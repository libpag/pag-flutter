//
//  ReuseItem.h
//  ReuseItem
//
//  Created by liampan on 2025/1/9.
//  Copyright © 2025 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/**
 复用render info类
 */
@interface ReuseItem : NSObject

/// 自身reuseKey pag资源路径
@property (nonatomic, strong) NSString* reuseKey;
/// 相同reuseKey的pagView端viewId 包括自身，生命周期同textureId的render
@property (nonatomic, strong) NSMutableSet<NSNumber *> *usingViewSet;
/// 相同reuseKey的pagView端viewId initPag method的FlutterResult 不包括自身，result回调后result置空并移除
@property (nonatomic, strong) NSMutableArray<FlutterResult> *mutableResultsArray;

- (instancetype)init;

- (void) setUpWithTextureId:(NSNumber*)textureId width:(double)width height:(double)height;

- (NSNumber*) getTextureId;

- (double) getHeight;

- (double) getWidth;

- (NSString *)description;

@end

NS_ASSUME_NONNULL_END
