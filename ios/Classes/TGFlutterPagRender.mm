//
//  TGFlutterPageRender.m
//  Tgclub
//
//  Created by 黎敬茂 on 2021/11/25.
//  Copyright © 2021 Tencent. All rights reserved.
//

#import "TGFlutterPagRender.h"
#import "TGFlutterWorkerExecutor.h"
#import <CoreVideo/CoreVideo.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <UIKit/UIKit.h>
#include <chrono>
#include <libpag/PAGPlayer.h>
#include <mutex>

@interface TGFlutterPagRender ()

@property(nonatomic, strong) PAGSurface *surface;

@property(nonatomic, strong) PAGPlayer *player;

@property(nonatomic, strong) PAGFile *pagFile;

@property(nonatomic, assign) double initProgress;

@property(nonatomic, assign) BOOL endEvent;

@property(nonatomic, assign) double lastProgress;

@property(atomic, assign) BOOL isAppActive;

@end

static int64_t GetCurrentTimeUS() {
  static auto START_TIME = std::chrono::high_resolution_clock::now();
  auto now = std::chrono::high_resolution_clock::now();
  auto ns =
      std::chrono::duration_cast<std::chrono::nanoseconds>(now - START_TIME);
  return static_cast<int64_t>(ns.count() * 1e-3);
}

@implementation TGFlutterPagRender {
  FrameUpdateCallback _frameUpdateCallback;
  PAGEventCallback _eventCallback;
  CADisplayLink *_displayLink;
  int _lastUpdateTs;
  int _repeatCount;
  int64_t start;
  int64_t _currRepeatCount;
}

- (CVPixelBufferRef)copyPixelBuffer {

  // 确保动画逻辑仅在 display link 处于活动状态且未暂停时运行
  if (_displayLink && !_displayLink.paused) {
    // 检查应用状态：仅在应用处于 Active 状态时推进动画进度。
    // 这可以防止在系统弹窗（Inactive 状态）或后台时进行“幽灵”播放。
    if (self.isAppActive) {
      int64_t duration = [_player duration];
      if (duration <= 0) {
        duration = 1;
      }

      // 基于自 start 以来经过的时间计算当前动画进度
      int64_t timestamp = GetCurrentTimeUS();
      if (start <= 0) {
        start = timestamp;
      }
      auto count = (timestamp - start) / duration;

      // 兜底：如果 `_lastProgress`
      // 无效（0）但播放器有有效进度，则使用播放器的进度。
      // 这处理了初始化期间的边缘情况。
      double value = _lastProgress;
      if (value <= 0 && [_player getProgress] > 0) {
        value = [_player getProgress];
      }

      // 处理动画循环/完成
      if (_repeatCount >= 0 && count >= _repeatCount) {
        value = 1;
        if (!_endEvent) {
          _endEvent = YES;
          _eventCallback(EventEnd);
          // 动画完成后停止渲染循环以节省资源
          __block typeof(self) blockSelf = self;
          dispatch_async(dispatch_get_main_queue(), ^{
            [blockSelf pauseRender];
          });
        }
      } else {
        _endEvent = NO;
        double playTime = (timestamp - start) % duration;
        value = static_cast<double>(playTime) / duration;
        if (_currRepeatCount < count) {
          _currRepeatCount = count;
          _eventCallback(EventRepeat);
        }
      }

      // 应用计算出的进度并进行缓存
      [_player setProgress:value];
      _lastProgress = value;
    } else {
      // 非活动状态（例如权限弹窗）：
      // 不要调用 setProgress。依赖 `flush` 保持渲染最后一帧有效画面。
      // 在此处调用带有过时值的 setProgress 可能会导致闪烁或黑屏。
    }
  }

  // 始终 flush 以确保 surface 更新（无论是新进度还是保持最后一帧）
  [_player flush];
  CVPixelBufferRef target = [_surface getCVPixelBuffer];

  // 保护措施：如果上下文丢失则重建 Surface
  // 如果 `target` 为 nil，意味着底层的 PAGSurface 或 GPU 上下文可能无效
  // （例如在权限切换等重大应用状态变更后）。
  if (target == nil && _pagFile != nil) {
    NSLog(@"TGFlutterPagRender: Surface lost, recreating...");
    _surface =
        [PAGSurface MakeOffscreen:CGSizeMake(_pagFile.width, _pagFile.height)];
    [_player setSurface:_surface];
    [_player setProgress:_lastProgress];
    [_player flush];
    target = [_surface getCVPixelBuffer];
  }
  if (target) {
    CVBufferRetain(target); // 只有在指针有效时才增加引用计数
  }
  return target;
}

- (instancetype)init {
  if (self = [super init]) {
    _textureId = @-1;
    // 基于当前应用状态初始化 active 状态（init 中在主线程是安全的）
    _isAppActive = [UIApplication sharedApplication].applicationState ==
                   UIApplicationStateActive;

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           // 进入后台时暂停动画以节省资源
           selector:@selector(applicationDidEnterBackground)
               name:UIApplicationDidEnterBackgroundNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           // 即将进入前台时恢复动画
           selector:@selector(applicationWillEnterForeground)
               name:UIApplicationWillEnterForegroundNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationWillResignActive)
               name:UIApplicationWillResignActiveNotification
             object:nil];
    // 变为 Active 时重新校准时间并强制 flush
    // （处理如弹窗消失等 Inactive->Active 的过渡）
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationDidBecomeActive)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];
  }
  return self;
}

