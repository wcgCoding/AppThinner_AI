# Best Practices

## 概述

本文档提供iOS无用代码扫描器的最佳实践指南，帮助您更有效地使用该工具并保持代码库的高质量。

---

## 扫描策略

### 1. 扫描频率

#### 日常开发
- **快速扫描**: 每次PR前运行
- **增量扫描**: 每日构建时运行
- **完整扫描**: 每周运行一次

```bash
# 快速扫描（适合日常）
./scripts/run_scan.sh --quick

# 完整扫描（适合周末）
./scripts/run_scan.sh --full
```

#### CI/CD集成
```yaml
# Pull Request - 快速扫描
on: pull_request
  scan-mode: quick

# 主分支 - 完整扫描
on:
  push:
    branches: [main]
  scan-mode: full
```

### 2. 扫描时机

#### 最佳时机
- ✅ 新功能开发完成后
- ✅ 代码重构前后
- ✅ 发版前质量检查
- ✅ 大型合并前

#### 避免时机
- ❌ 紧急修复时
- ❌ 代码不稳定时
- ❌ 大规模重构进行中

---

## 配置管理

### 1. 项目特定配置

为不同类型项目创建专用配置:

```bash
configs/
├── default.json          # 默认配置
├── swift.json            # Swift项目
├── objective-c.json      # Objective-C项目
├── hybrid.json           # 混合项目
└── legacy.json           # 遗留项目
```

#### Swift项目配置
```json
{
    "scan_config": {
        "enable_swift_specific": true,
        "swift_version": "5.0"
    },
    "ignore_rules": {
        "ignore_files": [
            "main.swift",
            "AppDelegate.swift",
            "SceneDelegate.swift"
        ]
    },
    "whitelist": {
        "classes": [
            "AppDelegate",
            "SceneDelegate"
        ],
        "methods": [
            "application(_:didFinishLaunchingWithOptions:)",
            "scene(_:willConnectTo:options:)"
        ]
    }
}
```

#### Objective-C项目配置
```json
{
    "scan_config": {
        "enable_objc_specific": true
    },
    "ignore_rules": {
        "ignore_files": [
            "main.m",
            "AppDelegate.h",
            "AppDelegate.m"
        ]
    },
    "whitelist": {
        "classes": [
            "AppDelegate"
        ],
        "methods": [
            "application:didFinishLaunchingWithOptions:",
            "applicationWillTerminate:"
        ]
    }
}
```

### 2. 白名单管理

#### 合理使用白名单
```json
{
    "whitelist": {
        "classes": [
            "AppDelegate",              // 应用入口
            "BaseViewController",        // 基类
            "ThirdPartySDKAdapter"      // SDK适配器
        ],
        "methods": [
            "viewDidLoad",              // 生命周期方法
            "viewWillAppear:",          // 生命周期方法
            "setupUI",                  // 通用方法
            "configureCell:atIndex:"    // IBOutlet相关
        ]
    }
}
```

#### 白名单注释
在配置中添加注释说明白名单原因:

```json
{
    "whitelist": {
        "classes": [
            "LegacyManager",  // 保留用于向后兼容
            "DebugHelper",    // 仅在调试模式使用
            "FutureFeature"   // 计划在v2.0使用
        ]
    },
    "whitelist_notes": {
        "LegacyManager": "v1.x版本兼容性支持，计划v3.0移除",
        "DebugHelper": "调试工具类，Release构建时不编译",
        "FutureFeature": "下个版本功能，保留接口定义"
    }
}
```

### 3. 忽略规则优化

```json
{
    "ignore_rules": {
        "ignore_directories": [
            "Pods",                    // 第三方库
            ".git",                    // 版本控制
            "build",                   // 构建产物
            "DerivedData",             // Xcode缓存
            "Carthage",                // 依赖管理
            ".bundle",                 // Ruby依赖
            "fastlane",                // 自动化脚本
            "docs",                    // 文档目录
            "Scripts",                 // 脚本目录
            "Tools"                    // 工具目录
        ],
        "ignore_files": [
            "*.generated.*",           // 自动生成文件
            "*+CoreDataProperties.*",  // Core Data生成
            "*.xcdatamodeld",          // 数据模型
            "Localizable.strings",     // 本地化文件
            "InfoPlist.strings"        // Info.plist字符串
        ],
        "ignore_patterns": [
            ".*Test.*",                // 测试文件
            ".*Mock.*",                // Mock类
            ".*Stub.*"                 // Stub类
        ]
    }
}
```

---

## 结果分析

### 1. 优先级排序

#### 按影响排序
1. **高优先级**: 大文件(>1MB)
2. **中优先级**: 未使用的类和方法
3. **低优先级**: 小图片资源

