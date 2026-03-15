//
//  ATRuntimeUsageReporter.m
//  AppThinnerReporter
//

#import "ATRuntimeUsageReporter.h"
#import "ATObjCClassCollector.h"
#import "ATReportPayloadBuilder.h"
#import "ATResourceUsageCollector.h"
#import <CommonCrypto/CommonCrypto.h>

#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#define AT_HAS_UIKIT 1
#else
#define AT_HAS_UIKIT 0
#endif

NSString * const kATReporterConfigEnable = @"enable";
NSString * const kATReporterConfigReportClassNames = @"reportClassNames";
NSString * const kATReporterConfigDelaySeconds = @"delaySeconds";
NSString * const kATReporterConfigReportIntervalSeconds = @"reportIntervalSeconds";
NSString * const kATReporterConfigMaxPayloadSize = @"maxPayloadSize";
NSString * const kATReporterConfigCollectResources = @"collectResources";

static const NSTimeInterval kDefaultDelaySeconds = 20 * 60;
static const NSTimeInterval kDefaultReportIntervalSeconds = 24 * 60 * 60;
static const NSUInteger kDefaultMaxPayloadSize = 100 * 1024;

static NSDictionary * _Nullable g_config;
static ATReporterUploadBlock _Nullable g_uploadBlock;
static NSTimeInterval g_appLaunchTime = 0;
static NSTimeInterval g_lastReportTime = 0;
static BOOL g_isReporting = NO;
static NSString * const kATLastReportTimeKey = @"AppThinnerReporter.lastReportTime";

static NSString *AT_SHA256ForData(NSData *data) {
    if (!data.length) return @"";
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [result appendFormat:@"%02x", hash[i]];
    }
    return result;
}

static NSString *AT_ClassTableHashFromNames(NSArray<NSString *> *names) {
    if (names.count == 0) {
        NSData *empty = [NSData data];
        return AT_SHA256ForData(empty);
    }
    NSString *joined = [names componentsJoinedByString:@"\n"];
    NSData *data = [joined dataUsingEncoding:NSUTF8StringEncoding];
    return AT_SHA256ForData(data);
}

@implementation ATRuntimeUsageReporter

+ (void)startWithConfiguration:(NSDictionary *)config uploadBlock:(ATReporterUploadBlock)uploadBlock {
    g_appLaunchTime = [[NSDate date] timeIntervalSince1970];
    g_config = config ? [config copy] : @{};
    g_uploadBlock = uploadBlock;

    BOOL enable = [g_config[kATReporterConfigEnable] boolValue];
    if (g_config[kATReporterConfigEnable] == nil) enable = YES;
    if (!enable) return;

    if ([g_config[kATReporterConfigCollectResources] boolValue]) {
        ATResourceUsageCollector *collector = [ATResourceUsageCollector shared];
        [collector startCollecting];
        __weak Class weakSelf = self;
        [collector setInternalReportBlock:^(NSString *resourceLine) {
            [weakSelf at_reportResourceLine:resourceLine];
        }];
    }

#if AT_HAS_UIKIT
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(at_applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
#endif
}

+ (void)stop {
    g_config = nil;
    g_uploadBlock = nil;
    [[ATResourceUsageCollector shared] stopCollecting];
#if AT_HAS_UIKIT
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
#endif
}

+ (void)at_applicationDidEnterBackground:(NSNotification *)note {
    (void)note;
    if (!g_config || !g_uploadBlock) return;
    if (g_isReporting) return;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval delay = [g_config[kATReporterConfigDelaySeconds] doubleValue];
    if (delay <= 0) delay = kDefaultDelaySeconds;
    if (now - g_appLaunchTime < delay) return;

    NSTimeInterval interval = [g_config[kATReporterConfigReportIntervalSeconds] doubleValue];
    if (interval <= 0) interval = kDefaultReportIntervalSeconds;
    NSTimeInterval last = [[NSUserDefaults standardUserDefaults] doubleForKey:kATLastReportTimeKey];
    if (last > 0 && now - last < interval) return;

    g_isReporting = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self at_reportOnce];
        g_isReporting = NO;
    });
}

