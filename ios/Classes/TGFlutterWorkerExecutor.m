//
//  TGFlutterWorkerExecutor.m
//  TGFlutterWorkerExecutor
//
//  Created by liampan on 2025/1/6.
//  Copyright © 2025 Tencent. All rights reserved.
//
#import "TGFlutterWorkerExecutor.h"

@interface TGFlutterWorkerExecutor ()

@property (nonatomic, strong, readonly) dispatch_queue_t concurrentQueue;
@property (nonatomic, strong, readonly) dispatch_queue_t serialQueue;
@end

@implementation TGFlutterWorkerExecutor

static TGFlutterWorkerExecutor *_instance = nil;

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enableMultiThread = YES; // 默认启用并行队列
        _concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        _serialQueue = dispatch_queue_create("com.example.serialQueue", DISPATCH_QUEUE_SERIAL); // todo 线程名确认 或者要不要使用dispatch_get_main_queue()
    }
    return self;
}

- (void)post:(dispatch_block_t)task {
    if (_enableMultiThread) {
        //task增加随机延迟测试
        dispatch_async(_concurrentQueue, ^{
                    uint64_t randomDelay = arc4random_uniform(501);
                    uint64_t delayInNanoseconds = NSEC_PER_MSEC * randomDelay;
                    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInNanoseconds);
                    dispatch_after(popTime, dispatch_get_current_queue(), ^{
                        task();
                    });
                });
//        dispatch_async(_concurrentQueue, task);
    } else {
        dispatch_async(_serialQueue, task);
    }
}
@end