- (void)setUpWithPagData:(NSData *)pagData
                progress:(double)initProgress
     frameUpdateCallback:(FrameUpdateCallback)frameUpdateCallback
           eventCallback:(PAGEventCallback)eventCallback {
  _frameUpdateCallback = frameUpdateCallback;
  _eventCallback = eventCallback;
  _initProgress = initProgress;
  if (pagData) {
    if ([[TGFlutterWorkerExecutor sharedInstance] enableMultiThread]) {
      // 防止setup和release、dealloc并行争抢
      @synchronized(self) {
        if (self) {
          [self setUpPlayerWithPagData:pagData];
        }
      }
    } else {
      [self setUpPlayerWithPagData:pagData];
    }
  }
}

- (void)setUpPlayerWithPagData:(NSData *)pagData {
  _pagFile = [PAGFile Load:pagData.bytes size:pagData.length];
  if (!_player) {
    _player = [[PAGPlayer alloc] init];
  }
  [_player setComposition:_pagFile];
  _surface =
      [PAGSurface MakeOffscreen:CGSizeMake(_pagFile.width, _pagFile.height)];
  [_player setSurface:_surface];
  _lastProgress = _initProgress; // 初始化缓存
  [_player setProgress:_initProgress];
  [_player flush];
  _frameUpdateCallback();
}

- (void)startRender {
  if (!_displayLink) {
    _displayLink = [CADisplayLink displayLinkWithTarget:self
                                               selector:@selector(update)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                       forMode:NSRunLoopCommonModes];
  }
  // 修复：始终基于当前进度重新计算 `start` 时间，防止使用过时的 start
  // 时间导致动画跳变或立即结束。
  int64_t duration = [_player duration];
  if (duration <= 0) {
    duration = 1;
  }
  double currentProgress = [_player getProgress];
  start = GetCurrentTimeUS() - (int64_t)(currentProgress * duration);
  _eventCallback(EventStart);
}

- (void)stopRender {
  if (_displayLink) {
    [_displayLink invalidate];
    _displayLink = nil;
  }
  [_player setProgress:_initProgress];
  [_player flush];
  _frameUpdateCallback();
  if (!_endEvent) {
    _endEvent = YES;
    _eventCallback(EventEnd);
  }
  _eventCallback(EventCancel);
}

- (void)pauseRender {
  if (_displayLink) {
    [_displayLink invalidate];
    _displayLink = nil;
  }
}
- (void)setRepeatCount:(int)repeatCount {
  _repeatCount = repeatCount;
}

- (void)setProgress:(double)progress {
  [_player setProgress:progress];
  [_player flush];
  _frameUpdateCallback();

  // 修复：手动设置进度时重置重复计数和结束状态
  _currRepeatCount = 0;
  _endEvent = NO;
  _lastProgress = progress; // 更新手动进度的缓存

  // 如果正在播放，立即调整 start 以防画面跳变；否则重置为0等待 startRender 处理
  if (_displayLink) {
    int64_t duration = [_player duration];
    if (duration <= 0) {
      duration = 1;
    }
    start = GetCurrentTimeUS() - (int64_t)(progress * duration);
  } else {
    start = 0;
  }
}

- (NSArray<NSString *> *)getLayersUnderPoint:(CGPoint)point {
  NSArray<PAGLayer *> *layers = [_player getLayersUnderPoint:point];
  NSMutableArray<NSString *> *layerNames = [[NSMutableArray alloc] init];
  for (PAGLayer *layer in layers) {
    [layerNames addObject:layer.layerName];
  }
  return layerNames;
}

- (CGSize)size {
  return CGSizeMake(_pagFile.width, _pagFile.height);
}

- (void)update {
  _frameUpdateCallback();
}

- (void)invalidateDisplayLink {
  if (_displayLink) {
    [_displayLink invalidate];
    _displayLink = nil;
  }
}

- (void)clearSurface {
  if (_surface) {
    if ([[TGFlutterWorkerExecutor sharedInstance] enableMultiThread]) {
      @synchronized(self) {
        if (_surface) {
          [_surface freeCache];
          [_surface clearAll];
        }
      }
    } else {
      [_surface freeCache];
      [_surface clearAll];
    }
  }
}

/// 清除Pagrender时序
- (void)clearPagState {
  if ([[TGFlutterWorkerExecutor sharedInstance] enableMultiThread]) {
    @synchronized(self) {
      start = -1;
      _endEvent = NO;
    }
  } else {
    start = -1;
    _endEvent = NO;
  }
}

- (void)applicationDidEnterBackground {
  if (_displayLink) {
    _displayLink.paused = YES;
  }
}

- (void)applicationWillEnterForeground {
  if (_displayLink) {
    // 仅唤醒循环
    _displayLink.paused = NO;
  }
}

// 当应用变为 Active 时重新校准动画计时
// 这处理了应用处于 Inactive（例如被系统弹窗覆盖）但未进入后台的情况。
// 它确保动画从中断处平滑继续，而不是向前跳跃。
- (void)applicationDidBecomeActive {
  self.isAppActive = YES;
  if (_displayLink && !_displayLink.paused) {
    int64_t duration = [_player duration];
    if (duration <= 0) {
      duration = 1;
    }
    double currentProgress = [_player getProgress];
    // 基于当前进度重置 `start` 时间，以忽略在 Inactive 状态下消耗的时间
    start = GetCurrentTimeUS() - (int64_t)(currentProgress * duration);

    // 强制 flush 以立即更新视图，确保返回时没有空白帧
    [_player flush];
  }
}

- (void)applicationWillResignActive {
  self.isAppActive = NO;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _frameUpdateCallback = nil;
  _eventCallback = nil;
  _surface = nil;
  _pagFile = nil;
  _player = nil;
}
@end
