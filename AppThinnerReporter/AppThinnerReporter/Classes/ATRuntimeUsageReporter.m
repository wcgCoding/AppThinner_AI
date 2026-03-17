//
//  ATRuntimeUsageReporter.m
//  AppThinnerReporter
//

#import "ATRuntimeUsageReporter.h"
#import "ATObjCClassCollector.h"
#import "ATReportPayloadBuilder.h"
#import "ATResourceUsageCollector.h"
#import "ATReporterKeys.h"
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>

#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#define AT_HAS_UIKIT 1
#else
#define AT_HAS_UIKIT 0
#endif

// Configuration 字段 key
NSString * const kATReporterConfigEnable = @"enable";
NSString * const kATReporterConfigReportClassNames = @"reportClassNames";
NSString * const kATReporterConfigDelaySeconds = @"delaySeconds";
NSString * const kATReporterConfigReportIntervalSeconds = @"reportIntervalSeconds";
NSString * const kATReporterConfigMaxPayloadSize = @"maxPayloadSize";
NSString * const kATReporterConfigCollectResources = @"collectResources";
NSString * const kATReporterConfigPersistClassMapping = @"persistClassMapping";

static const NSTimeInterval kDefaultDelaySeconds = 20 * 60;
static const NSTimeInterval kDefaultReportIntervalSeconds = 24 * 60 * 60;
static const NSUInteger kDefaultMaxPayloadSize = 100 * 1024;

static NSDictionary * _Nullable g_config;
static ATReporterUploadBlock _Nullable g_uploadBlock;
static NSTimeInterval g_appLaunchTime = 0;
static NSTimeInterval g_lastReportTime = 0;
static BOOL g_isReporting = NO;
static NSString * const kATLastReportTimeKey = @"AppThinnerReporter.lastReportTime";

// 资源上报缓冲区
static NSMutableDictionary<NSString *, NSDictionary *> * _Nullable g_resourceBuffer;
static dispatch_source_t _Nullable g_resourceReportTimer;
static const NSTimeInterval kResourceReportInterval = 5.0; // 5秒间隔

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
        // 初始化资源缓冲区和定时器
        g_resourceBuffer = [NSMutableDictionary dictionary];
        [self at_startResourceReportTimer];
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
    [self at_stopResourceReportTimer];
    g_resourceBuffer = nil;
#if AT_HAS_UIKIT
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
#endif
}

#pragma mark - private

+ (void)at_applicationDidEnterBackground:(NSNotification *)note {
    (void)note;
    if (!g_config || !g_uploadBlock) return;
    if (g_isReporting) return;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval delay = [g_config[kATReporterConfigDelaySeconds] doubleValue];
    if (delay <= 0) delay = kDefaultDelaySeconds;
    if (now - g_appLaunchTime < delay) return;

    BOOL persistMapping = [g_config[kATReporterConfigPersistClassMapping] boolValue];
    
    NSTimeInterval interval = [g_config[kATReporterConfigReportIntervalSeconds] doubleValue];
    if (interval <= 0) interval = kDefaultReportIntervalSeconds;
    NSTimeInterval last = [[NSUserDefaults standardUserDefaults] doubleForKey:kATLastReportTimeKey];
    if (last > 0 && now - last < interval && !persistMapping) {
        return;
    }

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
        if ([name isEqualToString:@"KSMultiKTVRoomInfo"]) {
            NSLog(@"KSMultiKTVRoomInfo index:%@ realized:%@",@(i),@(realized));
        }
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

    // 可选：将类映射表写入本地 plist，供后续离线分析使用
    BOOL persistMapping = [g_config[kATReporterConfigPersistClassMapping] boolValue];
    if (persistMapping && allNames.count > 0) {
        @try {
            NSMutableDictionary *mapping = [NSMutableDictionary dictionary];
            mapping[@"all_class_list"] = [allNames copy];
            mapping[@"metadata"] = [meta copy];
            
            NSString *dir = [self appThinnerDirectoryPath];
            
            NSString *fileName = [NSString stringWithFormat:@"class_mapping_%@_%@.plist",
                                  meta[@"app_version"] ?: @"",
                                  meta[@"build"] ?: @""];
            // 清理文件名中的非法字符
            fileName = [fileName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];                        
            NSString *fullPath = [dir stringByAppendingPathComponent:fileName];
            [mapping writeToFile:fullPath atomically:YES];
        } @catch (__unused NSException *e) {
            // 持久化失败不影响正常上报
        }
    }

    NSDictionary *payload = [ATReportPayloadBuilder buildPayloadWithAllClassNames:allNames
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
    if (!g_uploadBlock || resourceLine.length == 0 || !g_resourceBuffer) return;

    // 解析 resourceLine: path|size|count|loadMethod
    NSArray<NSString *> *parts = [resourceLine componentsSeparatedByString:@"|"];
    if (parts.count < 3) return;
    
    NSString *path = parts[0];
    NSUInteger size = (NSUInteger)[parts[1] integerValue];
    NSUInteger count = (NSUInteger)[parts[2] integerValue];
    NSString *loadMethod = parts.count >= 4 ? parts[3] : @"";
    
    // 按路径汇总：累加 count，保留最大 size 和第一个 loadMethod
    @synchronized(g_resourceBuffer) {
        NSDictionary *existing = g_resourceBuffer[path];
        if (existing) {
            NSUInteger existingCount = [existing[@"count"] unsignedIntegerValue];
            NSUInteger existingSize = [existing[@"size"] unsignedIntegerValue];
            count += existingCount;
            size = MAX(size, existingSize);
        }
        g_resourceBuffer[path] = @{
            @"size": @(size),
            @"count": @(count),
            @"loadMethod": loadMethod.length > 0 ? loadMethod : (existing[@"loadMethod"] ?: @"")
        };
    }
}

#pragma mark - tool

/// 获取/Documents/Caches/AppThinner/路径（URL 形式，推荐）
+ (NSURL *)appThinnerDirectoryURL {
    // 1. 获取Documents目录的URL（推荐用URL而非字符串，避免路径拼接错误）
    NSArray *documentsURLs = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                                     inDomains:NSUserDomainMask];
    if (documentsURLs.count == 0) {
        NSLog(@"获取Documents目录失败");
        return nil;
    }
    NSURL *documentsURL = documentsURLs.firstObject;
    
    // 2. 拼接Caches/AppThinner子目录
    NSURL *appThinnerURL = [documentsURL URLByAppendingPathComponent:@"Caches/AppThinner" isDirectory:YES];
    
    // 3. 检查并创建目录（不存在则创建，存在则直接返回）
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:appThinnerURL.path isDirectory:NULL]) {
        // withIntermediateDirectories:YES → 自动创建中间目录（如先创建Caches，再创建AppThinner）
        BOOL created = [fm createDirectoryAtURL:appThinnerURL
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:&error];
        if (!created) {
            NSLog(@"创建AppThinner目录失败：%@", error.localizedDescription);
            return nil;
        }
    }
    
    return appThinnerURL;
}

