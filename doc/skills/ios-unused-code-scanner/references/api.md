# API Reference

## 概述

iOS无用代码扫描器提供了三层API接口:
1. **核心扫描器API** - 底层扫描功能
2. **Agent Skill API** - 标准Agent接口
3. **命令行API** - Shell脚本接口

---

## 核心扫描器API

### iOSUnusedScanner

主扫描器类，提供完整的扫描和分析功能。

#### 构造函数

```python
iOSUnusedScanner(project_root: str, config_file: str = None)
```

**参数:**
- `project_root` (str): iOS项目根目录路径
- `config_file` (str, optional): 配置文件路径，默认使用 `configs/default.json`

**示例:**
```python
from src.scanner import iOSUnusedScanner

scanner = iOSUnusedScanner(
    project_root="/path/to/ios/project",
    config_file="configs/default.json"
)
```

---

#### scan()

执行项目扫描，检测无用代码和资源。

```python
def scan(scan_type: str = "all") -> dict:
```

**参数:**
- `scan_type` (str): 扫描类型
  - `"all"`: 扫描代码和资源（默认）
  - `"code"`: 仅扫描代码
  - `"resources"`: 仅扫描资源

**返回值:**
```python
{
    "success": True,
    "scan_type": "all",
    "scan_time": "2024-01-25T14:30:00",
    "unused_classes": [
        {
            "name": "UnusedViewController",
            "file_path": "Classes/UI/UnusedViewController.m",
            "line_number": 10,
            "type": "objective-c"
        },
        ...
    ],
    "unused_methods": [
        {
            "name": "unusedMethod",
            "class_name": "SomeClass",
            "file_path": "Classes/Service/SomeService.m",
            "line_number": 45,
            "type": "objective-c"
        },
        ...
    ],
    "unused_resources": [
        {
            "name": "unused_image.png",
            "file_path": "Resources/Images/unused_image.png",
            "size_bytes": 102400,
            "type": "image"
        },
        ...
    ]
}
```

**示例:**
```python
# 扫描所有
results = scanner.scan()

# 仅扫描代码
code_results = scanner.scan(scan_type="code")

# 仅扫描资源
resource_results = scanner.scan(scan_type="resources")
```

---

#### generate_reports()

生成多种格式的扫描报告。

```python
def generate_reports(output_dir: str = None, formats: list = None) -> dict:
```

**参数:**
- `output_dir` (str, optional): 输出目录，默认为 `unused_scan_results`
- `formats` (list, optional): 报告格式列表，默认为 `["html", "csv", "json"]`
  - `"html"`: HTML交互式报告
  - `"csv"`: CSV数据文件
  - `"json"`: JSON汇总数据
  - `"all"`: 生成所有格式

**返回值:**
```python
{
    "html_report": "./unused_scan_results/unused_scan_report.html",
    "csv_report": "./unused_scan_results/unused_scan_report.csv",
    "json_summary": "./unused_scan_results/scan_summary.json"
}
```

**示例:**
```python
# 生成所有格式报告
reports = scanner.generate_reports()

# 仅生成HTML报告
html_report = scanner.generate_reports(formats=["html"])

# 指定输出目录
reports = scanner.generate_reports(output_dir="./custom_reports")
```

---

#### get_summary()

获取扫描汇总统计信息。

```python
def get_summary() -> dict:
```

**返回值:**
```python
{
    "scan_time": "2024-01-25T14:30:00",
    "scan_duration": 15.8,  # 秒
    "project_path": "/path/to/project",
    "total_unused_items": 156,
    "unused_classes_count": 23,
    "unused_methods_count": 67,
    "unused_resources_count": 66,
    "total_size_bytes": 15925248,
    "files_scanned": 482,
    "performance_metrics": {
        "scan_speed": "30.5 files/sec",
        "memory_used_mb": 256
    }
}
```

**示例:**
```python
summary = scanner.get_summary()
print(f"发现 {summary['total_unused_items']} 个无用项")
print(f"可节省 {summary['total_size_bytes'] / 1024 / 1024:.2f} MB")
```

---

#### analyze_references()

分析代码引用关系，构建依赖图。

```python
def analyze_references(depth: int = 3) -> dict:
```

**参数:**
- `depth` (int): 分析深度，范围 1-5，默认为 3
  - 1: 直接引用
  - 3: 三层引用关系（推荐）
  - 5: 深度引用分析（较慢）

**返回值:**
```python
{
    "success": True,
    "total_symbols": 1250,
    "total_references": 3456,
    "depth": 3,
    "reference_graph": {
        "ClassA": ["ClassB", "ClassC"],
        "ClassB": ["ClassD"],
        ...
    },
    "orphan_symbols": ["UnreferencedClass1", "UnreferencedClass2"],
    "circular_references": [
        ["ClassX", "ClassY", "ClassX"]
    ]
}
```

**示例:**
```python
# 标准深度分析
refs = scanner.analyze_references()

# 快速分析（仅直接引用）
quick_refs = scanner.analyze_references(depth=1)

# 深度分析
deep_refs = scanner.analyze_references(depth=5)
```

