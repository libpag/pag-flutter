//
//  FlutterPagPlugin.m
//  FlutterPagPlugin
//
//  Created by 黎敬茂 on 2022/3/14.
//  Copyright © 2022 Tencent. All rights reserved.
//
#import "FlutterPagPlugin.h"
#import "TGFlutterPagRender.h"
#import "TGFlutterPagDownloadManager.h"
#import "TGFlutterWorkerExecutor.h"

/**
 FlutterPagPlugin，处理flutter MethodChannel约定的方法
 */
#define PlayCallback @"PAGCallback"
#define ArgumentEvent @"PAGEvent"
#define ArgumentTextureId @"textureId"
#define EnableCache @"enableCache"
#define SetCacheSize @"setCacheSize"
#define EnableMultiThread @"enableMultiThread"

@interface FlutterPagPlugin()

/// flutter引擎注册的textures对象
@property(nonatomic, weak) NSObject<FlutterTextureRegistry>* textures;

/// flutter引擎注册的registrar对象
@property(nonatomic, weak) NSObject<FlutterPluginRegistrar>* registrar;

/// 保存textureId跟render对象的对应关系
@property (nonatomic, strong) NSMutableDictionary *renderMap;

/// pag对象的缓存
@property (nonatomic, strong)NSCache<NSString*, NSData *> *cache;

/// 用于通信的channel
@property (nonatomic, strong)FlutterMethodChannel* channel;

///  缓存TGFlutterPagRender textureId，renderMap持有相应TGFlutterPagRender(release完成的)
@property (nonatomic, strong) NSMutableArray<NSNumber *> *freeEntryPool;

/// 开启TGFlutterPagRender 缓存
@property (nonatomic, assign) BOOL enableRenderCache;

///TGFlutterPagRender 缓存大小
@property (nonatomic, assign) NSInteger maxFreePoolSize;


@end

@implementation FlutterPagPlugin
- (instancetype)init {
    self = [super init];
    if (self) {
        _enableRenderCache = YES;
        _maxFreePoolSize = 10;
        _freeEntryPool = [[NSMutableArray alloc] init];
        _renderMap = [[NSMutableDictionary alloc] init];
    }
    return self;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"flutter_pag_plugin"
            binaryMessenger:[registrar messenger]];
  FlutterPagPlugin* instance = [[FlutterPagPlugin alloc] init];
    instance.textures = registrar.textures;
    instance.registrar = registrar;
    instance.channel = channel;
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)getLayersUnderPoint:(id)arguments result:(FlutterResult _Nonnull)result {
    NSNumber* textureId = arguments[@"textureId"];
    NSNumber* x = arguments[@"x"];
    NSNumber* y = arguments[@"y"];
    TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
    NSArray<NSString *> *names = [render getLayersUnderPoint:CGPointMake(x.doubleValue, y.doubleValue)];
    result(names);
}

- (void)release:(id)arguments result:(FlutterResult _Nonnull)result {
    NSNumber *textureId = arguments[@"textureId"];
    if (textureId == 0) {
        result(@"");
        return;
    }
    TGFlutterPagRender *render = _renderMap[textureId];
    if (render == NULL){
        result(@"");
        return;
    }
    [render releaseRender];
    [render setReleaseDone:TRUE];
    BOOL shouldAddToFreePool = _enableRenderCache && self.freeEntryPool.count < self.maxFreePoolSize;
    if (shouldAddToFreePool) {
        [self.freeEntryPool addObject:textureId];
    } else {
        [_textures unregisterTexture:textureId.intValue];
        [render setTextureId:@-1];
        [self.renderMap removeObjectForKey:textureId];
    }
    result(@"");
}

- (void)setProgress:(id)arguments result:(FlutterResult _Nonnull)result {
    NSNumber* textureId = arguments[@"textureId"];
    if(textureId == nil){
        result(@"");
        return;
    }
    double progress = 0.0;
    if (arguments[@"progress"]) {
        progress = [arguments[@"progress"] doubleValue];
    }
    TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
    [render setProgress:progress];
    result(@"");
}

- (void)pause:(id)arguments result:(FlutterResult _Nonnull)result {
    NSNumber* textureId = arguments[@"textureId"];
    if(textureId == nil){
        result(@"");
        return;
    }
    TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
    [render pauseRender];
    result(@"");
}

- (void)stop:(id)arguments result:(FlutterResult _Nonnull)result {
    NSNumber* textureId = arguments[@"textureId"];
    if(textureId == nil){
        result(@"");
        return;
    }
    TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
    [render stopRender];
    result(@"");
}

