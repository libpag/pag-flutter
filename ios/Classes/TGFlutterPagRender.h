//
//  TGFlutterPageRender.h
//  Tgclub
//
//  Created by 黎敬茂 on 2021/11/25.
//  Copyright © 2021 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

#define EventStart @"onAnimationStart"
#define EventEnd @"onAnimationEnd"
#define EventCancel @"onAnimationCancel"
#define EventRepeat @"onAnimationRepeat"

typedef void(^FrameUpdateCallback)(void);

typedef void(^PAGEventCallback)(NSString *);
//用于异步同步执行时序处理
//缓存对象时序：set -> released -> set -> release -> ... -> dealloc
//非缓存对象时序：set -> released ->dealloc
typedef NS_ENUM(NSInteger, ObjectState) {
    ObjectStateSet,                   // render设置surface资源完成
    ObjectStateReleased,             // render释放surface cache完成
};
/**
 Pag纹理渲染类
 */
@interface TGFlutterPagRender : NSObject<FlutterTexture>

///当前pag的size
@property(nonatomic, readonly) CGSize size;

@property (nonatomic, assign) ObjectState state;

@property (nonatomic, strong)NSNumber* textureId;

- (instancetype)init;

- (void)setUpWithPagData:(NSData*)pagData
                       progress:(double)initProgress
            frameUpdateCallback:(FrameUpdateCallback)frameUpdateCallback
                  eventCallback:(PAGEventCallback)eventCallback;

- (void)startRender;

- (void)stopRender;

- (void)pauseRender;

- (void)invalidateDisplayLink;

- (void)clearSurface;

- (void)setProgress:(double)progress;

- (void)setRepeatCount:(int)repeatCount;

- (NSArray<NSString *> *)getLayersUnderPoint:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
