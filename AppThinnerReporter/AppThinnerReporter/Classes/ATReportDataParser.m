//
//  ATReportDataParser.m
//  AppThinnerReporter
//
//  解析上报平台导出的 CSV，提取无用类/资源列表，导出为 AppThinnerAnalyzer 可导入格式。
//
//  支持的 CSV 格式：
//  1. 直接格式：包含 className、resource_path 等列，每行一个无用类/资源
//  2. 上报格式：包含 all_class_list、realized_bitmap_base64_gzip、used_resource_string 等列
//     - 从 all_class_list + realized_bitmap/realized_class_names 计算无用类（全量类 - 已实现类）
//     - 从 used_resource_string 解析资源路径（格式：每行 "path|size|count"）
//

#import "ATReportDataParser.h"
#import "ATCompressionHelper.h"
#import "ATResourceUsageInfo.h"

@implementation ATExternalData

- (instancetype)init {
    self = [super init];
    if (self) {
        _unusedClasses = @[];
        _unusedResources = @[];
    }
    return self;
}

@end

@implementation ATReportDataParser

+ (ATExternalData *)parseCSVFile:(NSString *)csvFilePath error:(NSError **)error {
    if (!csvFilePath.length) {
        if (error) *error = [NSError errorWithDomain:@"ATReportDataParser" code:1 userInfo:@{NSLocalizedDescriptionKey: @"CSV file path is empty"}];
        return nil;
    }
    
    NSError *readError = nil;
    NSString *content = [NSString stringWithContentsOfFile:csvFilePath encoding:NSUTF8StringEncoding error:&readError];
    if (readError) {
        if (error) *error = readError;
        return nil;
    }
    
    return [self parseCSVString:content error:error];
}