- (void)start:(id)arguments result:(FlutterResult _Nonnull)result {
    NSNumber* textureId = arguments[@"textureId"];
    if(textureId == nil){
        result(@"");
        return;
    }
    TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
    [render startRender];
    result(@"");
}

- (void)initPag:(id)arguments result:(FlutterResult _Nonnull)result {
    if (arguments == nil || (arguments[@"assetName"] == NSNull.null && arguments[@"url"] == NSNull.null && arguments[@"bytesData"] == NSNull.null)) {
        result(@-1);
        NSLog(@"showPag arguments is nil");
        return;
    }
    double initProgress = 0.0;
    if (arguments[@"initProgress"]) {
        initProgress = [arguments[@"initProgress"] doubleValue];
    }
    int repeatCount = -1;
    if(arguments[@"repeatCount"]){
        repeatCount = [[arguments objectForKey:@"repeatCount"] intValue];
    }
    
    BOOL autoPlay = NO;
    if(arguments[@"autoPlay"]){
        autoPlay = [[arguments objectForKey:@"autoPlay"] boolValue];
    }
    
    NSString* assetName = arguments[@"assetName"];
    NSData *pagData = nil;
    if ([assetName isKindOfClass:NSString.class] && assetName.length > 0) {
        NSString *key = assetName;
        pagData = [self getCacheData:key];
        if (!pagData) {
            NSString* package = arguments[@"package"];
            NSString* resourcePath;
            if(package && [package isKindOfClass:NSString.class] && package.length > 0){
                resourcePath = [self.registrar lookupKeyForAsset:assetName fromPackage:package];
            }else{
                resourcePath = [self.registrar lookupKeyForAsset:assetName];
            }

            resourcePath = [[NSBundle mainBundle] pathForResource:resourcePath ofType:nil];
            
            pagData = [NSData dataWithContentsOfFile:resourcePath];
            [self setCacheData:key data:pagData];
            
        }
        [self pagRenderWithPagData:pagData progress:initProgress repeatCount:repeatCount autoPlay:autoPlay result:result];
    }
    NSString* url = arguments[@"url"];
    if ([url isKindOfClass:NSString.class] && url.length > 0) {
        NSURLSessionDownloadTask *task;
        [task resume];
        NSString *key = url;
        pagData = [self getCacheData:key];
        if (!pagData) {
            __weak typeof(self) weak_self = self;
            [TGFlutterPagDownloadManager download:url completionHandler:^(NSData * _Nonnull data, NSError * _Nonnull error) {
                if (data) {
                    [weak_self setCacheData:key data:pagData];
                    [weak_self pagRenderWithPagData:data progress:initProgress repeatCount:repeatCount autoPlay:autoPlay result:result];
                }else{
                    result(@-1);
                }
            }];
        }else{
            [self pagRenderWithPagData:pagData progress:initProgress repeatCount:repeatCount autoPlay:autoPlay result:result];
        }
    }
    
    id bytesData = arguments[@"bytesData"];
    if(bytesData != nil && [bytesData isKindOfClass:FlutterStandardTypedData.class]){
        FlutterStandardTypedData *typedData = bytesData;
        if(typedData.type == FlutterStandardDataTypeUInt8 && typedData.data != nil){
            [self pagRenderWithPagData:typedData.data progress:initProgress repeatCount:repeatCount autoPlay:autoPlay result:result];
        }else{
            result(@-1);
        }
    }
}

- (void)enableCache:(id)arguments result:(FlutterResult _Nonnull)result {
    BOOL enable = YES; // 默认开启render cache
    if ([arguments isKindOfClass:[NSDictionary class]]) {
        id enableValue = [arguments objectForKey:EnableCache];
        if ([enableValue isKindOfClass:[NSNumber class]]) {
            enable = [enableValue boolValue];
        }
    }
    _enableRenderCache = enable;
    result(@"");
}

- (void)setCacheSize:(id)arguments result:(FlutterResult _Nonnull)result {
    NSInteger maxSize = self.maxFreePoolSize;
    if ([arguments isKindOfClass:[NSDictionary class]]) {
        id sizeValue = [arguments objectForKey:SetCacheSize];
        if ([sizeValue isKindOfClass:[NSNumber class]]) {
            maxSize = [sizeValue integerValue];
        }
    }
    _maxFreePoolSize = maxSize;
    result(@"");
}

