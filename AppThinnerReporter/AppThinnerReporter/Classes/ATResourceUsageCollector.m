//
//  ATResourceUsageCollector.m
//  AppThinnerReporter
//
//  通过 hook UIImage imageNamed:、NSBundle pathForResource 等记录使用到的资源，供上报 payload 使用。
//

#import "ATResourceUsageCollector.h"
#import "ATResourceUsageInfo.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/lock.h>

static NSString * const kATResourcePrefixImage = @"img:";
static NSString * const kATResourcePrefixBundle = @"bundle:";

@interface ATResourceUsageCollector ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, ATResourceUsageInfo *> *resourceMap;
@property (nonatomic, assign) os_unfair_lock lock;
@property (nonatomic, assign) BOOL collecting;
@property (nonatomic, copy, nullable) ATResourceInternalReportBlock internalReportBlock;
@end

@implementation ATResourceUsageCollector

+ (instancetype)shared {
    static ATResourceUsageCollector *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[ATResourceUsageCollector alloc] init]; });
    return one;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _resourceMap = [NSMutableDictionary dictionary];
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (void)startCollecting {
    if (_collecting) return;
    _collecting = YES;
    [self swizzleUIImageImageNamed];
    [self swizzleNSBundlePathForResource];
}

- (void)stopCollecting {
    _collecting = NO;
    [self unswizzleUIImageImageNamed];
    [self unswizzleNSBundlePathForResource];
}

- (NSArray<ATResourceUsageInfo *> *)currentUsedResourceInfos {
    os_unfair_lock_lock(&_lock);
    NSArray *arr = [_resourceMap allValues];
    os_unfair_lock_unlock(&_lock);
    return arr ?: @[];
}

- (NSString *)resourceReportString {
    os_unfair_lock_lock(&_lock);
    NSMutableArray *lines = [NSMutableArray arrayWithCapacity:_resourceMap.count];
    for (ATResourceUsageInfo *info in _resourceMap.allValues) {
        [lines addObject:[info reportString]];
    }
    os_unfair_lock_unlock(&_lock);
    return [lines componentsJoinedByString:@"\n"];
}

- (void)clear {
    os_unfair_lock_lock(&_lock);
    [_resourceMap removeAllObjects];
    os_unfair_lock_unlock(&_lock);
}

- (void)setInternalReportBlock:(ATResourceInternalReportBlock)block {
    os_unfair_lock_lock(&_lock);
    _internalReportBlock = [block copy];
    os_unfair_lock_unlock(&_lock);
}

- (void)recordResourcePath:(NSString *)path
                      size:(NSUInteger)size
                loadMethod:(nullable NSString *)loadMethod {
    if (!path.length) return;
    
    // 过滤掉仅表示「bundle 容器」本身的记录，例如：
    // bundle:com.tencent.QQWeSing/WSResources.bundle
    // 真实的资源文件会以 ".bundle/" 作为中间路径，例如 ".../WSResources.bundle/xxx.png"
    if ([path hasPrefix:kATResourcePrefixBundle]) {
        NSString *rest = [path substringFromIndex:kATResourcePrefixBundle.length];
        if ([rest hasSuffix:@".bundle"] && [rest rangeOfString:@".bundle/"].location == NSNotFound) {
            return;
        }
    }
    ATResourceInternalReportBlock reportBlock = nil;
    ATResourceUsageInfo *updatedInfo = nil;
    os_unfair_lock_lock(&_lock);
    ATResourceUsageInfo *info = _resourceMap[path];
    if (info) {
        info.callCount++;
        if (size > 0 && info.size == 0) info.size = size;
        if (loadMethod.length && info.loadMethod.length == 0) {
            info.loadMethod = loadMethod;
        }
    } else {
        _resourceMap[path] = [[ATResourceUsageInfo alloc] initWithPath:path size:size];
        info = _resourceMap[path];
        if (loadMethod.length) {
            info.loadMethod = loadMethod;
        }
    }
    updatedInfo = info;
    reportBlock = _internalReportBlock;
    os_unfair_lock_unlock(&_lock);

    if (reportBlock && updatedInfo) {
        reportBlock([updatedInfo reportString]);
    }
}

- (NSUInteger)fileSizeAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
    return attrs ? [attrs[NSFileSize] unsignedIntegerValue] : 0;
}

// MARK: - UIImage imageNamed: hook

static UIImage * (*original_imageNamed_)(id, SEL, NSString *) = NULL;
static UIImage * (*original_imageNamed_inBundle_compatible_)(id, SEL, NSString *, NSBundle *, UITraitCollection *) = NULL;

