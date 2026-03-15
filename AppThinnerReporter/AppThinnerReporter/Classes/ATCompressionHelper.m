//
//  ATCompressionHelper.m
//  AppThinnerReporter
//
//  使用 zlib 做 GZIP 格式压缩，便于看板端通用解压。
//

#import "ATCompressionHelper.h"
#import <zlib.h>

static const int kGzipWindowBits = 15 + 16;
static const int kMemLevel = 8;

@implementation ATCompressionHelper

+ (nullable NSData *)gzipData:(NSData *)data {
    if (!data || data.length == 0) return nil;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, kGzipWindowBits, kMemLevel, Z_DEFAULT_STRATEGY) != Z_OK)
        return nil;
    stream.avail_in = (uint32_t)data.length;
    stream.next_in = (Bytef *)data.bytes;
    NSMutableData *out = [NSMutableData dataWithLength:data.length * 1.2 + 64];
    int status;
    do {
        if (stream.avail_out == 0) {
            [out setLength:out.length + 1024];
            stream.avail_out = (uint32_t)(out.length - stream.total_out);
            stream.next_out = (Bytef *)out.mutableBytes + stream.total_out;
        }
        status = deflate(&stream, Z_FINISH);
    } while (status == Z_OK);
    deflateEnd(&stream);
    if (status != Z_STREAM_END) return nil;
    [out setLength:stream.total_out];
    return [out copy];
}

+ (nullable NSData *)gunzipData:(NSData *)data {
    if (!data || data.length == 0) return nil;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, kGzipWindowBits) != Z_OK) return nil;
    stream.avail_in = (uint32_t)data.length;
    stream.next_in = (Bytef *)data.bytes;
    NSMutableData *out = [NSMutableData dataWithLength:data.length * 2];
    int status;
    do {
        if (stream.avail_out == 0) {
            [out setLength:out.length + 1024];
            stream.avail_out = (uint32_t)(out.length - stream.total_out);
            stream.next_out = (Bytef *)out.mutableBytes + stream.total_out;
        }
        status = inflate(&stream, Z_SYNC_FLUSH);
    } while (status == Z_OK);
    inflateEnd(&stream);
    if (status != Z_STREAM_END && status != Z_BUF_ERROR) return nil;
    [out setLength:stream.total_out];
    return [out copy];
}

+ (nullable NSString *)base64GzipFromBitstrings:(NSArray<NSString *> *)bitstrings {
    if (!bitstrings.count) return nil;
    NSMutableData *raw = [NSMutableData data];
    for (NSString *str in bitstrings) {
        NSUInteger len = str.length;
        NSInteger byteCount = (len + 7) / 8;
        uint8_t *bytes = calloc((size_t)byteCount, 1);
        if (!bytes) return nil;
        for (NSUInteger i = 0; i < len; i++) {
            if ([str characterAtIndex:i] == '1')
                bytes[i / 8] |= (1 << (7 - (i % 8)));
        }
        [raw appendBytes:&len length:sizeof(NSUInteger)];
        [raw appendBytes:bytes length:(NSUInteger)byteCount];
        free(bytes);
    }
    NSData *gzip = [self gzipData:raw];
    if (!gzip) return nil;
    return [gzip base64EncodedStringWithOptions:0];
}

+ (NSArray<NSString *> *)bitstringsFromBase64Gzip:(NSString *)base64Gzip {
    if (!base64Gzip.length) return @[];
    NSData *gzip = [[NSData alloc] initWithBase64EncodedString:base64Gzip options:NSDataBase64DecodingIgnoreUnknownCharacters];
    NSData *raw = [self gunzipData:gzip];
    if (!raw.length) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSUInteger offset = 0;
    const uint8_t *bytes = raw.bytes;
    while (offset + sizeof(NSUInteger) <= raw.length) {
        NSUInteger len;
        memcpy(&len, bytes + offset, sizeof(NSUInteger));
        offset += sizeof(NSUInteger);
        NSInteger byteCount = (NSInteger)((len + 7) / 8);
        if (offset + (NSUInteger)byteCount > raw.length) break;
        NSMutableString *str = [NSMutableString stringWithCapacity:(NSUInteger)len];
        for (NSInteger i = 0; i < byteCount; i++) {
            uint8_t b = bytes[offset + (NSUInteger)i];
            for (NSInteger bit = 7; bit >= 0 && (NSUInteger)str.length < len; bit--)
                [str appendString:(b & (1 << bit)) ? @"1" : @"0"];
        }
        [result addObject:str];
        offset += (NSUInteger)byteCount;
    }
    return [result copy];
}

@end
