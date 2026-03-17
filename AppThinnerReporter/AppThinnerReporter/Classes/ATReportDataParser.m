//
//  ATReportDataParser.m
//  AppThinnerReporter
//
//  解析上报平台导出的 CSV，提取无用类列表，导出为 AppThinnerAnalyzer 可导入格式。
//  精简版：只保留外部业务方需要的无用类解析功能。
//

#import "ATReportDataParser.h"
#import "ATCompressionHelper.h"

@implementation ATExternalData

- (instancetype)init {
    self = [super init];
    if (self) {
        _unusedClasses = @[];
        _usedClasses = @[];
        _usedClassCallCounts = @{};
    }
    return self;
}

@end

@implementation ATReportDataParser

+ (ATExternalData *)parseCSVFileWithClassMappingPlist:(NSString *)plistFilePath
                                           csvFilePath:(NSString *)csvFilePath
                                                 error:(NSError **)error {
    NSArray<NSString *> *externalClassList = nil;
    if (plistFilePath.length) {
        NSDictionary *mapping = [NSDictionary dictionaryWithContentsOfFile:plistFilePath];
        if ([mapping isKindOfClass:[NSDictionary class]]) {
            NSArray *classes = mapping[@"all_class_list"];
            if ([classes isKindOfClass:[NSArray class]]) {
                externalClassList = classes;
            }
        }
    }

    if (!csvFilePath.length) {
        if (error) *error = [NSError errorWithDomain:@"ATReportDataParser" code:1 userInfo:@{NSLocalizedDescriptionKey: @"CSV file path is empty"}];
        return nil;
    }

    // 读取 CSV 文件内容
    NSString *csvContent = [NSString stringWithContentsOfFile:csvFilePath encoding:NSUTF8StringEncoding error:error];
    if (!csvContent) {
        return nil;
    }

    return [self parseCSVString:csvContent withExternalClassList:externalClassList error:error];
}

#pragma mark - Private Methods