#### 实践示例
```python
# 自定义优先级排序
def prioritize_unused_items(results):
    items = []

    # 添加大文件（高优先级）
    for resource in results['unused_resources']:
        if resource['size_bytes'] > 1024 * 1024:  # > 1MB
            items.append({
                'priority': 'high',
                'type': 'large_resource',
                'item': resource
            })

    # 添加无用类（中优先级）
    for cls in results['unused_classes']:
        items.append({
            'priority': 'medium',
            'type': 'unused_class',
            'item': cls
        })

    # 添加小资源（低优先级）
    for resource in results['unused_resources']:
        if resource['size_bytes'] <= 1024 * 1024:
            items.append({
                'priority': 'low',
                'type': 'small_resource',
                'item': resource
            })

    return items
```

### 2. 渐进式清理

#### 阶段1: 清理资源文件
```bash
# 仅扫描资源
./scripts/run_scan.sh --resource-only

# 按大小排序，优先删除大文件
# 手动验证后删除
```

#### 阶段2: 清理明显的无用代码
```bash
# 扫描代码
./scripts/run_scan.sh --code-only

# 从以下开始清理:
# 1. 明确无用的工具类
# 2. 已废弃的功能模块
# 3. 测试代码残留
```

#### 阶段3: 深度清理
```bash
# 完整扫描 + 引用分析
./scripts/run_scan.sh --full

# 清理:
# 1. 孤立的类和方法
# 2. 循环引用
# 3. 过度设计的抽象
```

### 3. 验证策略

#### 删除前验证清单
- [ ] 搜索全局引用（包括字符串形式）
- [ ] 检查动态调用（performSelector, NSClassFromString等）
- [ ] 检查Interface Builder引用
- [ ] 检查脚本和配置文件引用
- [ ] 运行单元测试
- [ ] 运行UI测试
- [ ] 手动回归测试

#### 验证脚本示例
```bash
#!/bin/bash

# 验证类是否真的未使用
CLASS_NAME="$1"

echo "🔍 验证类: $CLASS_NAME"

# 1. 搜索代码引用
echo "检查代码引用..."
grep -r "$CLASS_NAME" --include="*.swift" --include="*.m" --include="*.h" .

# 2. 搜索字符串引用
echo "检查字符串引用..."
grep -r "\"$CLASS_NAME\"" --include="*.swift" --include="*.m" --include="*.h" .

# 3. 搜索XIB/Storyboard引用
echo "检查IB引用..."
find . -name "*.xib" -o -name "*.storyboard" | xargs grep "$CLASS_NAME"

# 4. 搜索配置文件
echo "检查配置文件..."
grep -r "$CLASS_NAME" --include="*.plist" --include="*.json" .

echo "✅ 验证完成"
```

---

## 团队协作

### 1. 代码评审集成

#### PR模板集成
在 `.github/pull_request_template.md` 中添加:

```markdown
## 无用代码检查

- [ ] 已运行无用代码扫描
- [ ] 无新增无用代码
- [ ] 已清理相关无用代码

### 扫描结果
<!-- 粘贴扫描汇总信息 -->
```

#### 代码评审清单
```markdown
### 代码质量检查

- [ ] 代码扫描通过
- [ ] 无用项 < 阈值
- [ ] 白名单合理
- [ ] 配置已更新
```

### 2. 文档规范

#### 记录清理历史
创建 `CLEANUP_LOG.md`:

```markdown
# 无用代码清理日志

## 2024-01-25

### 清理内容
- 删除 `LegacyViewController` 及相关文件
- 清理 `old_icons/` 目录下的32个图片资源
- 移除 `DeprecatedAPI` 相关方法

### 扫描结果
- 清理前: 156个无用项
- 清理后: 89个无用项
- 节省空间: 2.3 MB

### 风险评估
- 风险等级: 低
- 影响范围: 无
- 回滚计划: Git revert

### 测试验证
- [x] 单元测试通过
- [x] UI测试通过
- [x] 回归测试通过
```

### 3. 指标追踪

#### 建立质量指标
```json
{
    "quality_metrics": {
        "target": {
            "unused_items": 50,
            "unused_classes": 10,
            "unused_methods": 30,
            "unused_resources": 10,
            "max_size_mb": 1.0
        },
        "current": {
            "unused_items": 89,
            "unused_classes": 15,
            "unused_methods": 48,
            "unused_resources": 26,
            "total_size_mb": 1.8
        },
        "trend": "improving"
    }
}
```

---

## 性能优化

### 1. 扫描性能

#### 针对大型项目
```json
{
    "performance": {
        "max_concurrent_scans": 8,      // 增加并发数
        "chunk_size": 200,               // 增大批处理大小
        "timeout_seconds": 600,          // 延长超时时间
        "memory_limit_mb": 2048,         // 增加内存限制
        "enable_cache": true,            // 启用缓存
        "cache_dir": "/tmp/scanner_cache"
    }
}
```

