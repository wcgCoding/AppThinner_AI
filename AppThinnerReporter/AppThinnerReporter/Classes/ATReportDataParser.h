//
//  ATReportDataParser.h
//  AppThinnerReporter
//
//  解析上报平台导出的 CSV 数据，转换为 AppThinnerAnalyzer 可用的外部数据格式。
//  主要用于外部业务方解析无用类数据：传入类映射 plist + 上报 CSV。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 解析后的外部数据（供 AppThinnerAnalyzer 导入）
@interface ATExternalData : NSObject

/// 无用类列表（类名数组）
@property (nonatomic, copy) NSArray<NSString *> *unusedClasses;

/// 使用到的类列表（类名数组）
@property (nonatomic, copy) NSArray<NSString *> *usedClasses;

/// 去除重复后的（类名数组）
@property (nonatomic, copy) NSArray<NSString *> *externalClasses;

/// 使用到的类调用次数统计（key 为类名，value 为 NSNumber，表示在所有上报位图中 bit == 1 的次数累加）
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *usedClassCallCounts;

@end

/// CSV 解析器：将上报平台导出的 CSV 解析为 AppThinnerAnalyzer 外部数据格式
@interface ATReportDataParser : NSObject

/// 从「原始类映射 plist + 上报 CSV」联合解析外部数据
/// - plist 由运行时上报模块写入，包含 all_class_list 与 metadata 等；
/// - CSV 来自线上平台导出的上报数据表格。
/// @param plistFilePath 类映射 plist 文件路径（可为 nil，为 nil 时等价于直接 parseCSVFile:）
/// @param csvFilePath CSV 文件路径
/// @param error 错误信息（如有）
/// @return 解析后的外部数据，失败返回 nil
+ (nullable ATExternalData *)parseCSVFileWithClassMappingPlist:(nullable NSString *)plistFilePath
                                                   csvFilePath:(NSString *)csvFilePath
                                                         error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
