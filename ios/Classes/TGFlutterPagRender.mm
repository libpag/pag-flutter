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


@end

// Playback lifecycle. A single enum replaces the previously scattered booleans
// (end-event fired / pinned at end / timeline initialized) so a state change
// happens in one place and cannot leave one flag stale while clearing another.
typedef NS_ENUM(NSInteger, TGPagPlaybackState) {
    TGPagPlaybackUninitialized = 0,  // the timeline has never been anchored
    TGPagPlaybackPlaying,            // advancing by wall clock from `start`
    TGPagPlaybackEnded,              // reached the natural end; pinned at the last frame, start() replays
    TGPagPlaybackStopped,            // held at a fixed position (stop/pause/setProgress), start() resumes from it
};

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
    // Wall-clock anchor while Playing: the total elapsed play time is (now - start).
    int64_t start;
    // Completed rounds, kept consistent with the current position; used only to
    // de-duplicate the repeat event across frames.
    int64_t _currRepeatCount;
    // Frozen total elapsed play time (microseconds, rounds included) while the
    // state is Stopped or Ended. It is the single source of truth for the held
    // position, so resuming never has to read the player progress back and add
    // the round count on top of it (which double-counted at progress == 1.0).
    int64_t _heldElapsed;
    TGPagPlaybackState _state;
    // Whether an onAnimationEnd has already been emitted for the current playback
    // episode. The lifecycle enum cannot carry this on its own: a single Stopped
    // state is reached both by stop() (which emits End) and by pause()/setProgress()
    // (which do not), so without a separate flag a second stop()-or a stop() after
    // the animation already ended-would emit a duplicate onAnimationEnd. It is set
    // when copyPixelBuffer reaches the natural end and when stopRender emits End,
    // and cleared whenever playback (re)starts.
    BOOL _endFired;
    // Serializes access to the timeline state (start, _currRepeatCount,
    // _heldElapsed, _state, _endFired). copyPixelBuffer runs on the Flutter raster thread
    // while the control methods run on the platform thread and the setup runs on
    // a worker queue, so these ivars need a lock. A dedicated lock is used instead
    // of @synchronized(self) because setUpWithPagData holds the self monitor for
    // the whole PAGFile load, and the raster thread must not stall behind file
    // loading. The lock is never held across PAGPlayer/PAGFile calls.
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
    if (_state == TGPagPlaybackUninitialized) {
        start = timestamp;
        _currRepeatCount = 0;
        _endFired = NO;
        _state = TGPagPlaybackPlaying;
    }
    // While held (Stopped/Ended) the frame is pinned to the frozen elapsed time,
    // so compositing the texture does not advance a paused or ended animation.
    int64_t elapsed = (_state == TGPagPlaybackPlaying) ? (timestamp - start) : _heldElapsed;
    int64_t count = elapsed / duration;
    if (_repeatCount >= 0 && count >= _repeatCount) {
        value = 1;
        if (_state == TGPagPlaybackPlaying) {
            _state = TGPagPlaybackEnded;
            _heldElapsed = static_cast<int64_t>(_repeatCount) * duration;
            _endFired = YES;
            fireEndEvent = YES;
        }
    } else {
        int64_t playTime = elapsed % duration;
        value = static_cast<double>(playTime) / duration;
        if (_state == TGPagPlaybackPlaying && _currRepeatCount < count) {
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
    [self applyProgress:_initProgress hold:NO];
    _frameUpdateCallback();
}

- (void)startRender
{
    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(update)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    int64_t timestamp = GetCurrentTimeUS();
    [_timelineLock lock];
    switch (_state) {
        case TGPagPlaybackEnded:
            // The animation finished and is pinned at the end. Restart from the
            // beginning, matching Android's animator.start() on an ended animation.
            start = timestamp;
            _currRepeatCount = 0;
            break;
        case TGPagPlaybackStopped:
            // Resume from the held position (set by pause, stop, or setProgress)
            // so the wall-clock time elapsed while held is not played. _heldElapsed
            // already carries the completed rounds, so there is no need to read the
            // player progress back and add the round count on top of it.
            start = timestamp - _heldElapsed;
            break;
        case TGPagPlaybackUninitialized:
            start = timestamp;
            _currRepeatCount = 0;
            break;
        case TGPagPlaybackPlaying:
            break;
    }
    _state = TGPagPlaybackPlaying;
    _endFired = NO;
    [_timelineLock unlock];
    _eventCallback(EventStart);
}

- (void)stopRender
{
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    // Freeze to the held position and decide the exactly-once EventEnd in
    // applyProgress's single critical section. Reading the state here under a
    // separate lock would let the raster thread transition Playing -> Ended (and
    // fire EventEnd) in between, making stopRender fire a second EventEnd off a
    // stale read; checking and setting _endFired inside that one critical section
    // also makes a second stop() (or a stop() after a natural end) a no-op for
    // EventEnd. hold:YES forces the frozen (Stopped) state even when stopping
    // mid-play, so the frame pins at initProgress, a later start() re-anchors
    // cleanly instead of fast-forwarding by the stop->start wall-clock gap, and
    // copyPixelBuffer can no longer end again. EventCancel is always emitted.
    BOOL shouldFireEnd = [self applyProgress:_initProgress hold:YES];
    _frameUpdateCallback();
    if (shouldFireEnd) {
        _eventCallback(EventEnd);
    }
    _eventCallback(EventCancel);
}

- (void)pauseRender{
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    int64_t duration = [_player duration];
    int64_t timestamp = GetCurrentTimeUS();
    [_timelineLock lock];
    if (_state == TGPagPlaybackPlaying) {
        // Freeze the current position so resuming continues from exactly here and
        // compositing the texture while paused no longer advances the animation.
        int64_t elapsed = timestamp - start;
        if (elapsed < 0) {
            elapsed = 0;
        }
        if (_repeatCount >= 0) {
            int64_t maxElapsed = static_cast<int64_t>(_repeatCount) * (duration > 0 ? duration : 1);
            if (elapsed > maxElapsed) {
                elapsed = maxElapsed;
            }
        }
        _heldElapsed = elapsed;
        _currRepeatCount = (duration > 0) ? (elapsed / duration) : 0;
        _state = TGPagPlaybackStopped;
    }
    [_timelineLock unlock];
}
- (void)setRepeatCount:(int)repeatCount{
    _repeatCount = repeatCount;
}

- (void)setProgress:(double)progress{
    [self applyProgress:progress hold:NO];
    _frameUpdateCallback();
}

// Single entry point for every externally requested progress change (Dart
// setProgress, stop, and initial setup). It clamps the value, aligns the
// wall-clock timeline with it, and pushes it to the player. copyPixelBuffer
// recomputes the progress from the timeline on every rendered frame, so
// skipping any of these steps lets the next frame overwrite the requested
// value. NaN is mapped to 0 because the clamp macros do not reject it.
//
// copyPixelBuffer derives the play progress from wall-clock time, so the
// timeline is realigned with the requested progress (the counterpart of
// Android's animator.setCurrentPlayTime). The round count is taken from this
// single value (playedTime / duration) rather than carried separately, which
// is what previously double-counted at progress == 1.0. A set made while
// playing re-anchors the live timeline so playback continues from the new
// value. hold:NO keeps a live set live: a set made while playing re-anchors the
// running timeline so playback continues from the new value (Dart setProgress
// mid-play); a set made while held/ended repositions the held state. hold:YES
// forces the frozen (Stopped) state regardless of the current state, which is
// what stop needs so the animation does not keep advancing after it was stopped.
// For the stop path (hold:YES) it also performs the exactly-once EventEnd
// check-and-set on _endFired inside the same critical section that performs the
// switch, and returns whether the caller (stopRender) should emit EventEnd, so a
// repeated stop or a stop after a natural end does not emit a duplicate End and
// no separate racy read is needed. hold:NO always returns NO.
- (BOOL)applyProgress:(double)progress hold:(BOOL)hold {
    if (std::isnan(progress)) {
        progress = 0.0;
    }
    progress = std::fmax(0.0, std::fmin(1.0, progress));
    int64_t duration = [_player duration];
    int64_t playedTime = (duration > 0) ? static_cast<int64_t>(progress * duration) : 0;
    int64_t timestamp = GetCurrentTimeUS();
    BOOL shouldFireEnd = NO;
    [_timelineLock lock];
    if (!hold && _state == TGPagPlaybackPlaying) {
        start = timestamp - playedTime;
    } else {
        if (hold) {
            shouldFireEnd = !_endFired;
            _endFired = YES;
        }
        _heldElapsed = playedTime;
        _state = TGPagPlaybackStopped;
    }
    _currRepeatCount = (duration > 0) ? (playedTime / duration) : 0;
    [_timelineLock unlock];
    [_player setProgress:progress];
    [_player flush];
    return shouldFireEnd;
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
    _state = TGPagPlaybackUninitialized;
    _heldElapsed = 0;
    _currRepeatCount = 0;
    _endFired = NO;
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