#### 增量扫描
```bash
# 仅扫描修改的文件
git diff --name-only HEAD~1 | grep -E "\.(swift|m|h)$" | \
    xargs ./scripts/run_scan.sh --files
```

### 2. 结果处理

#### 缓存扫描结果
```python
import json
import hashlib

def cache_scan_results(project_path, results):
    """缓存扫描结果"""
    cache_key = hashlib.md5(project_path.encode()).hexdigest()
    cache_file = f"/tmp/scan_cache_{cache_key}.json"

    with open(cache_file, 'w') as f:
        json.dump(results, f)

def get_cached_results(project_path, max_age_hours=24):
    """获取缓存结果"""
    import time
    from pathlib import Path

    cache_key = hashlib.md5(project_path.encode()).hexdigest()
    cache_file = Path(f"/tmp/scan_cache_{cache_key}.json")

    if not cache_file.exists():
        return None

    # 检查缓存年龄
    age_hours = (time.time() - cache_file.stat().st_mtime) / 3600
    if age_hours > max_age_hours:
        return None

    with open(cache_file) as f:
        return json.load(f)
```

---

## 安全考虑

### 1. 敏感信息保护

#### 排除敏感目录
```json
{
    "ignore_rules": {
        "ignore_directories": [
            "Secrets",
            "Credentials",
            "PrivateKeys",
            ".env"
        ]
    }
}
```

### 2. 报告访问控制

#### 限制报告访问
```bash
# 设置报告文件权限
chmod 600 unused_scan_results/*.html
chmod 600 unused_scan_results/*.json

# 限制目录访问
chmod 700 unused_scan_results/
```

---

## 常见陷阱

### 1. 假阳性

#### 动态调用的代码
```swift
// 这些代码可能被误报为未使用
class DynamicallyUsedClass {
    // 通过字符串动态创建
    // NSClassFromString("DynamicallyUsedClass")
}

// 解决方案: 加入白名单
{
    "whitelist": {
        "classes": ["DynamicallyUsedClass"]
    }
}
```

#### Interface Builder引用
```swift
// IBOutlet 和 IBAction 可能被误报
@IBOutlet weak var myButton: UIButton!
@IBAction func buttonTapped(_ sender: Any) { }

// 解决方案: 使用特殊标记
{
    "whitelist": {
        "methods": ["buttonTapped:"]
    }
}
```

### 2. 过度清理

#### 保留公共API
```swift
// Framework或SDK的公共接口
public class PublicAPI {
    // 即使内部未使用，也应保留
    public func exportedMethod() { }
}

// 解决方案: 白名单
{
    "whitelist": {
        "classes": ["PublicAPI"]
    }
}
```

---

## 自动化建议

### 1. 定期报告

#### 每周质量报告
```bash
#!/bin/bash
# weekly_quality_report.sh

./scripts/run_scan.sh --full

# 生成趋势报告
python3 <<EOF
import json
from datetime import datetime

# 读取当前结果
with open('unused_scan_results/scan_summary.json') as f:
    current = json.load(f)

# 生成报告
report = f"""
# 本周代码质量报告
生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## 无用代码统计
- 无用类: {current['unused_classes_count']}
- 无用方法: {current['unused_methods_count']}
- 无用资源: {current['unused_resources_count']}
- 总计: {current['total_unused_items']}

## 建议
- 优先清理大型资源文件
- 关注无用类的清理
"""

print(report)

# 发送邮件通知
# send_email(report)
EOF
```

### 2. 自动清理脚本

⚠️ **警告**: 自动删除代码有风险，仅用于资源文件

```bash
#!/bin/bash
# auto_cleanup_resources.sh (谨慎使用!)

echo "⚠️  自动清理无用资源文件"
echo "此操作有风险，建议先备份!"
read -p "继续? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    exit 0
fi

# 扫描资源
./scripts/run_scan.sh --resource-only

# 读取无用资源列表
python3 <<EOF
import json
import os

with open('unused_scan_results/scan_summary.json') as f:
    results = json.load(f)

# 仅删除小于10KB的图片
for resource in results.get('unused_resources', []):
    if resource['type'] == 'image' and resource['size_bytes'] < 10240:
        file_path = resource['file_path']
        if os.path.exists(file_path):
            print(f"删除: {file_path}")
            os.remove(file_path)
EOF

echo "✅ 清理完成"
```

---

## 总结

### 核心原则
1. **渐进式清理**: 分阶段、有计划地清理
2. **充分验证**: 删除前多重验证
3. **文档记录**: 记录清理过程和原因
4. **团队协作**: 代码评审和知识共享
5. **持续监控**: 定期扫描和趋势追踪

### 质量目标
- 保持无用项 < 50个
- 无用资源占用 < 1MB
- 每次PR不引入新的无用代码
- 每月至少清理一次

---

## 更多资源

- [API文档](api.md)
- [集成指南](integration.md)
- [README](../README.md)
