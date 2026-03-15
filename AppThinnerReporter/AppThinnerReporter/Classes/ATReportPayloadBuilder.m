//
//  ATReportPayloadBuilder.m
//  AppThinnerReporter
//

#import "ATReportPayloadBuilder.h"
#import "ATCompressionHelper.h"

@implementation ATReportPayloadBuilder

+ (NSDictionary *)buildPayloadWithAllClassNames:(NSArray<NSString *> *)allClassNames
                                 realizedBitmap:(NSString *)realizedBitmap
                            realizedClassNames:(NSArray<NSString *> *)reportClassNames
                              usedResourceString:(NSString *)usedResourceString
                                 extraMetadata:(NSDictionary *)extraMetadata {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"report_time"] = @((long long)([[NSDate date] timeIntervalSince1970] * 1000));
    if (allClassNames.count > 0) {
        payload[@"all_class_count"] = @(allClassNames.count);
        payload[@"all_class_list"] = allClassNames;
    }

    if (realizedBitmap.length) {
        NSString *base64 = [ATCompressionHelper base64GzipFromBitstrings:@[realizedBitmap]];
        if (base64) payload[@"realized_bitmap_base64_gzip"] = base64;
        payload[@"report_mode"] = @"bitmap";
    } else if (reportClassNames.count) {
        payload[@"realized_class_names"] = reportClassNames;
        payload[@"report_mode"] = @"class_names";
    }

    if (usedResourceString.length) {
        payload[@"used_resource_string"] = usedResourceString;
    }

    if (extraMetadata.count) {
        NSMutableDictionary *meta = [payload[@"metadata"] mutableCopy] ?: [NSMutableDictionary dictionary];
        [meta addEntriesFromDictionary:extraMetadata];
        payload[@"metadata"] = meta;
    }
    return [payload copy];
}

+ (NSString *)jsonStringFromPayload:(NSDictionary *)payload {
    if (!payload) return nil;
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&err];
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