- (void)enableMultiThread:(id)arguments result:(FlutterResult _Nonnull)result {
    BOOL enable = YES; // 默认开启 MultiThread
    if ([arguments isKindOfClass:[NSDictionary class]]) {
        id enableValue = [arguments objectForKey:EnableMultiThread];
        if ([enableValue isKindOfClass:[NSNumber class]]) {
            enable = [enableValue boolValue];
        }
    }
    [[TGFlutterWorkerExecutor sharedInstance] setEnableMultiThread:enable];
    result(@"");
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    
    id arguments = call.arguments;
    if ([@"getPlatformVersion" isEqualToString:call.method]) {
        result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    } else if([@"initPag" isEqualToString:call.method]){
        [self initPag:arguments result:result];
    } else if([@"start" isEqualToString:call.method]){
        [self start:arguments result:result];
    } else if([@"stop" isEqualToString:call.method]){
        [self stop:arguments result:result];
    } else if([@"pause" isEqualToString:call.method]){
        [self pause:arguments result:result];
    } else if([@"setProgress" isEqual:call.method]){
        [self setProgress:arguments result:result];
    } else if([@"release" isEqualToString:call.method]){
        [self release:arguments result:result];
    } else if([@"getLayersUnderPoint" isEqualToString:call.method]){
        [self getLayersUnderPoint:arguments result:result];
    } else if([EnableCache isEqualToString:call.method]){
        [self enableCache:arguments result:result];
    } else if([SetCacheSize isEqualToString:call.method]){
        [self setCacheSize:arguments result:result];
    } else if([EnableMultiThread isEqualToString:call.method]){
        [self enableMultiThread:arguments result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

-(void)pagRenderWithPagData:(NSData *)pagData progress:(double)progress repeatCount:(int)repeatCount autoPlay:(BOOL)autoPlay result:(FlutterResult)result {
    __block int64_t textureId = -1;
    __weak typeof(self) weakSelf = self;
    __block TGFlutterPagRender *render;
    if (!_enableRenderCache || _freeEntryPool.count <= 0) {
        render = [[TGFlutterPagRender alloc] init];
        textureId = [_textures registerTexture:render];
        [render setTextureId:[NSNumber numberWithLongLong:textureId]];
        [weakSelf.renderMap setObject:render forKey:@(textureId)];
    } else {
        NSNumber* renderCacheTextureId = [weakSelf getRenderCacheTextureId];
        textureId = [renderCacheTextureId longLongValue];
        [weakSelf.freeEntryPool removeObjectAtIndex:0];
        render = [weakSelf.renderMap objectForKey:renderCacheTextureId];
        if (render == NULL){
            result([FlutterError errorWithCode:@"-1101"
                                      message:@"id异常，未命中缓存！"
                                      details:nil]);
            return;
        }
        if ([render releaseDone]){
            result([FlutterError errorWithCode:@"-1102"
                                      message:@"TGFlutterPagRender异常！"
                                      details:nil]);
            return;
        }
    }
    [[TGFlutterWorkerExecutor sharedInstance] post:^(){
        if ([render releaseDone]){
            return;
        }
        [render setUpWithPagData:pagData progress:progress frameUpdateCallback:^{
            [weakSelf.textures textureFrameAvailable:textureId];
        } eventCallback:^(NSString *event) {
            [weakSelf.channel invokeMethod:PlayCallback arguments:@{ArgumentTextureId:@(textureId), ArgumentEvent:event}];
        }];
        [render setRepeatCount:repeatCount];
        dispatch_async(dispatch_get_main_queue(), ^(){
            if (autoPlay) {
                [render startRender];
            }
            result(@{@"textureId": @(textureId), @"width": @([render size].width), @"height": @([render size].height)});
        });
    }];
}

-(NSNumber *) getRenderCacheTextureId{
    if (_freeEntryPool.count <= 0){
        return NULL;
    }
    return _freeEntryPool[0];
}

-(NSData *)getCacheData:(NSString *)key{
    return [self.cache objectForKey:key];
}

-(void)setCacheData:(NSString *)key data:(NSData *)data{
    if (data == nil || key == nil) {
        return;
    }
    [self.cache setObject:data forKey:key cost:data.length];
}

-(NSCache *)cache{
    if (!_cache) {
        _cache = [[NSCache alloc] init];
        ///缓存64m
        _cache.totalCostLimit = 64*1024*1024;
        _cache.countLimit = 32;
    }
    return _cache;
}
@end
