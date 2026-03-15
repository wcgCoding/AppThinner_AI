//
//  ATReportPayloadBuilder.h
//  AppThinnerReporter
//
//  按与 AppThinner 看板约定的规范，构建类使用 + 资源使用的上报 payload（JSON）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单次上报 payload 的 JSON 结构（与 doc 规范一致）
/// - 类使用：all_class_list / 全量类名顺序；realized_bitmap_base64_gzip（0/1 位图）或 realized_class_names
/// - 资源使用（可选）：used_resource_string（字符串格式，每行 "path|size|count"）
/// - 元数据：app_version, device_model, report_time 等
@interface ATReportPayloadBuilder : NSObject

/// 从已排序全量类名 + 已实现类信息，构建上报用 JSON 字典（可再转 JSON 字符串上传）
/// @param allClassNames 全量类名，按与看板一致的顺序（如字典序）
/// @param realizedBitmap 与 allClassNames 等长的 0/1 字符串，1 表示已实现；与 reportClassNames 二选一
/// @param reportClassNames 若上报类名列表而非位图，传已实现类名数组；否则传 nil
/// @param usedResourceString 资源使用情况字符串（格式：每行 "path|size|count"，用换行符分隔），可为 nil
/// @param extraMetadata 额外元数据（如 app_version, device_model），会合并进 payload
+ (NSDictionary *)buildPayloadWithAllClassNames:(NSArray<NSString *> *)allClassNames
                                 realizedBitmap:(nullable NSString *)realizedBitmap
                              realizedClassNames:(nullable NSArray<NSString *> *)reportClassNames
                              usedResourceString:(nullable NSString *)usedResourceString
                                 extraMetadata:(nullable NSDictionary *)extraMetadata;

/// 将 payload 字典转为 JSON 字符串（UTF-8）
+ (nullable NSString *)jsonStringFromPayload:(NSDictionary *)payload;

@end

NS_ASSUME_NONNULL_END
