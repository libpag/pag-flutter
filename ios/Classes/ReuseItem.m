//
//  ReuseItem.m
//  ReuseItem
//
//  Created by liampan on 2025/1/9.
//  Copyright © 2025 Tencent. All rights reserved.
//

#import "ReuseItem.h"
#import <Foundation/Foundation.h>
@interface ReuseItem()
/// 自身纹理id
@property (nonatomic, strong) NSNumber* textureId;
/// 自身viewId flutter端静态自增
@property (nonatomic, strong) NSNumber* viewId;
/// pag data 宽
@property (nonatomic, assign) double width;
/// pag data 高
@property (nonatomic, assign) double height;
@end

@implementation ReuseItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _textureId = @-1;
        _usingViewSet = [[NSMutableSet alloc] init];
        _width = 0;
        _height = 0;
        _reuseKey = nil;
        _mutableResultsArray = [NSMutableArray array];
    }
    return self;
}

- (void)setUpWithTextureId:(NSNumber*)textureId width:(double)width height:(double)height{
    _width = width;
    _height = height;
    _textureId = textureId;
}

- (NSNumber*) getTextureId{
    return _textureId;
}

- (double) getHeight{
    return _height;
}

- (double) getWidth{
    return _width;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"ReuseItem{textureId=%ld, usingViewSetNum=%lu, width=%ld, height=%ld}",
            (long)_textureId,
            (unsigned long)[_usingViewSet count],
            (long)_width,
            (long)_height];
}

@end
