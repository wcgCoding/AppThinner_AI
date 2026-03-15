---
name: ios_unused_code_scanner  
description: iOS项目无用代码和资源扫描工具，支持Swift/Objective-C混合项目的静态分析。当用户需要：(1) 扫描和清理无用的类、方法、属性；(2) 检测未使用的图片、xib、storyboard等资源文件；(3) 分析代码引用关系和依赖图；(4) 生成详细的清理报告（HTML/CSV/JSON格式）；(5) 集成到CI/CD流程进行代码质量检查；(6) 优化项目体积和编译时间时使用。特别适用于大型iOS项目的代码清理和重构场景。
---

# iOS Unused Code Scanner

专业的iOS项目无用代码和资源扫描工具，支持Swift/Objective-C混合项目，提供精确的静态分析和详细的报告输出。

## 快速开始

### 基础扫描

```bash
# 扫描当前项目
./scripts/run_scan.sh

# 扫描指定项目
./scripts/run_scan.sh --project /path/to/ios/project

# 仅扫描代码（不扫描资源）
./scripts/run_scan.sh --code-only

# 快速扫描模式（跳过深度分析）
./scripts/run_scan.sh --quick
```

### Python API 使用

```python
from scripts.scanner import iOSUnusedScanner

# 初始化扫描器
scanner = iOSUnusedScanner(project_root='.')

# 执行扫描
results = scanner.scan()

# 生成报告
scanner.generate_reports(output_dir='./reports', formats=['html', 'json'])
```

## 核心功能

### 1. 扫描无用代码 (scan_unused_code)

扫描无用代码（类、方法、属性等）

**Parameters:**
- `project_root` (string, required) - iOS项目根目录路径，默认: "."
- `scan_type` (string, optional) - 扫描类型，可选值: "all", "code", "resources"，默认: "all"

**Returns:**
```json
{
  "success": true,
  "unused_classes": [...],
  "unused_methods": [...],
  "unused_resources": [...]
}
```

### 2. 扫描无用资源 (scan_unused_resources)

扫描无用资源文件（图片、xib/storyboard等）

**Parameters:**
- `project_root` (string, required) - iOS项目根目录路径，默认: "."
- `resource_types` (array, optional) - 资源类型列表，可选值: "images", "xibs", "storyboards", "all"，默认: ["all"]

**Returns:**
```json
{
  "success": true,
  "unused_resources": [...]
}
```

### 3. 生成报告 (generate_reports)

生成多种格式的报告

**Parameters:**
- `output_dir` (string, optional) - 输出目录路径，默认: "unused_scan_results"
- `formats` (array, optional) - 报告格式列表，可选值: "html", "csv", "json", "all"，默认: ["all"]

**Returns:**
```json
{
  "html_report": "./unused_scan_results/report.html",
  "csv_report": "./unused_scan_results/data.csv",
  "json_summary": "./unused_scan_results/summary.json"
}
```

### 4. 分析引用关系 (analyze_references)

分析代码引用关系

**Parameters:**
- `project_root` (string, required) - iOS项目根目录路径，默认: "."
- `depth` (integer, optional) - 分析深度，范围: 1-5，默认: 3

**Returns:**
```json
{
  "success": true,
  "total_symbols": 1250,
  "total_references": 3456,
  "reference_graph": {...}
}
```

### 5. 获取汇总信息 (get_summary)

获取扫描汇总信息

**Parameters:** 无

**Returns:**
```json
{
  "total_unused_items": 156,
  "unused_classes_count": 23,
  "unused_methods_count": 67,
  "unused_resources_count": 66,
  "total_size_bytes": 15925248
}
```

## 配置说明

配置文件位于 `assets/default.json`，可以自定义扫描行为。

### 扫描配置 (Scan Config)

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| `project_root` | string | 项目根目录 | "." |
| `output_dir` | string | 输出目录 | "unused_scan_results" |
| `enable_code_scan` | boolean | 启用代码扫描 | true |
| `enable_resource_scan` | boolean | 启用资源扫描 | true |
| `enable_reference_analysis` | boolean | 启用引用分析 | true |
| `file_source` | string | 文件数据源：`"directory"`=目录遍历，`"xcodeproj"`=从 .xcodeproj 引用 | "directory" |
| `xcodeproj_path` | string \| null | .xcodeproj 路径；为 null 时在 project_root 下自动查找 | null |

**文件数据源说明**：设为 `"xcodeproj"` 时，仅扫描工程内引用的文件（Sources + Resources），与 Xcode 实际编译/打包范围一致；设为 `"directory"` 时按目录递归收集（含未加入工程的文件）。

### 忽略规则 (Ignore Rules)

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| `ignore_directories` | array | 忽略的目录 | ["Pods", ".git", "build", "DerivedData", "Carthage"] |
| `ignore_files` | array | 忽略的文件 | ["main.m", "AppDelegate.h", "AppDelegate.m", "main.swift"] |
| `ignore_file_patterns` | array | 忽略的文件名模式（支持 `*Test*.{h,m,swift}` 等 fnmatch 与 `{a,b}` 展开） | ["*Test*.{h,m,swift}", "*Mock*", "*Spec*"] |

