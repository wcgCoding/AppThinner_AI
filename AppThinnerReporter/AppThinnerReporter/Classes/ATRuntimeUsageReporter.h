//
//  ATRuntimeUsageReporter.h
//  AppThinnerReporter
//
//  现网运行时类与资源使用情况动态上报。输出格式与 AppThinner 看板外部导入约定一致。
//

#import <Foundation/Foundation.h>
#import "ATReporterKeys.h"

NS_ASSUME_NONNULL_BEGIN

/// 配置项 key（传入 startWithConfiguration: 的 NSDictionary）
FOUNDATION_EXPORT NSString * const kATReporterConfigEnable;
FOUNDATION_EXPORT NSString * const kATReporterConfigReportClassNames;  // NSNumber bool：YES 上报类名列表，NO 上报 0/1 位图
FOUNDATION_EXPORT NSString * const kATReporterConfigDelaySeconds;     // NSNumber：进入 App 后多少秒才允许上报
FOUNDATION_EXPORT NSString * const kATReporterConfigReportIntervalSeconds; // NSNumber：两次上报最小间隔（秒）
FOUNDATION_EXPORT NSString * const kATReporterConfigMaxPayloadSize;   // NSNumber：单次上报 payload 最大字节（含 JSON），超则分段或仅位图
FOUNDATION_EXPORT NSString * const kATReporterConfigCollectResources; // NSNumber bool：是否采集资源使用（如 imageNamed）
FOUNDATION_EXPORT NSString * const kATReporterConfigPersistClassMapping; // NSNumber bool：是否将类映射表写入本地 plist 供后续分析使用

/// 上报 payload 中常用字段 key（类使用 & 资源使用通用）
/// 说明：常量定义在 `ATReporterKeys.m` 中，这里仅通过头文件暴露，便于接入方复用字段名。

/// 上报回调：payload 为规范 JSON 字典，可由宿主上传到自有后端或写文件；若有多段则多次调用
typedef void(^ATReporterUploadBlock)(NSDictionary *payload, NSInteger segmentIndex, NSInteger segmentTotal);

@interface ATRuntimeUsageReporter : NSObject

/// 使用配置启动上报能力（进入后台时在满足延迟与间隔条件下触发「类使用情况」采集并调用 uploadBlock）
/// config 可为 nil，则使用默认：延迟 20 分钟、间隔 24 小时、位图模式、不采集资源
+ (void)startWithConfiguration:(nullable NSDictionary *)config
                  uploadBlock:(nullable ATReporterUploadBlock)uploadBlock;

/// 停止上报（移除后台监听、停止资源采集）
+ (void)stop;

/// 本地上报类的元数据文件夹
+ (NSString *)appThinnerDirectoryPath;

@end

NS_ASSUME_NONNULL_END
