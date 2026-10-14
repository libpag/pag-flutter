//
//  TGFlutterPageRender.m
//  Tgclub
//
//  Created by 黎敬茂 on 2021/11/25.
//  Copyright © 2021 Tencent. All rights reserved.
//

#import "TGFlutterPagRender.h"
#import "TGFlutterWorkerExecutor.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>
#include <libpag/PAGPlayer.h>
#include <chrono>
#include <cmath>
#include <mutex>

@interface TGFlutterPagRender()

@property(nonatomic, strong)PAGSurface *surface;

@property(nonatomic, strong)PAGPlayer* player;

@property(nonatomic, strong)PAGFile* pagFile;

@property(nonatomic, assign)double initProgress;

@property(nonatomic, assign)BOOL endEvent;


@end

static int64_t GetCurrentTimeUS() {
  static auto START_TIME = std::chrono::high_resolution_clock::now();
  auto now = std::chrono::high_resolution_clock::now();
  auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(now - START_TIME);
  return static_cast<int64_t>(ns.count() * 1e-3);
}

@implementation TGFlutterPagRender
{
    FrameUpdateCallback _frameUpdateCallback;
    PAGEventCallback _eventCallback;
    CADisplayLink *_displayLink;
    int _lastUpdateTs;
    int _repeatCount;
    int64_t start;
    int64_t _currRepeatCount;
    BOOL _playbackEnded;
    // Serializes access to the timeline state (start, _currRepeatCount, _endEvent,
    // _playbackEnded). copyPixelBuffer runs on the Flutter raster thread while the
    // control methods run on the platform thread and the setup runs on a worker
    // queue, so these ivars need a lock. A dedicated lock is used instead of
    // @synchronized(self) because setUpWithPagData holds the self monitor for the
    // whole PAGFile load, and the raster thread must not stall behind file loading.
    // The lock is never held across PAGPlayer/PAGFile calls.
    NSLock *_timelineLock;
}

- (CVPixelBufferRef)copyPixelBuffer {
    
    int64_t duration = [_player duration];
    if(duration <= 0){
        duration = 1;
    }

    int64_t timestamp = GetCurrentTimeUS();
    double value = 0;
    BOOL fireEndEvent = NO;
    BOOL fireRepeatEvent = NO;
    [_timelineLock lock];
    if(start <= 0){
        start = timestamp;
    }
    auto count = (timestamp - start) / duration;
    if (_repeatCount >= 0 && count >= _repeatCount) {
        value = 1;
        if(!_endEvent){
            _endEvent = YES;
            _playbackEnded = YES;
            fireEndEvent = YES;
        }
    } else {
        _endEvent = NO;
        _playbackEnded = NO;
        double playTime = (timestamp - start) % duration;
        value = static_cast<double>(playTime) / duration;
        if (_currRepeatCount < count) {
            _currRepeatCount = count;
            fireRepeatEvent = YES;
        }
    }
    [_timelineLock unlock];
    if (fireEndEvent) {
        _eventCallback(EventEnd);
    }
    if (fireRepeatEvent) {
        _eventCallback(EventRepeat);
    }
    [_player setProgress:value];
    [_player flush];
    CVPixelBufferRef target = [_surface getCVPixelBuffer];
    CVBufferRetain(target);
    return target;
}

