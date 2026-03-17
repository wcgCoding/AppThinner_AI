//
//  ATReporterKeys.m
//  AppThinnerReporter
//

#import "ATReporterKeys.h"

/// 通用字段
NSString * const kATReporterPayloadKeyReportTime = @"report_time";
NSString * const kATReporterPayloadKeyReportType = @"report_type"; // resources or code
NSString * const kATReporterPayloadKeyMetadata   = @"metadata";

/// 类使用 payload 字段
NSString * const kATReporterPayloadKeyAllClassCount              = @"all_class_count";
NSString * const kATReporterPayloadKeyAllClassList               = @"all_class_list";
NSString * const kATReporterPayloadKeyRealizedBitmapBase64Gzip   = @"realized_bitmap_base64_gzip";
NSString * const kATReporterPayloadKeyRealizedClassNames         = @"realized_class_names";
NSString * const kATReporterPayloadKeyReportMode                 = @"report_mode";

/// 资源使用 payload 字段
NSString * const kATReporterPayloadKeyUsedResourceString         = @"used_resource_string";
NSString * const kATReporterPayloadKeyTimeSinceLaunch            = @"time_since_launch";
NSString * const kATReporterPayloadKeyResourceSize               = @"resource_size";
NSString * const kATReporterPayloadKeyResourceName               = @"resource_name";
NSString * const kATReporterPayloadKeyResourceLoadMethod         = @"resource_load_method";
NSString * const kATReporterPayloadKeyResourceUseCount           = @"resource_use_count";

