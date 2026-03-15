---
name: app-thinner-analysis
description: iOS 安装包治理与无用代码/资源分析，与 AppThinnerAnalyzer Mac App 共享同一套解析与差集逻辑（LinkMap 解析、Mach-O classlist−classref 无用类、按文件体积与路径回填）。当用户需要分析 IPA/App 体积、查找无用 ObjC 类、解析 LinkMap、做减包评估或与减包技术文档结合分析时使用。
---

# AppThinner 分析逻辑（与 Mac App 复用）

本 Skill 与 **AppThinnerAnalyzer Mac App** 使用同一套分析逻辑与数据约定，便于在 Cursor/Agent 场景下复用结果，并与桌面端交叉校验。

## 何时使用

- 用户进行 **iOS 安装包治理**、**减包评估**、**无用类/无用资源分析**
- 需要解析 **LinkMap** 得到按文件/符号体积
- 需要基于 **Mach-O** 的 classlist − classref 差集得到**候选无用 ObjC 类**
- 与现有减包文档（如 `doc/iOS_JOOX_减包优化技术分享.md`）结合做方案分析或校验

## 核心逻辑（与 Mac App 一致）

1. **无用类**  
   - **定义类**：`__objc_classlist`（多数二进制在 `__DATA_CONST`，少数在 `__DATA`）  
   - **被引用类**：`__objc_classrefs`（`__DATA`），可选叠加 superrefs、category 宿主等  
   - **候选无用类** = 定义类 − 被引用类（再经白名单过滤）  
   - 路径与体积：用 LinkMap 符号表按类名匹配编译单元，取 `estimatedSize` 与项目相对路径

2. **LinkMap**  
   - 解析 Object files + Symbols，得到 `CodeSizeInfo`（relativePath、totalSize、symbols）  
   - 与工程路径映射时需处理 Framework/静态库路径差异（前缀裁剪、文件名/基名匹配）

3. **数据流**  
   - IPA/.app 解析 → 主二进制路径、包内文件列表  
   - 工程扫描 → ProjectFileEntry，用于路径映射  
   - LinkMap 解析 → CodeSizeInfo  
   - 主二进制 + CodeSizeInfo → BinaryUnusedCodeAnalyzer → UnusedCode 列表

## 与 Mac App 的复用方式

- **逻辑复用**：优先通过 **AppThinnerCore + CLI**（若已实现）与 Mac App 共用同一套代码，见 `doc/AppThinner_SKILL_与MacApp逻辑复用方案.md`。  
- **当前可做**：  
  - 使用仓库内 **otool/nm 校验脚本**（若存在 `scripts/otool_unused_class_validator.sh`）对指定 Mach-O 做无用类校验，与 Mac App 的 BinaryUnusedCodeAnalyzer 结果对照。  
  - 按上述「核心逻辑」用脚本或已有工具复现：classlist/classref 差集、LinkMap 解析、路径与体积回填。  
- **输出约定**：与 Mac App 的 `UnusedCode`、`CodeSizeInfo` 等结构对齐，便于后续导入或对比。

## 参考文档

- 方案与实施顺序：`doc/AppThinner_SKILL_与MacApp逻辑复用方案.md`  
- 减包技术分享（含 otool/WBBlades 等方法）：`doc/iOS_JOOX_减包优化技术分享.md`  
- 分析逻辑实现：`AppThinnerAnalyzer/Services/BinaryUnusedCodeAnalyzer.swift`、`LinkmapAnalyzer.swift`、`AnalysisService.buildUnusedContentResults`