+ (void)at_reportOnce {
#if !__LP64__
    if (g_uploadBlock) {
        NSDictionary *payload = [ATReportPayloadBuilder buildPayloadWithAllClassNames:@[]
                                                                     realizedBitmap:nil
                                                                  realizedClassNames:nil
                                                                      usedResources:nil
                                                                     extraMetadata:@{ @"note": @"64-bit only" }];
        g_uploadBlock(payload, 0, 1);
    }
    return;
#endif

    int total = at_objc_allClassCount();
    if (total <= 0) return;

    Class *buf = (Class *)malloc((size_t)total * sizeof(Class));
    if (!buf) return;
    int n = at_objc_getAllClasses(buf, total);
    if (n <= 0) { free(buf); return; }

    qsort(buf, (size_t)n, sizeof(Class), at_compareClassesByName);

    NSMutableArray *allNames = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
    NSMutableString *bitmap = [NSMutableString stringWithCapacity:(NSUInteger)n];

    for (int i = 0; i < n; i++) {
        const char *cname = class_getName(buf[i]);
        if (!cname) continue;
        NSString *name = [NSString stringWithUTF8String:cname];
        if (!name.length) continue;
        [allNames addObject:name];
        BOOL realized = at_objc_isClassRealized(buf[i]);
        [bitmap appendString:realized ? @"1" : @"0"];
    }
    free(buf);

    // 计算类表哈希与位图长度（供静态端校验与解码）
    NSString *classTableHash = AT_ClassTableHashFromNames(allNames);
    NSUInteger bitmapLength = (NSUInteger)bitmap.length;

    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    if (info[@"CFBundleShortVersionString"]) meta[@"app_version"] = info[@"CFBundleShortVersionString"];
    if (info[@"CFBundleVersion"]) meta[@"build"] = info[@"CFBundleVersion"];
    meta[@"class_table_hash"] = classTableHash;
    meta[@"bitmap_length"] = @(bitmapLength);
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    meta[@"device"] = @"physical";
#else
    meta[@"device"] = @"simulator";
#endif

    NSString *realizedBitmap = [bitmap copy];
    NSDictionary *payload = [ATReportPayloadBuilder buildPayloadWithAllClassNames:@[]
                                                                 realizedBitmap:realizedBitmap
                                                              realizedClassNames:nil
                                                              usedResourceString:nil
                                                                 extraMetadata:meta];

    [[NSUserDefaults standardUserDefaults] setDouble:[[NSDate date] timeIntervalSince1970] forKey:kATLastReportTimeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSUInteger maxSize = [g_config[kATReporterConfigMaxPayloadSize] unsignedIntegerValue];
    if (maxSize <= 0) maxSize = kDefaultMaxPayloadSize;
    NSString *json = [ATReportPayloadBuilder jsonStringFromPayload:payload];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length <= maxSize && g_uploadBlock) {
        g_uploadBlock(payload, 0, 1);
    } else if (g_uploadBlock) {
        g_uploadBlock(payload, 0, 1);
    }
}

/// 单条资源使用内部上报：由 ATResourceUsageCollector 在记录时触发
+ (void)at_reportResourceLine:(NSString *)resourceLine {
    if (!g_uploadBlock || resourceLine.length == 0) return;

    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    if (info[@"CFBundleShortVersionString"]) meta[@"app_version"] = info[@"CFBundleShortVersionString"];
    if (info[@"CFBundleVersion"]) meta[@"build"] = info[@"CFBundleVersion"];
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    meta[@"device"] = @"physical";
#else
    meta[@"device"] = @"simulator";
#endif

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval delta = g_appLaunchTime > 0 ? (now - g_appLaunchTime) : 0;

    // 从 resourceLine 中解析资源大小（path|size|count）
    NSUInteger resourceSize = 0;
    NSArray<NSString *> *parts = [resourceLine componentsSeparatedByString:@"|"];
    if (parts.count >= 2) {
        resourceSize = (NSUInteger)[parts[1] longLongValue];
    }

    NSDictionary *payload = @{
        @"report_time": @((long long)(now * 1000)),
        @"report_type": @"resources_only",
        @"used_resource_string": resourceLine,
        // 距离 App 启动的时长（秒），用于评估资源使用场景的优先级
        @"time_since_launch": @(delta),
        // 资源大小（字节），从 path|size|count 第二段解析
        @"resource_size": @(resourceSize),
        @"metadata": [meta copy]
    };

    g_uploadBlock(payload, 0, 1);
}

@end
