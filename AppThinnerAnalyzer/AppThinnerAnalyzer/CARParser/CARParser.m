//
// CARParser.m
// In-process Assets.car parser using CoreUI.
//

#import "CARParser.h"
#import "CoreUI.h"
#import <CoreGraphics/CoreGraphics.h>

static NSString *baseNameFromRenditionName(NSString *name) {
    if (!name.length) return name;
    NSArray *parts = [name componentsSeparatedByString:@"@"];
    return parts.firstObject ?: name;
}

NSArray<NSDictionary<NSString *, id> *> * _Nullable CARParserParseCARAtPath(NSString *path, NSError **outError) {
    if (!path.length) {
        if (outError) *outError = [NSError errorWithDomain:@"CARParser" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"Path is empty" }];
        return nil;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *err = nil;
    CUICatalog *catalog = [[CUICatalog alloc] initWithURL:url error:&err];
    if (err || !catalog) {
        if (outError) *outError = err ?: [NSError errorWithDomain:@"CARParser" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open catalog" }];
        return nil;
    }
    CUIStructuredThemeStore *store = [catalog _themeStore];
    if (!store || !store.themeStore || !store.themeStore.allAssetKeys) {
        if (outError) *outError = [NSError errorWithDomain:@"CARParser" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"Not a theme store or no keys" }];
        return nil;
    }
    id keys = store.themeStore.allAssetKeys;
    if (![keys isKindOfClass:[NSArray class]] || [keys count] == 0) {
        if (outError) *outError = [NSError errorWithDomain:@"CARParser" code:3 userInfo:@{ NSLocalizedDescriptionKey: @"allAssetKeys not an array or empty" }];
        return nil;
    }
    NSMutableDictionary<NSString *, NSNumber *> *byBaseName = [NSMutableDictionary dictionary];
    for (id keyObj in (NSArray *)keys) {
        CUIRenditionKey *key = (CUIRenditionKey *)keyObj;
        if (!key.keyList) continue;
        CUIThemeRendition *rendition = [store renditionWithKey:key.keyList];
        if (!rendition || !rendition.name) continue;
        NSData *data = rendition.data;
        NSUInteger size = data ? data.length : 0;
        if (size == 0 && [store respondsToSelector:@selector(lookupAssetForKey:)]) {
            NSData *lookupData = [store lookupAssetForKey:key.keyList];
            size = lookupData ? lookupData.length : 0;
        }
        NSString *base = baseNameFromRenditionName(rendition.name);
        if (base.length) {
            if (size > 0) {
                unsigned long long prev = [byBaseName[base] unsignedLongLongValue];
                byBaseName[base] = @(prev + size);
            } else {
                byBaseName[base] = @(0);
            }
        }
    }
    if (byBaseName.count == 0) {
        if (outError) *outError = [NSError errorWithDomain:@"CARParser" code:4 userInfo:@{ NSLocalizedDescriptionKey: @"Catalog opened but no renditions with data (keys=0 or all rendition.data empty, possibly sandbox/format limitation)" }];
        return nil;
    }
    unsigned long long totalSize = 0;
    for (NSNumber *n in byBaseName.allValues) totalSize += n.unsignedLongLongValue;
    if (totalSize == 0) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        unsigned long long fileSize = [attrs[NSFileSize] unsignedLongLongValue];
        if (fileSize > 0) {
            unsigned long long perAsset = fileSize / (unsigned long long)byBaseName.count;
            for (NSString *k in byBaseName.allKeys) byBaseName[k] = @(perAsset);
        } else {
            if (outError) *outError = [NSError errorWithDomain:@"CARParser" code:5 userInfo:@{ NSLocalizedDescriptionKey: @"No rendition data and could not read file size for fallback" }];
            return nil;
        }
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:byBaseName.count];
    [byBaseName enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull name, NSNumber * _Nonnull size, BOOL * _Nonnull stop) {
        [result addObject:@{ @"name": name, @"size": size }];
    }];
    return [result copy];
}
