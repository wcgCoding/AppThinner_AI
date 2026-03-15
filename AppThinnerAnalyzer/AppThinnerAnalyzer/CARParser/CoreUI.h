//
// Minimal CoreUI declarations for in-process .car parsing.
// Reference: https://github.com/insidegui/AssetCatalogTinkerer (ACS/Private Headers/CoreUI.h)
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CUIThemeRendition : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSData *data;
@end

@interface CUIRenditionKey : NSObject
@property (readonly) struct _renditionkeytoken *keyList;
@end

struct _renditionkeytoken {
    unsigned short identifier;
    unsigned short value;
};

@interface CUICommonAssetStorage : NSObject
@property (readonly) id allAssetKeys;
@end

@interface CUIStructuredThemeStore : NSObject
- (NSData *)lookupAssetForKey:(struct _renditionkeytoken *)key;
- (CUIThemeRendition *)renditionWithKey:(const struct _renditionkeytoken *)key;
@property (readonly) CUICommonAssetStorage *themeStore;
@end

@interface CUICatalog : NSObject
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)outError;
- (CUIStructuredThemeStore *)_themeStore;
@end