static UIImage *at_swizzled_imageNamed_(id self, SEL _cmd, NSString *name) {
    UIImage *image = original_imageNamed_(self, _cmd, name);
    
    if (name.length) {
        ATResourceUsageCollector *c = [ATResourceUsageCollector shared];
        if (c.collecting) {
            NSString *pathKey = [kATResourcePrefixImage stringByAppendingString:name];
            // 通过 UIImage 估算大小：width * height * scale^2 * 4（RGBA）
            NSUInteger estimatedSize = 0;
            if (image) {
                CGSize size = image.size;
                CGFloat scale = image.scale > 0 ? image.scale : 1.0;
                double pixels = (double)size.width * scale * (double)size.height * scale;
                estimatedSize = (NSUInteger)llround(pixels * 4.0);
            }
            [c recordResourcePath:pathKey size:estimatedSize loadMethod:@"UIImage.imageNamed:"];
        }
    }
    return image;
}

static UIImage *at_swizzled_imageNamed_inBundle_compatible_(id self,
                                                            SEL _cmd,
                                                            NSString *name,
                                                            NSBundle *bundle,
                                                            UITraitCollection *traitCollection) {
    UIImage *image = original_imageNamed_inBundle_compatible_(self, _cmd, name, bundle, traitCollection);
    
    if (name.length) {
        ATResourceUsageCollector *c = [ATResourceUsageCollector shared];
        if (c.collecting) {
            NSBundle *effectiveBundle = bundle ?: [NSBundle mainBundle];
            NSString *bundleId = effectiveBundle.bundleIdentifier ?: @"main";
            
            NSString *pathKey = [NSString stringWithFormat:@"%@%@/%@", kATResourcePrefixBundle, bundleId, name];
            
            NSUInteger estimatedSize = 0;
            if (image) {
                CGSize size = image.size;
                CGFloat scale = image.scale > 0 ? image.scale : 1.0;
                double pixels = (double)size.width * scale * (double)size.height * scale;
                estimatedSize = (NSUInteger)llround(pixels * 4.0);
            }
            
            [c recordResourcePath:pathKey
                             size:estimatedSize
                       loadMethod:@"UIImage.imageNamed:inBundle:compatibleWithTraitCollection:"];
        }
    }
    
    return image;
}

- (void)swizzleUIImageImageNamed {
    Class cls = [UIImage class];
    
    // swizzle +imageNamed:
    SEL sel = @selector(imageNamed:);
    Method m = class_getClassMethod(cls, sel);
    if (m) {
        IMP imp = method_getImplementation(m);
        if (imp != (IMP)at_swizzled_imageNamed_) {
            original_imageNamed_ = (void *)imp;
            method_setImplementation(m, (IMP)at_swizzled_imageNamed_);
        }
    }
    
    // swizzle +imageNamed:inBundle:compatibleWithTraitCollection:
    SEL sel2 = @selector(imageNamed:inBundle:compatibleWithTraitCollection:);
    Method m2 = class_getClassMethod(cls, sel2);
    if (m2) {
        IMP imp2 = method_getImplementation(m2);
        if (imp2 != (IMP)at_swizzled_imageNamed_inBundle_compatible_) {
            original_imageNamed_inBundle_compatible_ = (void *)imp2;
            method_setImplementation(m2, (IMP)at_swizzled_imageNamed_inBundle_compatible_);
        }
    }
}

- (void)unswizzleUIImageImageNamed {
    Class cls = [UIImage class];
    
    if (original_imageNamed_) {
        SEL sel = @selector(imageNamed:);
        Method m = class_getClassMethod(cls, sel);
        if (m) method_setImplementation(m, (IMP)original_imageNamed_);
        original_imageNamed_ = NULL;
    }
    
    if (original_imageNamed_inBundle_compatible_) {
        SEL sel2 = @selector(imageNamed:inBundle:compatibleWithTraitCollection:);
        Method m2 = class_getClassMethod(cls, sel2);
        if (m2) method_setImplementation(m2, (IMP)original_imageNamed_inBundle_compatible_);
        original_imageNamed_inBundle_compatible_ = NULL;
    }
}

// MARK: - NSBundle pathForResource:ofType: hook

static NSString * (*original_pathForResource_ofType_)(id, SEL, NSString *, NSString *) = NULL;
static NSString * (*original_pathForResource_ofType_inDirectory_)(id, SEL, NSString *, NSString *, NSString *) = NULL;
static NSString * (*original_pathForResource_ofType_inDirectory_forLocalization_)(id, SEL, NSString *, NSString *, NSString *, NSString *) = NULL;

static NSString *at_swizzled_pathForResource_ofType_(id self, SEL _cmd, NSString *name, NSString *ext) {
    NSString *result = original_pathForResource_ofType_(self, _cmd, name, ext);
    if (result.length && ![ext isEqualToString:@"bundle"]) {
        ATResourceUsageCollector *c = [ATResourceUsageCollector shared];
        if (c.collecting) {
            NSBundle *bundle = (NSBundle *)self;
            NSString *bundleId = bundle.bundleIdentifier ?: @"main";
            NSString *path = [NSString stringWithFormat:@"%@%@/%@%@", kATResourcePrefixBundle, bundleId, name, ext ? [@"." stringByAppendingString:ext] : @""];
            NSUInteger size = [c fileSizeAtPath:result];
            [c recordResourcePath:path size:size loadMethod:@"NSBundle.pathForResource:ofType:"];
        }
    }
    return result;
}

