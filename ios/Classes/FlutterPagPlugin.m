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
#import "ReuseItem.h"
/**
 FlutterPagPlugin，处理flutter MethodChannel约定的方法
 */
#define PlayCallback @"PAGCallback"
#define ArgumentEvent @"PAGEvent"
#define ArgumentTextureId @"textureId"
#define EnableCache @"enableCache"
#define SetCacheSize @"setCacheSize"
#define EnableMultiThread @"enableMultiThread"
#define EnableReuse @"enableReuse"

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

///  缓存TGFlutterPagRender textureId，release中的。处理release异步并行超出maxFreePoolSize
@property (nonatomic, strong) NSMutableArray<NSNumber *> *preFreeEntryPool;

/// 开启TGFlutterPagRender 缓存
@property (nonatomic, assign) BOOL enableRenderCache;

///TGFlutterPagRender 缓存大小
@property (nonatomic, assign) int maxFreePoolSize;

/// 开启TGFlutterPagRender 复用
@property (nonatomic, assign) BOOL enableReuse;

/// 保存reuseKey和对应复用信息对象
@property (nonatomic, strong) NSMutableDictionary<NSString *, ReuseItem *> *reuseMap;

@end

@implementation FlutterPagPlugin
- (instancetype)init {
    self = [super init];
    if (self) {
        _enableRenderCache = YES;
        _maxFreePoolSize = 10;
        _freeEntryPool = [[NSMutableArray alloc] init];
        _renderMap = [[NSMutableDictionary alloc] init];
        _reuseMap = [[NSMutableDictionary alloc] init];
        _enableReuse = YES;
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
    
    BOOL reuse = NO;
    if (arguments[@"reuse"]) {
        reuse = [[arguments objectForKey:@"reuse"] boolValue];
    }

    NSString *reuseKey = nil;
    if (arguments[@"reuseKey"]) {
        reuseKey = [arguments objectForKey:@"reuseKey"];
    }

    int viewId = -1;
    if (arguments[@"viewId"]) {
        viewId = [[arguments objectForKey:@"viewId"] intValue];
    }
    
    if (_enableReuse && reuse && reuseKey && [reuseKey length] > 0){
        ReuseItem *reuseItem = [_reuseMap objectForKey:reuseKey];
        if (reuseItem && [[reuseItem getTextureId] isEqual:textureId]){
            [[reuseItem usingViewSet] removeObject:@(viewId)];
            if ([reuseItem usingViewSet].count <= 0){
                // 复用列表为空 清除复用
                [_reuseMap removeObjectForKey:reuseKey];
            } else{
                return;
            }
        }
    }
    
    if (!textureId || [textureId compare:@0] == NSOrderedAscending) {
        result(@"");
        return;
    }
    TGFlutterPagRender *render = _renderMap[textureId];
    if (!render){
        result(@"");
        return;
    }
    
    // 异步并行release异常时序处理
    // release时同时dealloc或者relea 资源synchronized处理
    // release前未setup release判空处理
    // release前dealloc render判空处理
    __weak typeof(self) weakSelf = self;
    [render invalidateDisplayLink];
    [[TGFlutterWorkerExecutor sharedInstance] post:^(){
        if (!render) return;
        [render clearSurface];
        dispatch_async(dispatch_get_main_queue(), ^(){
            BOOL shouldAddToFreePool = weakSelf.enableRenderCache && weakSelf.freeEntryPool.count < weakSelf.maxFreePoolSize;
            if (shouldAddToFreePool) {
                [weakSelf.freeEntryPool addObject:textureId];
                NSLog(@"debug log relese pool add cache %@, pool size:%lu", textureId, (unsigned long) self->_freeEntryPool.count);
            } else {
                [weakSelf.textures unregisterTexture: textureId.intValue];
                [render setTextureId:@-1];
                [weakSelf.renderMap removeObjectForKey:textureId];
                NSLog(@"debug log relese %@, pool size:%lu", textureId, (unsigned long) self->_freeEntryPool.count);
            }
            result(@"");
        });
    }];

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
    
    BOOL reuse = NO;
    if (arguments[@"reuse"]) {
        reuse = [[arguments objectForKey:@"reuse"] boolValue];
    }

    NSString *reuseKey = nil;
    if (arguments[@"reuseKey"]) {
        reuseKey = [arguments objectForKey:@"reuseKey"];
    }

    int viewId = -1;
    if (arguments[@"viewId"]) {
        viewId = [[arguments objectForKey:@"viewId"] intValue];
    }
    
    if (_enableReuse && reuse){
        [self reuseSetupWithreuseKey:reuseKey viewId:viewId result:result];
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
        if (pagData){
            [self pagRenderWithPagData:pagData progress:initProgress repeatCount:repeatCount autoPlay:autoPlay result:result reuse:reuse reuseKey:reuseKey viewId:viewId];
        } else{
            FlutterError * flutterError = [FlutterError errorWithCode:@"-1100"
                                                              message:[NSString stringWithFormat:@"asset资源加载错误: %@", assetName]
                                                              details:nil];
            result(flutterError);
            [self onInitPagError:reuse reuseKey:reuseKey flutterError:flutterError];
        }

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
                    [weak_self pagRenderWithPagData:data progress:initProgress repeatCount:repeatCount autoPlay:autoPlay result:result reuse:reuse reuseKey:reuseKey viewId:viewId];
                }else{
                    FlutterError * flutterError = [FlutterError errorWithCode:@"-1100"
                                                                      message:[NSString stringWithFormat:@"url资源加载错误: %@", key]
                                                                      details:nil];
                    result(flutterError);
                    [self onInitPagError:reuse reuseKey:reuseKey flutterError:flutterError];
                }
            }];
        }else{
            [self pagRenderWithPagData:pagData progress:initProgress repeatCount:repeatCount autoPlay:autoPlay result:result reuse:reuse reuseKey:reuseKey viewId:viewId];
        }
    }
    
    id bytesData = arguments[@"bytesData"];
    if(bytesData != nil && [bytesData isKindOfClass:FlutterStandardTypedData.class]){
        FlutterStandardTypedData *typedData = bytesData;
        if(typedData.type == FlutterStandardDataTypeUInt8 && typedData.data != nil){
            [self pagRenderWithPagData:typedData.data progress:initProgress repeatCount:repeatCount autoPlay:autoPlay result:result reuse:reuse reuseKey:reuseKey viewId:viewId];
        }else{
            FlutterError * flutterError = [FlutterError errorWithCode:@"-1100"
                                                              message:@"bytesData 资源加载错误"
                                                              details:nil];
            result(flutterError);
            [self onInitPagError:reuse reuseKey:reuseKey flutterError:flutterError];
        }
    }
}

