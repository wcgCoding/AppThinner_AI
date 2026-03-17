//
//  ATReporterKeys.h
//  AppThinnerReporter
//
//  统一定义运行时上报 payload 中使用的字段 key，供接入方和内部组件复用。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 通用字段
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyReportTime;          // "report_time"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyReportType;          // "report_type" -> 'resources' or 'code'
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyMetadata;            // "metadata"

/// 类使用 payload 字段
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyAllClassCount;       // "all_class_count"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyAllClassList;        // "all_class_list"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyRealizedBitmapBase64Gzip; // "realized_bitmap_base64_gzip"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyRealizedClassNames;  // "realized_class_names"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyReportMode;          // "report_mode" -> 'bitmap' or 'class_names'

/// 资源使用 payload 字段
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyUsedResourceString;   // "used_resource_string"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyTimeSinceLaunch;      // "time_since_launch"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyResourceSize;         // "resource_size"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyResourceName;         // "resource_name"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyResourceLoadMethod;   // "resource_load_method" -> "UIImage.imageNamed:" / "NSBundle.pathForResource*"
FOUNDATION_EXPORT NSString * const kATReporterPayloadKeyResourceUseCount;     // "resource_use_count"

NS_ASSUME_NONNULL_END

