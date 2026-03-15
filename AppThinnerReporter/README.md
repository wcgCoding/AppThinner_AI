# AppThinnerReporter

iOS 现网运行时**类与资源使用情况**动态上报 Pod 库，与 [AppThinner / AppThinnerAnalyzer](https://github.com/your-org/AppThinner_AI) 看板配合使用。

## 作用

- 在宿主 App 内采集运行时「已实现类」及（可扩展）资源使用情况。
- 按与 AppThinner 约定好的**规范统一数据格式**上报或落盘。
- 便于当前工具**外部导入**时，与静态分析结果一并作为数据支撑，在看板中展示与排优。

## 数据格式约定

上报/落盘数据格式需与看板侧「外部无用类/无用资源」导入能力对齐，例如：

- **类使用**：全量类列表顺序、已实现类标识（0/1 位图或类名列表）、版本/设备等元数据。
- **资源使用**（可扩展）：资源 ID/路径列表、访问标识、采样时间等。
- **载体格式**：JSON / plist / CSV 等约定字段与编码，便于 AppThinner 解析与融合。

具体 schema 与 AppThinner 文档/ExternalDataImporter 保持一致。

## 集成方式

```ruby
# Podfile
pod 'AppThinnerReporter', :path => '../AppThinnerReporter'
```

## 使用

```objc
#import <AppThinnerReporter/AppThinnerReporter.h>

// 配置（可选，nil 则用默认：延迟 20 分钟、间隔 24 小时、位图模式）
NSDictionary *config = @{
    kATReporterConfigEnable: @YES,
    kATReporterConfigReportClassNames: @NO,        // NO = 上报 0/1 位图（省流量）
    kATReporterConfigDelaySeconds: @(20 * 60),     // 进入 App 后 20 分钟才允许上报
    kATReporterConfigReportIntervalSeconds: @(24 * 3600),
    kATReporterConfigCollectResources: @YES,       // 是否采集 imageNamed 等资源使用
};

[ATRuntimeUsageReporter startWithConfiguration:config uploadBlock:^(NSDictionary *payload, NSInteger segmentIndex, NSInteger segmentTotal) {
    // 将 payload 上传到自有后端，或写入沙盒供 AppThinner 导入
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    // 例如： [YourBeacon report:json]; 或 [json writeToFile:path atomically:YES];
}];

// 停止上报
[ATRuntimeUsageReporter stop];
```

- 触发时机：在满足「进入 App 时长 ≥ delaySeconds」且「距上次上报 ≥ reportIntervalSeconds」时，在 **App 进入后台** 时触发一次采集并调用 `uploadBlock`。
- 仅 64 位架构生效；非 64 位下会跳过类采集。

## 上报 Payload 格式（与看板约定）

| 字段 | 说明 |
|------|------|
| `report_time` | 上报时间戳（毫秒） |
| `all_class_count` | 全量 OC 类数量 |
| `all_class_list` | 全量类名数组（字典序，与位图一一对应） |
| `report_mode` | `"bitmap"` 或 `"class_names"` |
| `realized_bitmap_base64_gzip` | 0/1 位图经 GZIP+Base64（report_mode=bitmap 时存在） |
| `realized_class_names` | 已实现类名列表（report_mode=class_names 时存在） |
| `used_resource_string` | 资源使用情况字符串（每行 `path\|size\|count`，用换行符分隔），**仅资源独立上报 payload 中存在** |
| `time_since_launch` | 当前资源使用距离 App 启动的时长（秒），用于评估资源使用场景的优先级 |
| `resource_size` | 资源大小（字节），从 `used_resource_string` 中的第二段 `size` 解析得到 |
| `metadata` | app_version、build、device 等 |

**资源字符串格式**：每行一个资源，格式为 `path|size|count`，例如：
```
img:icon.png|1024|5
bundle:com.example.lib/Resources/image.png|2048|2
```

**资源路径前缀**：
- `img:` - 通过 `[UIImage imageNamed:]` 加载的图片
- `bundle:` - 通过 `[NSBundle pathForResource:ofType:]` 加载的资源，格式为 `bundle:bundleId/path`

看板端可将 `realized_bitmap_base64_gzip` 用 GZIP 解压后按位与 `all_class_list` 对齐，得到「已实现类」；全量类 − 已实现类 = 候选无用类，与静态结果融合展示。

## CSV 数据解析（上报平台导出 → AppThinnerAnalyzer）

支持将上报平台导出的 CSV 数据解析为 AppThinnerAnalyzer 可导入的外部数据格式：

```objc
#import <AppThinnerReporter/AppThinnerReporter.h>

NSError *error = nil;
ATExternalData *data = [ATReportDataParser parseCSVFile:@"/path/to/report.csv" error:&error];
if (data) {
    // 导出为 AppThinnerAnalyzer 可导入的格式
    [ATReportDataParser exportExternalData:data format:@"json" outputPath:@"/path/to/output.json" error:&error];
    // 或 CSV/TXT 格式
    // [ATReportDataParser exportExternalData:data format:@"csv" outputPath:@"/path/to/output.csv" error:&error];
}
```

**支持的 CSV 列**：
- 类相关：`class`、`className`、`realized_bitmap_base64_gzip`（需配合 `all_class_list` 解析）
- 资源相关：`resource`、`resource_path`、`used_resource_string`（格式：每行 `path|size|count`）

**导出格式**：
- `json` - JSON 格式，包含 `unusedClasses` 和 `unusedResources` 数组
- `csv` - CSV 格式，包含 `Type`（Class/Resource）和 `Path` 列
- `txt` - 文本格式，分别列出无用类和无用资源

## 资源监控能力

- **UIImage imageNamed:** - 监控通过 `imageNamed:` 加载的图片资源
- **NSBundle pathForResource:ofType:** - 监控通过 `pathForResource:ofType:` 加载的 bundle 资源（包括三方库）
- **完整路径记录** - 记录资源完整路径（含 bundle 标识），避免同名资源混淆
- **大小与调用次数** - 记录资源文件大小和调用次数，便于分析使用频率

## 工程说明

- 本仓库为主工程下的 **iOS Pod 库**，实现现网**类使用 + 资源使用**动态采集与规范格式上报。
- 类采集参考 doc/UnuseClassDetector（JXRealizeCalss / JXDeadCodeDetector），遍历所有 dyld 镜像的 `__objc_classlist`，通过 `flags & RW_REALIZED` 判断已实现类。
- 资源采集通过 hook `UIImage imageNamed:` 和 `NSBundle pathForResource:ofType:` 等方法，支持主 bundle 和三方库 bundle 的资源监控。

## License

与主工程一致。