// 设置reuseKey 复用的render信息对象
- (void) reuseSetupWithreuseKey:(NSString *)reuseKey viewId:(int)viewId result:(FlutterResult)result {
    if (reuseKey && [reuseKey length] > 0){
        ReuseItem *reuseItem = [_reuseMap objectForKey:reuseKey];
        if (reuseItem && [reuseItem getTextureId] >= 0) {
            [reuseItem.usingViewSet addObject:@(viewId)];
            result(@{@"textureId": [reuseItem getTextureId], @"width": @([reuseItem getWidth]), @"height": @([reuseItem getHeight])});
            return;
        } else if (reuseItem) {
            [reuseItem.usingViewSet addObject:@(viewId)];
            [reuseItem.mutableResultsArray addObject:result];
            return;
        } else {
            ReuseItem *tempItem = [[ReuseItem alloc] init];
            [tempItem.usingViewSet addObject:@(viewId)];
            [_reuseMap setObject:tempItem forKey:reuseKey];
        }
    }
}

- (void)enableCache:(id)arguments result:(FlutterResult _Nonnull)result {
    BOOL enable = YES; // 默认开启render cache
    if ([arguments isKindOfClass:[NSDictionary class]]) {
        id enableValue = [arguments objectForKey:@"cacheEnabled"];
        if ([enableValue isKindOfClass:[NSNumber class]]) {
            enable = [enableValue boolValue];
        }
    }
    _enableRenderCache = enable;
    result(@"");
}

- (void)setCacheSize:(id)arguments result:(FlutterResult _Nonnull)result {
    int maxSize = 10;
    if ([arguments isKindOfClass:[NSDictionary class]]) {
        id sizeValue = [arguments objectForKey:@"cacheSize"];
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
        id enableValue = [arguments objectForKey:@"multiThreadEnabled"];
        if ([enableValue isKindOfClass:[NSNumber class]]) {
            enable = [enableValue boolValue];
        }
    }
    [[TGFlutterWorkerExecutor sharedInstance] setEnableMultiThread:enable];
    result(@"");
}