+ (ATExternalData *)parseCSVString:(NSString *)csvString error:(NSError **)error {
    if (!csvString.length) {
        if (error) *error = [NSError errorWithDomain:@"ATReportDataParser" code:2 userInfo:@{NSLocalizedDescriptionKey: @"CSV content is empty"}];
        return nil;
    }
    
    NSArray *lines = [csvString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if (lines.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATReportDataParser" code:3 userInfo:@{NSLocalizedDescriptionKey: @"CSV has no lines"}];
        return nil;
    }
    
    NSMutableArray<NSString *> *unusedClasses = [NSMutableArray array];
    NSMutableArray<NSString *> *unusedResources = [NSMutableArray array];
    
    // 列索引映射
    NSInteger classNameColumn = -1;
    NSInteger resourcePathColumn = -1;
    NSInteger reportModeColumn = -1;
    NSInteger realizedBitmapColumn = -1;
    NSInteger realizedClassNamesColumn = -1;
    NSInteger resourceStringColumn = -1;
    NSInteger allClassListColumn = -1;
    
    // 用于位图解析的全局数据（如果存在）
    NSArray<NSString *> *allClassList = nil;
    NSString *realizedBitmap = nil;
    NSString *reportMode = nil;
    NSArray<NSString *> *realizedClassNames = nil;
    
    // 第一遍：解析表头并收集上报数据格式的列
    BOOL hasHeader = NO;
    for (NSInteger i = 0; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length == 0) continue;
        
        NSArray *columns = [self parseCSVLine:line];
        if (columns.count == 0) continue;
        
        // 检测表头
        if (i == 0) {
            for (NSInteger j = 0; j < columns.count; j++) {
                NSString *header = [columns[j] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *headerLower = [header lowercaseString];
                
                // 类相关列
                if ([headerLower containsString:@"classname"] || [headerLower containsString:@"class_name"] || 
                    ([headerLower containsString:@"class"] && ![headerLower containsString:@"list"] && ![headerLower containsString:@"all"])) {
                    classNameColumn = j;
                } else if ([headerLower containsString:@"all_class_list"] || [headerLower isEqualToString:@"all_class_list"]) {
                    allClassListColumn = j;
                } else if ([headerLower containsString:@"realized_class_names"] || [headerLower isEqualToString:@"realized_class_names"]) {
                    realizedClassNamesColumn = j;
                }
                
                // 资源相关列
                if ([headerLower containsString:@"resource_path"] || [headerLower containsString:@"resourcepath"] ||
                    ([headerLower containsString:@"resource"] && [headerLower containsString:@"path"])) {
                    resourcePathColumn = j;
                } else if ([headerLower containsString:@"used_resource_string"] || [headerLower containsString:@"resource_string"] ||
                           [headerLower containsString:@"used_resource"]) {
                    resourceStringColumn = j;
                } else if ([headerLower containsString:@"path"] && ![headerLower containsString:@"class"] && ![headerLower containsString:@"resource"]) {
                    // 通用的 path 列，如果没有专门的 resource_path 列则使用
                    if (resourcePathColumn < 0) {
                        resourcePathColumn = j;
                    }
                }
                
                // 上报格式相关列
                if ([headerLower containsString:@"report_mode"] || [headerLower isEqualToString:@"report_mode"]) {
                    reportModeColumn = j;
                } else if ([headerLower containsString:@"realized_bitmap"] || [headerLower containsString:@"bitmap"]) {
                    realizedBitmapColumn = j;
                }
            }
            hasHeader = YES;
            continue;
        }
        
        // 解析第一行数据，提取上报格式的全局数据（这些是每行共享的）
        if (i == 1 && hasHeader) {
            // 提取 all_class_list
            if (allClassListColumn >= 0 && allClassListColumn < columns.count) {
                NSString *allClassListStr = [columns[allClassListColumn] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (allClassListStr.length) {
                    allClassList = [self parseClassListString:allClassListStr];
                }
            }
            
            // 提取 report_mode
            if (reportModeColumn >= 0 && reportModeColumn < columns.count) {
                reportMode = [columns[reportModeColumn] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
            
            // 提取 realized_bitmap_base64_gzip
            if (realizedBitmapColumn >= 0 && realizedBitmapColumn < columns.count) {
                NSString *bitmapBase64 = [columns[realizedBitmapColumn] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (bitmapBase64.length && reportMode && [reportMode.lowercaseString isEqualToString:@"bitmap"]) {
                    NSArray<NSString *> *bitstrings = [ATCompressionHelper bitstringsFromBase64Gzip:bitmapBase64];
                    if (bitstrings.count > 0) {
                        realizedBitmap = bitstrings[0];
                    }
                }
            }
            
            // 提取 realized_class_names
            if (realizedClassNamesColumn >= 0 && realizedClassNamesColumn < columns.count) {
                NSString *realizedClassNamesStr = [columns[realizedClassNamesColumn] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (realizedClassNamesStr.length) {
                    realizedClassNames = [self parseClassListString:realizedClassNamesStr];
                }
            }
            
            // 如果存在上报格式数据，计算无用类（只计算一次）
            if (allClassList.count > 0 && unusedClasses.count == 0) {
                NSMutableSet<NSString *> *realizedSet = [NSMutableSet set];
                
                if (realizedBitmap.length > 0 && realizedBitmap.length == allClassList.count) {
                    // 从位图解析已实现类
                    for (NSInteger idx = 0; idx < allClassList.count && idx < realizedBitmap.length; idx++) {
                        unichar bit = [realizedBitmap characterAtIndex:idx];
                        if (bit == '1') {
                            [realizedSet addObject:allClassList[idx]];
                        }
                    }
                } else if (realizedClassNames.count > 0) {
                    // 从类名列表解析已实现类
                    [realizedSet addObjectsFromArray:realizedClassNames];
                }
                
                // 计算无用类：全量类 - 已实现类
                for (NSString *className in allClassList) {
                    if (![realizedSet containsObject:className]) {
                        [unusedClasses addObject:className];
                    }
                }
            }
        }
        
        // 解析数据行：提取直接的无用类和资源（遍历所有数据行）
        // 从类名列提取无用类（如果还没有从位图解析，或者 CSV 中每行都有不同的类）
        if (classNameColumn >= 0 && classNameColumn < columns.count) {
            NSString *className = [columns[classNameColumn] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (className.length && ![className isEqualToString:@"N/A"] && ![className isEqualToString:@"-"] && 
                ![className isEqualToString:@""]) {
                // 如果已经通过位图解析了无用类，则追加；否则直接添加
                [unusedClasses addObject:className];
            }
        }
        
        // 从资源字符串列解析资源（格式：每行 "path|size|count"，用换行符分隔）
        if (resourceStringColumn >= 0 && resourceStringColumn < columns.count) {
            NSString *resourceStr = columns[resourceStringColumn];
            if (resourceStr.length) {
                NSArray *resourceLines = [resourceStr componentsSeparatedByString:@"\n"];
                for (NSString *resLine in resourceLines) {
                    NSString *trimmed = [resLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (trimmed.length == 0) continue;
                    
                    // 尝试解析为 reportString 格式
                    ATResourceUsageInfo *info = [ATResourceUsageInfo fromReportString:trimmed];
                    if (info && info.resourcePath.length) {
                        [unusedResources addObject:info.resourcePath];
                    } else {
                        // 如果不是标准格式，尝试直接按 | 分割
                        NSArray *parts = [trimmed componentsSeparatedByString:@"|"];
                        if (parts.count >= 1) {
                            NSString *path = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                            if (path.length) {
                                [unusedResources addObject:path];
                            }
                        }
                    }
                }
            }
        }
        
        // 从资源路径列直接提取
        if (resourcePathColumn >= 0 && resourcePathColumn < columns.count) {
            NSString *resourcePath = [columns[resourcePathColumn] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (resourcePath.length && ![resourcePath isEqualToString:@"N/A"] && 
                ![resourcePath isEqualToString:@"-"] && ![resourcePath isEqualToString:@""]) {
                [unusedResources addObject:resourcePath];
            }
        }
    }
    
    // 去重并排序（保持字典序，与上报格式一致）
    NSOrderedSet<NSString *> *uniqueClasses = [NSOrderedSet orderedSetWithArray:unusedClasses];
    NSOrderedSet<NSString *> *uniqueResources = [NSOrderedSet orderedSetWithArray:unusedResources];
    
    // 对类名排序（字典序）
    NSArray<NSString *> *sortedClasses = [uniqueClasses.array sortedArrayUsingSelector:@selector(compare:)];
    // 对资源路径排序
    NSArray<NSString *> *sortedResources = [uniqueResources.array sortedArrayUsingSelector:@selector(compare:)];
    
    ATExternalData *data = [[ATExternalData alloc] init];
    data.unusedClasses = [sortedClasses copy];
    data.unusedResources = [sortedResources copy];
    
    return data;
}

+ (NSArray<NSString *> *)parseClassListString:(NSString *)classListStr {
    if (!classListStr.length) return @[];
    
    // 尝试解析为 JSON 数组
    NSData *jsonData = [classListStr dataUsingEncoding:NSUTF8StringEncoding];
    if (jsonData) {
        NSError *jsonError = nil;
        id jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
        if (!jsonError && [jsonObj isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)jsonObj;
            NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:arr.count];
            for (id item in arr) {
                if ([item isKindOfClass:[NSString class]]) {
                    NSString *trimmed = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (trimmed.length) {
                        [result addObject:trimmed];
                    }
                }
            }
            return [result copy];
        }
    }
    
    // 尝试按逗号分割（去除方括号等）
    NSString *cleaned = [classListStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cleaned hasPrefix:@"["] && [cleaned hasSuffix:@"]"]) {
        cleaned = [cleaned substringWithRange:NSMakeRange(1, cleaned.length - 2)];
    }
    
    NSArray *parts = [cleaned componentsSeparatedByString:@","];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // 移除引号
        if ([trimmed hasPrefix:@"\""] && [trimmed hasSuffix:@"\""]) {
            trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
        } else if ([trimmed hasPrefix:@"'"] && [trimmed hasSuffix:@"'"]) {
            trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
        }
        trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length) {
            [result addObject:trimmed];
        }
    }
    
    return [result copy];
}

+ (NSArray<NSString *> *)parseCSVLine:(NSString *)line {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL inQuotes = NO;
    
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == '"') {
            inQuotes = !inQuotes;
        } else if (c == ',' && !inQuotes) {
            [result addObject:[current copy]];
            [current setString:@""];
        } else {
            [current appendFormat:@"%C", c];
        }
    }
    [result addObject:[current copy]];
    
    return [result copy];
}

+ (BOOL)exportExternalData:(ATExternalData *)externalData
                    format:(NSString *)format
                outputPath:(NSString *)outputPath
                     error:(NSError **)error {
    if (!externalData || !format.length || !outputPath.length) {
        if (error) *error = [NSError errorWithDomain:@"ATReportDataParser" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Invalid parameters"}];
        return NO;
    }
    
    NSString *fmt = [format lowercaseString];
    NSData *data = nil;
    
    if ([fmt isEqualToString:@"json"]) {
        NSMutableDictionary *json = [NSMutableDictionary dictionary];
        json[@"unusedClasses"] = externalData.unusedClasses;
        json[@"unusedResources"] = externalData.unusedResources;
        data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:error];
        if (!data) return NO;
    } else if ([fmt isEqualToString:@"csv"]) {
        NSMutableString *csv = [NSMutableString string];
        [csv appendString:@"Type,Path\n"];
        for (NSString *cls in externalData.unusedClasses) {
            [csv appendFormat:@"Class,%@\n", cls];
        }
        for (NSString *res in externalData.unusedResources) {
            [csv appendFormat:@"Resource,%@\n", res];
        }
        data = [csv dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([fmt isEqualToString:@"txt"]) {
        NSMutableString *txt = [NSMutableString string];
        [txt appendString:@"# Unused Classes\n"];
        for (NSString *cls in externalData.unusedClasses) {
            [txt appendFormat:@"%@\n", cls];
        }
        [txt appendString:@"\n# Unused Resources\n"];
        for (NSString *res in externalData.unusedResources) {
            [txt appendFormat:@"%@\n", res];
        }
        data = [txt dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        if (error) *error = [NSError errorWithDomain:@"ATReportDataParser" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported format: %@", format]}];
        return NO;
    }
    
    return [data writeToFile:outputPath atomically:YES];
}

@end
