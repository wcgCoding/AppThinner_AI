//
//  ATResourceUsageCollector.h
//  AppThinnerReporter
//
//  运行时资源使用情况采集（可扩展）。记录 imageNamed: / pathForResource 等访问过的资源标识。
//

#import <Foundation/Foundation.h>

@class ATResourceUsageInfo;

NS_ASSUME_NONNULL_BEGIN

typedef void(^ATResourceInternalReportBlock)(NSString *resourceLine);

@interface ATResourceUsageCollector : NSObject

/// 单例，用于统一记录与读取
+ (instancetype)shared;

/// 开始记录（会 hook UIImage imageNamed:、NSBundle pathForResource 等，仅记录不改变行为）
- (void)startCollecting;

/// 停止记录并移除 hook
- (void)stopCollecting;

/// 当前已记录到的资源信息列表（包含路径、大小、调用次数），拷贝后返回
- (NSArray<ATResourceUsageInfo *> *)currentUsedResourceInfos;

/// 获取资源上报字符串（格式：每行一个 "path|size|count"，用换行符分隔）
- (NSString *)resourceReportString;

/// 设置内部上报回调：每次记录或更新某个资源时会触发一次，参数为该资源当前的 `path|size|count` 字符串
- (void)setInternalReportBlock:(nullable ATResourceInternalReportBlock)block;

/// 清空当前周期记录（上报后可由调用方清空，以便下一周期重新累积）
- (void)clear;

@end

NS_ASSUME_NONNULL_END
