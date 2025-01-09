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
}

- (CVPixelBufferRef)copyPixelBuffer {
    
    int64_t duration = [_player duration];
    if(duration <= 0){
        duration = 1;
    }

    int64_t timestamp = GetCurrentTimeUS();
    if(start <= 0){
        start = timestamp;
    }
    auto count = (timestamp - start) / duration;
    double value = 0;
    if (_repeatCount >= 0 && count >= _repeatCount) {
        value = 1;
        if(!_endEvent){
            _endEvent = YES;
            _eventCallback(EventEnd);
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
                [self setUpPlayerWithPagData:pagData];
            }
        } else{
            [self setUpPlayerWithPagData:pagData];
        }
    }
    _state = ObjectStateSet;
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
    [_player setProgress: _initProgress];
    [_player flush];
    _frameUpdateCallback();
}

- (void)startRender
{
    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(update)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    if(start <= 0){
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
    [_player setProgress:_initProgress];
    [_player flush];
    _frameUpdateCallback();
    if(!_endEvent){
        _endEvent = YES;
        _eventCallback(EventEnd);
    }
    _eventCallback(EventCancel);
}

- (void)pauseRender{
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
}
- (void)setRepeatCount:(int)repeatCount{
    _repeatCount = repeatCount;
}

- (void)setProgress:(double)progress{
    [_player setProgress:progress];
    [_player flush];
    _frameUpdateCallback();
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
        [_surface freeCache];
        [_surface clearAll];
    }
    _state = ObjectStateReleased;
}

- (void)dealloc {
    _frameUpdateCallback = nil;
    _eventCallback = nil;
    _surface = nil;
    self.pagFile = nil;
    self.player = nil;
}
@end
