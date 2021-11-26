#import "FlutterPagPlugin.h"
#import "TGFlutterPagRender.h"

@interface FlutterPagPlugin()



@end

@implementation FlutterPagPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"flutter_pag_plugin"
            binaryMessenger:[registrar messenger]];
  FlutterPagPlugin* instance = [[FlutterPagPlugin alloc] init];
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
      int repeatCount = [arguments intValueForKey:@"repeatCount" default:-1];

      __block int64_t textureId = -1;

      TRouterEngine *engine = [[TRouterApplication shared] defaultEngine];
      TGFlutterPagRender *render = [[TGFlutterPagRender alloc] initWithPagName:pagName frameUpdateCallback:^{
          [[[TRouterApplication shared] defaultEngine].engine textureFrameAvailable:textureId];
      }];
      [render setRepeatCount:repeatCount];
      textureId = [engine.engine registerTexture:render];
      if(_renderMap == nil){
        _renderMap = [[NSMutableDictionary alloc] init];
      }
      [_renderMap setObject:render forKey:@(textureId)];
      result(@{@"textureId":@(textureId), @"width":@([render size].width), @"height":@([render size].height)});
  } else if([@"start" isEqualToString:call.method]){
    NSNumber* textureId = arguments[@"textureId"];
    if(textureId == nil){
        result();
        return;
    }
    TGFlutterPagRender *render = [_renderMap objectForKey:@(textureId)];
    [render startRender];
    result();
  } else if([@"stop" isEqualToString:call.method]){
    NSNumber* textureId = arguments[@"textureId"];
    if(textureId == nil){
       result();
       return;
    }
    TGFlutterPagRender *render = [_renderMap objectForKey:@(textureId)];
    [render stopRender];
    [_renderMap removeObjectForKey:@(textureId)];
    result();
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
