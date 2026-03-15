//
// CARParser.h
// In-process Assets.car parser using CoreUI (no xcrun/assetutil).
// Reference: https://github.com/insidegui/AssetCatalogTinkerer
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Parses a .car file and returns array of @{ @"name": assetBaseName, @"size": @(bytes) }.
/// Same semantics as assetutil -I: names are logical (e.g. "Logo"), sizes are per-rendition summed by base name.
/// Returns nil on failure (e.g. not a theme store, or CoreUI error).
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, id> *> * _Nullable CARParserParseCARAtPath(NSString *path, NSError ** _Nullable outError);

NS_ASSUME_NONNULL_END
