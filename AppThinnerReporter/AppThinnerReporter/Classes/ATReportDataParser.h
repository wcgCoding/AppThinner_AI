//
//  ATReportDataParser.h
//  AppThinnerReporter
//
//  解析上报平台导出的 CSV 数据，转换为 AppThinnerAnalyzer 可用的外部数据格式。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 解析后的外部数据（供 AppThinnerAnalyzer 导入）
@interface ATExternalData : NSObject

/// 无用类列表（类名数组）
@property (nonatomic, copy) NSArray<NSString *> *unusedClasses;

/// 无用资源列表（资源路径数组）
@property (nonatomic, copy) NSArray<NSString *> *unusedResources;

@end

/// CSV 解析器：将上报平台导出的 CSV 解析为 AppThinnerAnalyzer 外部数据格式
@interface ATReportDataParser : NSObject

/// 从 CSV 文件解析外部数据
/// @param csvFilePath CSV 文件路径
/// @param error 错误信息（如有）
/// @return 解析后的外部数据，失败返回 nil
+ (nullable ATExternalData *)parseCSVFile:(NSString *)csvFilePath error:(NSError * _Nullable * _Nullable)error;

/// 从 CSV 字符串解析外部数据
/// @param csvString CSV 内容字符串
/// @param error 错误信息（如有）
/// @return 解析后的外部数据，失败返回 nil
+ (nullable ATExternalData *)parseCSVString:(NSString *)csvString error:(NSError * _Nullable * _Nullable)error;

/// 导出为 AppThinnerAnalyzer 可用的格式（JSON/CSV/TXT）
/// @param externalData 外部数据
/// @param format 格式（@"json", @"csv", @"txt"）
/// @param outputPath 输出文件路径
/// @param error 错误信息（如有）
/// @return 是否成功
+ (BOOL)exportExternalData:(ATExternalData *)externalData
                    format:(NSString *)format
                outputPath:(NSString *)outputPath
                     error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