+ (ATExternalData *)parseCSVString:(NSString *)csvString
              withExternalClassList:(nullable NSArray<NSString *> *)externalClassList
                              error:(NSError **)error {
    if (!csvString.length) {
        if (error) *error = [NSError errorWithDomain:@"ATReportDataParser" code:2 userInfo:@{NSLocalizedDescriptionKey: @"CSV content is empty"}];
        return nil;
    }

    NSArray<NSString *> *lines = [csvString componentsSeparatedByString:@"\n"];
    if (lines.count < 2) {
        if (error) *error = [NSError errorWithDomain:@"ATReportDataParser" code:3 userInfo:@{NSLocalizedDescriptionKey: @"CSV has no lines"}];
        return nil;
    }

    // 解析表头
    NSString *headerLine = lines[0];
    NSArray<NSString *> *headers = [self parseCSVLine:headerLine];
    NSDictionary<NSString *, NSNumber *> *headerIndexMap = [self createHeaderIndexMap:headers];

    // 解析数据行
    // unusedClassSet：显式标记为无用的类（CSV 列） + 基于位图、在所有行中从未被置为 1 的类
    // usedClassSet：在任意一条位图上报中出现过 bit == '1' 的类
    // usedClassCountMap：记录每个类在所有位图中出现 bit == 1 的次数（可视作「使用次数」近似值）
    NSMutableSet<NSString *> *unusedClassSet = [NSMutableSet set];
    NSMutableSet<NSString *> *usedClassSet = [NSMutableSet set];
    NSMutableSet<NSString *> *externalClassSet = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSNumber *> *usedClassCountMap = [NSMutableDictionary dictionary];

    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!line.length) continue;

        NSArray<NSString *> *fields = [self parseCSVLine:line];
        if (fields.count != headers.count) continue;

        // 解析无用类（直接列）
        NSNumber *classIndex = headerIndexMap[@"unused_class_name"];
        if (classIndex) {
            NSString *className = [fields[classIndex.integerValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (className.length) {
                [unusedClassSet addObject:className];
            }
        }

        // 处理上报格式的类使用数据（如果有类映射）
        if (externalClassList.count > 0) {
            NSNumber *bitmapIndex = headerIndexMap[@"realized_bitmap_base64_gzip"];
            if (bitmapIndex) {
                NSString *bitmapBase64 = fields[bitmapIndex.integerValue];
                if (bitmapBase64.length) {
                    NSArray<NSString *> *bitstrings = [ATCompressionHelper bitstringsFromBase64Gzip:bitmapBase64];
                    if (bitstrings.count > 0) {
                        NSString *bitmap = bitstrings[0];
                        NSUInteger limit = MIN(bitmap.length, externalClassList.count);
                        for (NSUInteger j = 0; j < limit; j++) {
                            unichar bit = [bitmap characterAtIndex:j];
                            NSString *clsName = externalClassList[j];
                            if (!clsName.length) continue;
                            if (bit == '1') {
                                // 任意一条上报中 bit == 1 即视为「曾经被使用过」
                                [usedClassSet addObject:clsName];
                                NSNumber *old = usedClassCountMap[clsName] ?: @0;
                                usedClassCountMap[clsName] = @(old.integerValue + 1);
                            }
                        }
                    }
                }
            }
        }
    }

    // 若提供了完整类映射表：基于「全量类 - usedSet」计算位图层面的 unused，并与显式 unusedClassSet 合并
    if (externalClassList.count > 0) {
        for (NSString *clsName in externalClassList) {
            if (!clsName.length) continue;
            if (![usedClassSet containsObject:clsName]) {
                [unusedClassSet addObject:clsName];
            }
            [externalClassSet addObject:clsName];
        }
    }

    // 去重并排序
    NSArray<NSString *> *sortedUnused = [[unusedClassSet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *sortedUsed = [[usedClassSet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *sortedExternal = [[externalClassSet allObjects] sortedArrayUsingSelector:@selector(compare:)];

    ATExternalData *data = [[ATExternalData alloc] init];
    data.unusedClasses = sortedUnused;
    data.usedClasses = sortedUsed;
    data.usedClassCallCounts = [usedClassCountMap copy];
    data.externalClasses = sortedExternal;
    return data;
}

#pragma mark - Helper Methods

+ (NSArray<NSString *> *)parseCSVLine:(NSString *)line {
    NSMutableArray<NSString *> *fields = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:line];
    NSString *field;
    BOOL inQuotes = NO;
    NSMutableString *currentField = [NSMutableString string];

    while (!scanner.isAtEnd) {
        NSString *character = [line substringWithRange:NSMakeRange(scanner.scanLocation, 1)];

        if ([character isEqualToString:@"\""]) {
            if (inQuotes && scanner.scanLocation + 1 < line.length && [[line substringWithRange:NSMakeRange(scanner.scanLocation + 1, 1)] isEqualToString:@"\""]) {
                // 转义的引号
                [currentField appendString:@"\""];
                scanner.scanLocation += 2;
            } else {
                // 切换引号状态
                inQuotes = !inQuotes;
                scanner.scanLocation++;
            }
        } else if ([character isEqualToString:@","] && !inQuotes) {
            // 字段分隔符
            [fields addObject:[currentField copy]];
            [currentField setString:@""];
            scanner.scanLocation++;
        } else {
            [currentField appendString:character];
            scanner.scanLocation++;
        }
    }

    [fields addObject:[currentField copy]];
    return [fields copy];
}

+ (NSDictionary<NSString *, NSNumber *> *)createHeaderIndexMap:(NSArray<NSString *> *)headers {
    NSMutableDictionary<NSString *, NSNumber *> *map = [NSMutableDictionary dictionary];
    [headers enumerateObjectsUsingBlock:^(NSString *header, NSUInteger idx, BOOL *stop) {
        map[header] = @(idx);
    }];
    return [map copy];
}

@end
