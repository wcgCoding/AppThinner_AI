//
//  ATCompressionHelper.h
//  AppThinnerReporter
//
//  GZIP 压缩/解压，用于 0/1 位图等上报数据，与看板端解析约定一致。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATCompressionHelper : NSObject

/// 将 0/1 字符串压缩为 GZIP 后 Base64。多段时每段一个 0/1 字符串，按顺序传入。
+ (nullable NSString *)base64GzipFromBitstrings:(NSArray<NSString *> *)bitstrings;

/// 从 Base64(GZIP(data)) 解压回 0/1 字符串数组（与 compress 时顺序一致）。
+ (NSArray<NSString *> *)bitstringsFromBase64Gzip:(NSString *)base64Gzip;

@end

NS_ASSUME_NONNULL_END
