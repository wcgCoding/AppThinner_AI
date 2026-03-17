//
//  ATResourceUsageInfo.h
//  AppThinnerReporter
//
//  资源使用信息模型：路径、大小、调用次数
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 资源使用信息
@interface ATResourceUsageInfo : NSObject

/// 资源完整标识（如 "img:icon.png" 或 "bundle:com.example.lib/Resources/image.png"）
@property (nonatomic, copy) NSString *resourcePath;

/// 资源大小（字节），如果无法获取则为 0
@property (nonatomic, assign) NSUInteger size;

/// 调用次数
@property (nonatomic, assign) NSUInteger callCount;

/// 原始 hook 方法名（例如 "UIImage.imageNamed:" / "UIImage.imageNamed:inBundle:compatibleWithTraitCollection:" / "NSBundle.pathForResource:ofType:"）
@property (nonatomic, copy, nullable) NSString *loadMethod;

- (instancetype)initWithPath:(NSString *)path size:(NSUInteger)size;

/// 格式化为上报字符串：格式 "path|size|count|loadMethod"（loadMethod 可为空字符串）
- (NSString *)reportString;

/// 从上报字符串解析（格式 "path|size|count|loadMethod"）
+ (nullable instancetype)fromReportString:(NSString *)reportString;

@end

NS_ASSUME_NONNULL_END
