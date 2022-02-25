#import "FlutterPagPlugin.h"
#import "TGFlutterPagRender.h"

@interface FlutterPagPlugin()

@property(nonatomic, weak) NSObject<FlutterTextureRegistry>* textures;

@property(nonatomic, weak) NSObject<FlutterPluginRegistrar>* registrar;

@property (nonatomic, strong) NSMutableDictionary *renderMap;

@end

@implementation FlutterPagPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"flutter_pag_plugin"
            binaryMessenger:[registrar messenger]];
  FlutterPagPlugin* instance = [[FlutterPagPlugin alloc] init];
    instance.textures = registrar.textures;
    instance.registrar = registrar;
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  id arguments = call.arguments;
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  } else if([@"initPag" isEqualToString:call.method]){
      if (arguments == nil || arguments[@"pagName"] == nil) {
          result(@-1);
          NSLog(@"showPag arguments is nil");
          return;
      }
      NSString* pagName = arguments[@"pagName"];
      pagName = [self.registrar lookupKeyForAsset:pagName];
      double initProgress = 0.0;
      if (arguments[@"initProgress"]) {
          initProgress = [arguments[@"initProgress"] doubleValue];
      }
      int repeatCount = -1;
      if(arguments[@"repeatCount"]){
          repeatCount = [[arguments objectForKey:@"repeatCount"] intValue];
      }

      __block int64_t textureId = -1;
      
      TGFlutterPagRender *render = [[TGFlutterPagRender alloc] initWithPagName:pagName progress:initProgress frameUpdateCallback:^{
           [self.textures textureFrameAvailable:textureId];
      }];
      [render setRepeatCount:repeatCount];
      textureId = [self.textures registerTexture:render];
      if(_renderMap == nil){
        _renderMap = [[NSMutableDictionary alloc] init];
      }
      [_renderMap setObject:render forKey:@(textureId)];
      result(@{@"textureId":@(textureId), @"width":@([render size].width), @"height":@([render size].height)});
  } else if([@"start" isEqualToString:call.method]){
    NSNumber* textureId = arguments[@"textureId"];
    if(textureId == nil){
        result(@{});
        return;
    }
    TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
    [render startRender];
    result(@{});
  } else if([@"stop" isEqualToString:call.method]){
    NSNumber* textureId = arguments[@"textureId"];
    if(textureId == nil){
       result(@{});
       return;
    }
    TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
    [render stopRender];
      result(@{});
  } else if([@"pause" isEqualToString:call.method]){
      NSNumber* textureId = arguments[@"textureId"];
      if(textureId == nil){
         result(@{});
         return;
      }
    TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
    [render pauseRender];
    result(@{});
  } else if([@"setProgress" isEqual:call.method]){
      NSNumber* textureId = arguments[@"textureId"];
      if(textureId == nil){
          result(@{});
          return;
      }
      double progress = 0.0;
      if (arguments[@"progress"]) {
          progress = [arguments[@"progress"] doubleValue];
      }
      TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
      [render setProgress:progress];
      result(@{});
  } else if([@"release" isEqualToString:call.method]){
      NSNumber* textureId = arguments[@"textureId"];
      if(textureId == nil){
         result(@{});
         return;
      }
      TGFlutterPagRender *render = [_renderMap objectForKey:textureId];
      [render releaseRender];
      [_renderMap removeObjectForKey:textureId];
    result(@{});
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