/// （可选）获取字符串形式的路径（兼容旧代码）
+ (NSString *)appThinnerDirectoryPath {
    NSURL *directoryURL = [self appThinnerDirectoryURL];
    return directoryURL ? directoryURL.path : nil;
}

#pragma mark - Resource Report Timer

+ (void)at_startResourceReportTimer {
    if (g_resourceReportTimer) return;
    
    g_resourceReportTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!g_resourceReportTimer) return;
    
    dispatch_source_set_timer(g_resourceReportTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kResourceReportInterval * NSEC_PER_SEC)),
                              (uint64_t)(kResourceReportInterval * NSEC_PER_SEC),
                              0);
    
    __weak Class weakSelf = self;
    dispatch_source_set_event_handler(g_resourceReportTimer, ^{
        [weakSelf at_flushResourceBuffer];
    });
    
    dispatch_resume(g_resourceReportTimer);
}

+ (void)at_stopResourceReportTimer {
    if (g_resourceReportTimer) {
        dispatch_source_cancel(g_resourceReportTimer);
        g_resourceReportTimer = nil;
    }
}

+ (void)at_flushResourceBuffer {
    if (!g_uploadBlock || !g_resourceBuffer) return;
    
    NSDictionary *bufferCopy = nil;
    @synchronized(g_resourceBuffer) {
        if (g_resourceBuffer.count == 0) return;
        bufferCopy = [g_resourceBuffer copy];
        [g_resourceBuffer removeAllObjects];
    }
    
    // 构建公共 metadata
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
    
    // 为每个汇总的资源构建 payload 并上报
    for (NSString *path in bufferCopy) {
        NSDictionary *info = bufferCopy[path];
        NSUInteger size = [info[@"size"] unsignedIntegerValue];
        NSUInteger count = [info[@"count"] unsignedIntegerValue];
        NSString *loadMethod = info[@"loadMethod"];
        
        // 重建 resourceLine: path|size|count|loadMethod
        NSString *resourceLine = [NSString stringWithFormat:@"%@|%lu|%lu|%@", path, (unsigned long)size, (unsigned long)count, loadMethod];
        
        // 解析 resourceName
        NSString *resourceName = nil;
        NSRange colonRange = [path rangeOfString:@":"];
        if (colonRange.location != NSNotFound && colonRange.location + 1 < path.length) {
            resourceName = [path substringFromIndex:colonRange.location + 1];
        } else {
            resourceName = path;
        }
        
        NSDictionary *payload = @{
            kATReporterPayloadKeyReportTime: @((long long)(now * 1000)),
            kATReporterPayloadKeyReportType: @"resources",
            kATReporterPayloadKeyUsedResourceString: resourceLine,
            kATReporterPayloadKeyTimeSinceLaunch: @(delta),
            kATReporterPayloadKeyResourceSize: @(size),
            kATReporterPayloadKeyResourceName: resourceName ?: @"",
            kATReporterPayloadKeyResourceLoadMethod: loadMethod ?: @"",
            kATReporterPayloadKeyMetadata: [meta copy],
            kATReporterPayloadKeyResourceUseCount: @(count)
        };
        
        g_uploadBlock(payload, 0, 1);
    }
}

@end
