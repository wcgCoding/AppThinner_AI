//
//  ATResourceUsageInfo.m
//  AppThinnerReporter
//

#import "ATResourceUsageInfo.h"

@implementation ATResourceUsageInfo

- (instancetype)initWithPath:(NSString *)path size:(NSUInteger)size {
    self = [super init];
    if (self) {
        _resourcePath = [path copy];
        _size = size;
        _callCount = 1;
    }
    return self;
}

- (NSString *)reportString {
    return [NSString stringWithFormat:@"%@|%lu|%lu", _resourcePath, (unsigned long)_size, (unsigned long)_callCount];
}

+ (instancetype)fromReportString:(NSString *)reportString {
    if (!reportString.length) return nil;
    NSArray *parts = [reportString componentsSeparatedByString:@"|"];
    if (parts.count < 3) return nil;
    NSString *path = parts[0];
    NSUInteger size = [parts[1] integerValue];
    NSUInteger count = [parts[2] integerValue];
    ATResourceUsageInfo *info = [[ATResourceUsageInfo alloc] initWithPath:path size:size];
    info.callCount = count;
    return info;
}

@end