---

## Agent Skill API

### skill_main()

Agent Skill主入口函数。

```python
def skill_main(action: str, params: dict) -> dict:
```

**参数:**
- `action` (str): 操作名称
  - `"scan_unused_code"`: 扫描无用代码
  - `"scan_unused_resources"`: 扫描无用资源
  - `"generate_reports"`: 生成报告
  - `"analyze_references"`: 分析引用关系
  - `"get_summary"`: 获取汇总信息

- `params` (dict): 操作参数（根据action不同而不同）

**返回值:**
```python
{
    "success": True,
    "action": "scan_unused_code",
    "result": { ... },  # 操作结果
    "message": "扫描完成",
    "timestamp": "2024-01-25T14:30:00"
}
```

**示例:**
```python
from src.api import skill_main

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

# 获取汇总
result = skill_main("get_summary", {})
```

---

### skill_info()

获取Skill信息。

```python
def skill_info() -> dict:
```

**返回值:**
```python
{
    "name": "ios_unused_code_scanner",
    "version": "1.0.0",
    "description": "iOS无用代码及资源扫描工具",
    "capabilities": [
        "scan_unused_code",
        "scan_unused_resources",
        "generate_reports",
        "analyze_references",
        "get_summary"
    ],
    "author": "AI Assistant",
    "status": "stable"
}
```

---

### skill_health()

健康检查函数。

```python
def skill_health() -> dict:
```

**返回值:**
```python
{
    "status": "healthy",
    "checks": {
        "python_version": "3.9.0",
        "dependencies": "ok",
        "config_file": "ok",
        "permissions": "ok"
    },
    "timestamp": "2024-01-25T14:30:00"
}
```

---

## 命令行API

### run_scan.sh

主执行脚本。

```bash
./scripts/run_scan.sh [OPTIONS] [PROJECT_PATH]
```

**选项:**

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--project PATH` | 项目路径 | 当前目录 |
| `--code-only` | 仅扫描代码 | - |
| `--resource-only` | 仅扫描资源 | - |
| `--output DIR` | 输出目录 | unused_scan_results |
| `--config FILE` | 配置文件 | configs/default.json |
| `--quick` | 快速扫描模式 | - |
| `--full` | 完整扫描模式 | - |
| `--format FORMAT` | 报告格式 | all |
| `--verbose` | 详细输出 | - |
| `--debug` | 调试模式 | - |
| `--help` | 显示帮助 | - |

**示例:**
```bash
# 基本扫描
./scripts/run_scan.sh

# 扫描指定项目
./scripts/run_scan.sh --project /path/to/ios/project

# 仅扫描代码
./scripts/run_scan.sh --code-only

# 快速扫描（跳过引用分析）
./scripts/run_scan.sh --quick

# 完整扫描（深度分析）
./scripts/run_scan.sh --full

# 仅生成HTML报告
./scripts/run_scan.sh --format html

# 详细输出
./scripts/run_scan.sh --verbose
```

---

## 配置文件格式

### 配置文件结构

```json
{
    "skill": {
        "name": "ios_unused_code_scanner",
        "version": "1.0.0"
    },
    "scan_config": {
        "project_root": ".",
        "output_dir": "unused_scan_results",
        "enable_code_scan": true,
        "enable_resource_scan": true,
        "enable_reference_analysis": true
    },
    "ignore_rules": {
        "ignore_directories": [
            "Pods",
            ".git",
            "build"
        ],
        "ignore_files": [
            "main.m",
            "AppDelegate.h"
        ]
    },
    "whitelist": {
        "classes": [
            "AppDelegate",
            "ViewController"
        ],
        "methods": [
            "viewDidLoad",
            "viewWillAppear:"
        ]
    },
    "performance": {
        "max_concurrent_scans": 4,
        "chunk_size": 100,
        "timeout_seconds": 300
    }
}
```

---

## 错误处理

所有API调用都返回标准化的错误响应:

```python
{
    "success": False,
    "error": "错误描述",
    "error_code": "ERROR_CODE",
    "details": {
        "file": "scanner.py",
        "line": 123,
        "traceback": "..."
    }
}
```

**常见错误码:**

| 错误码 | 说明 |
|--------|------|
| `PROJECT_NOT_FOUND` | 项目路径不存在 |
| `CONFIG_INVALID` | 配置文件格式错误 |
| `PERMISSION_DENIED` | 权限不足 |
| `SCAN_TIMEOUT` | 扫描超时 |
| `MEMORY_LIMIT` | 内存限制 |

---

## 性能考虑

### 扫描性能

- **小型项目** (< 100文件): 通常 < 30秒
- **中型项目** (100-500文件): 1-5分钟
- **大型项目** (> 500文件): 5-15分钟

### 优化建议

1. 使用 `--quick` 模式跳过引用分析
2. 调整 `max_concurrent_scans` 参数
3. 合理配置 `ignore_rules`
4. 使用增量扫描（未来版本）

---

## 更多资源

- [集成指南](integration.md)
- [最佳实践](best_practices.md)
- [README](../README.md)
