//
//  TGFlutterPagDownloadManager.h
//  flutter_pag_plugin
//
//  Created by 黎敬茂 on 2022/3/14.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TGFlutterPagDownloadManager : NSObject

+(void)download:(NSString *)urlStr completionHandler:(void (^)(NSData * data, NSError * error))handler;

@end

NS_ASSUME_NONNULL_END
