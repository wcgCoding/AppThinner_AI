//
//  ATReportPayloadBuilder.m
//  AppThinnerReporter
//

#import "ATReportPayloadBuilder.h"
#import "ATCompressionHelper.h"
#import "ATReporterKeys.h"

@implementation ATReportPayloadBuilder

+ (NSDictionary *)buildPayloadWithAllClassNames:(NSArray<NSString *> *)allClassNames
                                 realizedBitmap:(NSString *)realizedBitmap
                            realizedClassNames:(NSArray<NSString *> *)reportClassNames
                              usedResourceString:(NSString *)usedResourceString
                                 extraMetadata:(NSDictionary *)extraMetadata {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[kATReporterPayloadKeyReportTime] = @((long long)([[NSDate date] timeIntervalSince1970] * 1000));
    payload[kATReporterPayloadKeyReportType] = @"code";
    if (allClassNames.count > 0) {
        payload[kATReporterPayloadKeyAllClassCount] = @(allClassNames.count);
        payload[kATReporterPayloadKeyAllClassList] = allClassNames;
    }

    if (realizedBitmap.length) {
        NSString *base64 = [ATCompressionHelper base64GzipFromBitstrings:@[realizedBitmap]];
        if (base64) payload[kATReporterPayloadKeyRealizedBitmapBase64Gzip] = base64;
        payload[kATReporterPayloadKeyReportMode] = @"bitmap";
    } else if (reportClassNames.count) {
        payload[kATReporterPayloadKeyRealizedClassNames] = reportClassNames;
        payload[kATReporterPayloadKeyReportMode] = @"class_names";
    }

    if (usedResourceString.length) {
        payload[kATReporterPayloadKeyUsedResourceString] = usedResourceString;
    }

    if (extraMetadata.count) {
        NSMutableDictionary *meta = [payload[kATReporterPayloadKeyMetadata] mutableCopy] ?: [NSMutableDictionary dictionary];
        [meta addEntriesFromDictionary:extraMetadata];
        payload[kATReporterPayloadKeyMetadata] = meta;
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
