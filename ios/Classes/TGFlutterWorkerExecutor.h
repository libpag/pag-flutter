//
//  TGFlutterWorkerExecutor.h
//  TGFlutterWorkerExecutor
//
//  Created by liampan on 2025/1/6.
//  Copyright © 2025 Tencent. All rights reserved.
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  WorkThreadExecutor 是管理render缓存的队列单例类。
 *  提供全局并并发队列和一个手动创建的穿行队列
 */

@interface TGFlutterWorkerExecutor : NSObject
// 并行队列开关
@property (nonatomic, assign) BOOL enableMultiThread;

// 单例方法
+ (instancetype)sharedInstance;

- (void)post:(dispatch_block_t)task;

@end

NS_ASSUME_NONNULL_END