- (instancetype)init
{
    if (self = [super init]) {
        _textureId = @-1;
        _timelineLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)setUpWithPagData:(NSData*)pagData
                       progress:(double)initProgress
            frameUpdateCallback:(FrameUpdateCallback)frameUpdateCallback
                  eventCallback:(PAGEventCallback)eventCallback
{
    _frameUpdateCallback = frameUpdateCallback;
    _eventCallback = eventCallback;
    _initProgress = initProgress;
    if(pagData){
        if ([[TGFlutterWorkerExecutor sharedInstance] enableMultiThread]) {
            // 防止setup和release、dealloc并行争抢
            @synchronized(self) {
                if(self){
                    [self setUpPlayerWithPagData:pagData];
                }
            }
        } else{
            [self setUpPlayerWithPagData:pagData];
        }
    }
}

- (void) setUpPlayerWithPagData:(NSData*)pagData
{
    _pagFile = [PAGFile Load:pagData.bytes size:pagData.length];
    if (!_player) {
        _player = [[PAGPlayer alloc] init];
    }
    [_player setComposition:_pagFile];
    _surface = [PAGSurface MakeOffscreen:CGSizeMake(_pagFile.width, _pagFile.height)];
    [_player setSurface:_surface];
    [self applyProgress:_initProgress];
    _frameUpdateCallback();
}

- (void)startRender
{
    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(update)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    int64_t duration = [_player duration];
    if (duration > 0) {
        int64_t timestamp = GetCurrentTimeUS();
        double frozenProgress = [_player getProgress];
        [_timelineLock lock];
        if (_playbackEnded) {
            // The animation finished and the timeline is pinned at the end. Restart
            // from the beginning, matching Android's animator.start() on an ended
            // animation.
            start = timestamp;
            _currRepeatCount = 0;
            _playbackEnded = NO;
            _endEvent = NO;
        } else if (start > 0) {
            // Re-anchor the timeline base to the frozen progress (plus the rounds
            // already played) so resuming does not skip the wall-clock time elapsed
            // while paused or stopped. This is the counterpart of Android's
            // animator.pause()/start() semantics.
            start = timestamp - static_cast<int64_t>((_currRepeatCount + frozenProgress) * duration);
        } else {
            start = timestamp;
        }
        [_timelineLock unlock];
    } else if (start <= 0) {
        start = GetCurrentTimeUS();
    }
    _eventCallback(EventStart);
}

- (void)stopRender
{
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    [self applyProgress:_initProgress];
    _frameUpdateCallback();
    BOOL fireEndEvent = NO;
    [_timelineLock lock];
    if(!_endEvent){
        _endEvent = YES;
        fireEndEvent = YES;
    }
    [_timelineLock unlock];
    if (fireEndEvent) {
        _eventCallback(EventEnd);
    }
    _eventCallback(EventCancel);
}

- (void)pauseRender{
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    // The timeline is re-anchored to the frozen progress in startRender on
    // resume, so there is nothing to adjust here.
}
- (void)setRepeatCount:(int)repeatCount{
    _repeatCount = repeatCount;
}

- (void)setProgress:(double)progress{
    [self applyProgress:progress];
    _frameUpdateCallback();
}

// Single entry point for every externally requested progress change (Dart
// setProgress, stop, and initial setup). It clamps the value, aligns the
// wall-clock timeline with it, and pushes it to the player. copyPixelBuffer
// recomputes the progress from the timeline on every rendered frame, so
// skipping any of these steps lets the next frame overwrite the requested
// value. NaN is mapped to 0 because the clamp macros do not reject it.
- (void)applyProgress:(double)progress {
    if (std::isnan(progress)) {
        progress = 0.0;
    }
    progress = std::fmax(0.0, std::fmin(1.0, progress));
    [self syncTimelineToProgress:progress];
    [_player setProgress:progress];
    [_player flush];
}

// copyPixelBuffer derives the play progress from wall-clock time. Align the
// timeline base with the requested progress (the counterpart of Android's
// animator.setCurrentPlayTime) so the next rendered frame advances from the
// set progress instead of overwriting it with the stale timeline.
- (void)syncTimelineToProgress:(double)progress {
    int64_t duration = [_player duration];
    if (duration <= 0) {
        [_timelineLock lock];
        start = -1;
        [_timelineLock unlock];
        return;
    }
    int64_t playedTime = static_cast<int64_t>(progress * duration);
    [_timelineLock lock];
    start = GetCurrentTimeUS() - playedTime;
    _currRepeatCount = playedTime / duration;
    // A reposition invalidates the ended state, so a later start resumes from
    // the new progress instead of replaying from the beginning.
    _playbackEnded = NO;
    [_timelineLock unlock];
}

- (NSArray<NSString *> *)getLayersUnderPoint:(CGPoint)point{
    NSArray<PAGLayer*>* layers = [_player getLayersUnderPoint:point];
    NSMutableArray<NSString *> *layerNames = [[NSMutableArray alloc] init];
    for (PAGLayer *layer in layers) {
        [layerNames addObject:layer.layerName];
    }
    return layerNames;
}

- (CGSize)size{
    return CGSizeMake(_pagFile.width, _pagFile.height);
}

- (void)update
{
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
                if (_surface){
                    [_surface freeCache];
                    [_surface clearAll];
                }
            }
        } else{
            [_surface freeCache];
            [_surface clearAll];
        }
    }
}

/// 清除Pagrender时序
- (void)clearPagState {
    [_timelineLock lock];
    start = -1;
    _endEvent = NO;
    _playbackEnded = NO;
    [_timelineLock unlock];
}

- (void)dealloc {
    _frameUpdateCallback = nil;
    _eventCallback = nil;
    _surface = nil;
    _pagFile = nil;
    _player = nil;
}
@end