static NSString *at_swizzled_pathForResource_ofType_inDirectory_(id self, SEL _cmd, NSString *name, NSString *ext, NSString *subpath) {
    NSString *result = original_pathForResource_ofType_inDirectory_(self, _cmd, name, ext, subpath);
    if (result.length && ![ext isEqualToString:@"bundle"]) {
        ATResourceUsageCollector *c = [ATResourceUsageCollector shared];
        if (c.collecting) {
            NSBundle *bundle = (NSBundle *)self;
            NSString *bundleId = bundle.bundleIdentifier ?: @"main";
            NSString *fullSubpath = subpath.length ? [subpath stringByAppendingPathComponent:name] : name;
            NSString *path = [NSString stringWithFormat:@"%@%@/%@%@", kATResourcePrefixBundle, bundleId, fullSubpath, ext ? [@"." stringByAppendingString:ext] : @""];
            NSUInteger size = [c fileSizeAtPath:result];
            [c recordResourcePath:path size:size loadMethod:@"NSBundle.pathForResource:ofType:inDirectory:"];
        }
    }
    return result;
}

static NSString *at_swizzled_pathForResource_ofType_inDirectory_forLocalization_(id self, SEL _cmd, NSString *name, NSString *ext, NSString *subpath, NSString *localizationName) {
    NSString *result = original_pathForResource_ofType_inDirectory_forLocalization_(self, _cmd, name, ext, subpath, localizationName);
    if (result.length && ![ext isEqualToString:@"bundle"]) {
        ATResourceUsageCollector *c = [ATResourceUsageCollector shared];
        if (c.collecting) {
            NSBundle *bundle = (NSBundle *)self;
            NSString *bundleId = bundle.bundleIdentifier ?: @"main";
            NSString *fullSubpath = subpath.length ? [subpath stringByAppendingPathComponent:name] : name;
            NSString *path = [NSString stringWithFormat:@"%@%@/%@%@", kATResourcePrefixBundle, bundleId, fullSubpath, ext ? [@"." stringByAppendingString:ext] : @""];
            NSUInteger size = [c fileSizeAtPath:result];
            [c recordResourcePath:path size:size loadMethod:@"NSBundle.pathForResource:ofType:inDirectory:forLocalization:"];
        }
    }
    return result;
}

- (void)swizzleNSBundlePathForResource {
    Class cls = [NSBundle class];
    
    SEL sel1 = @selector(pathForResource:ofType:);
    Method m1 = class_getInstanceMethod(cls, sel1);
    if (m1) {
        IMP imp = method_getImplementation(m1);
        if (imp != (IMP)at_swizzled_pathForResource_ofType_) {
            original_pathForResource_ofType_ = (void *)imp;
            method_setImplementation(m1, (IMP)at_swizzled_pathForResource_ofType_);
        }
    }
    
    SEL sel2 = @selector(pathForResource:ofType:inDirectory:);
    Method m2 = class_getInstanceMethod(cls, sel2);
    if (m2) {
        IMP imp = method_getImplementation(m2);
        if (imp != (IMP)at_swizzled_pathForResource_ofType_inDirectory_) {
            original_pathForResource_ofType_inDirectory_ = (void *)imp;
            method_setImplementation(m2, (IMP)at_swizzled_pathForResource_ofType_inDirectory_);
        }
    }
    
    SEL sel3 = @selector(pathForResource:ofType:inDirectory:forLocalization:);
    Method m3 = class_getInstanceMethod(cls, sel3);
    if (m3) {
        IMP imp = method_getImplementation(m3);
        if (imp != (IMP)at_swizzled_pathForResource_ofType_inDirectory_forLocalization_) {
            original_pathForResource_ofType_inDirectory_forLocalization_ = (void *)imp;
            method_setImplementation(m3, (IMP)at_swizzled_pathForResource_ofType_inDirectory_forLocalization_);
        }
    }
}

- (void)unswizzleNSBundlePathForResource {
    Class cls = [NSBundle class];
    
    if (original_pathForResource_ofType_) {
        SEL sel = @selector(pathForResource:ofType:);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) method_setImplementation(m, (IMP)original_pathForResource_ofType_);
        original_pathForResource_ofType_ = NULL;
    }
    
    if (original_pathForResource_ofType_inDirectory_) {
        SEL sel = @selector(pathForResource:ofType:inDirectory:);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) method_setImplementation(m, (IMP)original_pathForResource_ofType_inDirectory_);
        original_pathForResource_ofType_inDirectory_ = NULL;
    }
    
    if (original_pathForResource_ofType_inDirectory_forLocalization_) {
        SEL sel = @selector(pathForResource:ofType:inDirectory:forLocalization:);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) method_setImplementation(m, (IMP)original_pathForResource_ofType_inDirectory_forLocalization_);
        original_pathForResource_ofType_inDirectory_forLocalization_ = NULL;
    }
}

@end