- (void)enableReuse:(id)arguments result:(FlutterResult _Nonnull)result {
    BOOL enable = YES; // 默认开启 enableReuse render 复用
    if ([arguments isKindOfClass:[NSDictionary class]]) {
        id enableValue = [arguments objectForKey:@"reuseEnabled"];
        if ([enableValue isKindOfClass:[NSNumber class]]) {
            enable = [enableValue boolValue];
        }
    }
    _enableReuse = enable;
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
    } else if([@"enableCache" isEqualToString:call.method]){
        [self enableCache:arguments result:result];
    } else if([SetCacheSize isEqualToString:call.method]){
        [self setCacheSize:arguments result:result];
    } else if([EnableMultiThread isEqualToString:call.method]){
        [self enableMultiThread:arguments result:result];
    } else if([EnableReuse isEqualToString:call.method]){
        [self enableReuse:arguments result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

-(void)pagRenderWithPagData:(NSData *)pagData progress:(double)progress repeatCount:(int)repeatCount autoPlay:(BOOL)autoPlay result:(FlutterResult)result reuse:(bool)reuse reuseKey:(NSString *)reuseKey viewId:(int)viewId{
    __block int64_t textureId = -1;
    __weak typeof(self) weakSelf = self;
    __block TGFlutterPagRender *render;
    if (!_enableRenderCache || _freeEntryPool.count <= 0) {
        render = [[TGFlutterPagRender alloc] init];
        textureId = [_textures registerTexture:render];
        [render setTextureId:[NSNumber numberWithLongLong:textureId]];
        [weakSelf.renderMap setObject:render forKey:@(textureId)];
        NSLog(@"debug log init new %lld, pool size:%lu", textureId, (unsigned long)_freeEntryPool.count);
    } else {
        NSNumber* renderCacheTextureId = [weakSelf getRenderCacheTextureId];
        textureId = [renderCacheTextureId longLongValue];
        [weakSelf.freeEntryPool removeObjectAtIndex:0];
        render = [weakSelf.renderMap objectForKey:renderCacheTextureId];
        if (!render){
            FlutterError * flutterError = [FlutterError errorWithCode:@"-1101"
                                                              message:[NSString stringWithFormat:@"id异常，未命中缓存: %@", renderCacheTextureId] //@"id异常，未命中缓存！"
                                                              details:nil];
            result(flutterError);
            [weakSelf onInitPagError:reuse reuseKey:reuseKey flutterError:flutterError];
            return;
        }
        NSLog(@"debug log init cache %lld, pool size:%lu", textureId, (unsigned long)_freeEntryPool.count);
    }
    // render异步并行setup异常时序处理
    // setup时同时dealloc或者release 资源synchronized处理
    // setup前已经dealloc render判空处理
    // setup前已经release 无须处理
    [[TGFlutterWorkerExecutor sharedInstance] post:^(){
        if (!render){
            dispatch_async(dispatch_get_main_queue(), ^(){
                FlutterError * flutterError = [FlutterError errorWithCode:@"-1102"
                                                                  message:@"render异常"
                                                                  details:nil];
                result(flutterError);
                [weakSelf onInitPagError:reuse reuseKey:reuseKey flutterError:flutterError];
            });
            return;
        }
        [render setRepeatCount:repeatCount];
        [render setUpWithPagData:pagData progress:progress frameUpdateCallback:^{
            dispatch_async(dispatch_get_main_queue(), ^(){
                [weakSelf.textures textureFrameAvailable:textureId];
            });
        } eventCallback:^(NSString *event) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                [weakSelf.channel invokeMethod:PlayCallback arguments:@{ArgumentTextureId:@(textureId), ArgumentEvent:event}];
            });
        }];
        dispatch_async(dispatch_get_main_queue(), ^(){
            if (autoPlay) {
                [render startRender];
            }
            result(@{@"textureId": @(textureId), @"width": @([render size].width), @"height": @([render size].height)});
            // 复用的render初始化完成 同步复用相同reuseKey result回调
            if (_enableReuse && reuse && reuseKey && [reuseKey length] > 0){
                ReuseItem *reuseItem = [_reuseMap objectForKey:reuseKey];
                if (reuseItem) {
                    [reuseItem setUpWithTextureId:@(textureId) width:[render size].width height:[render size].height];
                    for (FlutterResult result in reuseItem.mutableResultsArray) {
                        if (result) {
                            result(@{@"textureId": @(textureId), @"width": @([render size].width), @"height": @([render size].height)});
                        }
                    }
                    [reuseItem.mutableResultsArray removeAllObjects];
                } else {
                    ReuseItem *tempItem = [[ReuseItem alloc] init];
                    [tempItem setUpWithTextureId:@(textureId) width:[render size].width height:[render size].height];
                    [tempItem.usingViewSet addObject:@(viewId)];
                    [_reuseMap setObject:tempItem forKey:reuseKey];
                }
            }
        });
    }];
}

-(void) onInitPagError:(BOOL)reuse reuseKey:(NSString *)reuseKey flutterError:(FlutterError *)flutterError{
    if (_enableReuse && reuse && reuseKey && [reuseKey length] > 0){
        ReuseItem *reuseItem = [_reuseMap objectForKey:reuseKey];
        if (reuseItem ) {
            for (FlutterResult result in reuseItem.mutableResultsArray) {
                if (result) {
                    result(flutterError);
                }
            }
            [reuseItem.mutableResultsArray removeAllObjects];
        }
        [_reuseMap removeObjectForKey:reuseKey];
    }
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