### 白名单配置 (Whitelist)

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| `classes` | array | 白名单类名（精确匹配） | 内置仅含通用 iOS/UIKit 基类 |
| `class_name_patterns` | array | 白名单类名通配（如 `*Base*ViewController`） | ["*Base*ViewController", "*Base*VC", "*Base*Cell"] |
| `methods` | array | 白名单方法名 | ["viewDidLoad", "viewWillAppear:", "application:didFinishLaunchingWithOptions:"] |

**说明**：项目专属白名单类（如业务基类、桥接类）请写在 `assets/default.json` 的 `whitelist.classes` 或 `whitelist.class_name_patterns` 中，与内置通用白名单合并生效。

## 使用示例

### Python API 示例

```python
from scripts.scanner import iOSUnusedScanner

scanner = iOSUnusedScanner(project_root='.')
results = scanner.scan()
scanner.generate_reports()
```

### 命令行使用示例

```bash
# 基本扫描
./scripts/run_scan.sh

# 扫描指定项目
./scripts/run_scan.sh --project /path/to/ios/project

# 仅扫描代码
./scripts/run_scan.sh --code-only

# 快速扫描模式
./scripts/run_scan.sh --quick
```

### Agent Skill API 调用

```python
from scripts.api import skill_main

# 扫描无用代码
result = skill_main("scan_unused_code", {
    "project_root": ".",
    "scan_type": "all"
})

# 生成报告
result = skill_main("generate_reports", {
    "output_dir": "./reports",
    "formats": ["html", "json"]
})
```

## 集成支持

### CI/CD 集成

支持主流 CI/CD 平台：
- **GitHub Actions**: 参考 `scripts/ci_integration.py`
- **Jenkins**: 支持 Pipeline 集成
- **GitLab CI**: 支持 .gitlab-ci.yml 配置
- **Fastlane**: 可作为 Fastlane lane 调用

集成示例详见 `references/integration.md`。

### 工具集成

与常用 iOS 开发工具无缝集成：
- **Xcode**: 支持 Xcode 项目和 Workspace
- **CocoaPods**: 自动识别 Pods 目录并排除
- **Carthage**: 自动识别 Carthage 目录并排除
- **Swift Package Manager**: 支持 SPM 项目结构

## 安装与依赖

### 系统要求

- **操作系统**: macOS 10.15+
- **Python**: 3.6 或更高版本
- **Xcode**: 建议 12.0+（用于项目解析）

### 安装步骤

```bash
# 用户级安装
./scripts/install.sh

# 可选：安装测试依赖（核心扫描器仅用标准库，无强制第三方依赖）
pip3 install -r requirements.txt

# 运行测试
./scripts/test.sh
```

## 参考文档

详细文档位于 `references/` 目录：

- **API 参考**: `references/api.md` - 完整的 API 接口文档
- **集成指南**: `references/integration.md` - CI/CD 集成详细说明
- **最佳实践**: `references/best_practices.md` - 使用建议和优化技巧

需要时可以使用 `read_file` 工具查看这些文档。

## 测试

```bash
# 运行所有测试
./scripts/test.sh

# 运行特定测试
python3 -m pytest tests/test_scanner.py -v

# 运行覆盖率测试
python3 -m pytest tests/test_scanner.py --cov=src --cov-report=html
```

## 安全与权限

### 所需权限

此技能需要以下权限：
- **读取文件**: 读取项目源代码和资源文件
- **写入文件**: 生成报告文件到指定目录
- **执行脚本**: 运行 Python 脚本进行分析

### 数据隐私

- 所有分析在本地执行，不上传任何代码到外部服务器
- 生成的报告仅保存在本地指定目录
- 不收集或传输任何项目信息

## 性能指标

### 扫描性能

根据项目规模的预期扫描时间：

| 项目规模 | 文件数量 | 扫描时间 |
|---------|---------|----------|
| 小型项目 | < 100 files | < 30秒 |
| 中型项目 | 100-500 files | 1-5分钟 |
| 大型项目 | 500-1000 files | 5-15分钟 |
| 超大项目 | > 1000 files | 15-30分钟 |

### 资源使用

- **内存占用**: 通常 < 500MB（可通过配置调整）
- **CPU 使用**: 支持多线程并行处理
- **磁盘空间**: 临时文件自动清理，报告大小通常 < 10MB

## 日志与监控

### 日志配置

- **日志级别**: INFO（可配置为 DEBUG 获取更详细信息）
- **日志文件**: `logs/scanner.log`
- **日志轮转**: 自动轮转，保留最近 7 天

### 监控指标

扫描过程中会记录以下指标：

- `scan_duration` - 总扫描耗时
- `files_processed` - 已处理文件数量
- `unused_items_found` - 发现的无用项数量
- `total_size_saved` - 可节省的总大小（字节）

## 常见问题

### Q: 如何处理误报？

A: 使用白名单配置排除特定的类、方法或资源。编辑 `assets/default.json` 中的 `whitelist` 部分。

### Q: 扫描速度太慢怎么办？

A: 可以使用 `--quick` 模式跳过深度引用分析，或者在配置中增加 `ignore_directories` 排除不需要扫描的目录。

### Q: 支持哪些 iOS 项目结构？

A: 支持标准 Xcode 项目、Workspace、CocoaPods、Carthage 和 Swift Package Manager 项目。

### Q: 如何在 CI 中使用？

A: 参考 `references/integration.md` 中的 CI/CD 集成示例，或查看 `scripts/ci_integration.py`。

---

**提示**: 首次使用建议先在小型测试项目上运行，熟悉工具行为后再应用到生产项目。
