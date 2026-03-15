# AppThinner 解析分析逻辑沉淀为 SKILL 与 Mac App 逻辑复用方案

## 目标

- 将当前「解析 + 分析」逻辑沉淀成 **SKILL**，便于在 Cursor/Agent 场景下复用。
- 与 **Mac App（AppThinnerAnalyzer）** 尽可能复用同一套逻辑，避免两套实现分叉。

## 现状简要

| 层级 | 模块 | 职责 | 依赖 |
|------|------|------|------|
| 数据源解析 | LinkmapAnalyzer | 解析 LinkMap → ObjectFileInfo + SymbolInfo，映射到工程路径 → CodeSizeInfo | 无 |
| 数据源解析 | PackageParser | 解析 IPA/.app → PackageFileInfo、主二进制路径 | 无 |
| 无用类分析 | BinaryUnusedCodeAnalyzer | Mach-O classlist − classref（+ superref/catHost）→ UnusedCode，结合 CodeSizeInfo 填路径/体积 | MachOKit, MachOObjCSection |
| 编排 | AnalysisService | 解析 IPA + 工程扫描 + LinkMap → 构建 CodeSizeInfo；调用 buildUnusedContentResults（无用类以 Mach-O 差集为准，LinkMap 只补 estimatedSize/路径） | 上述 + CoreData/FilePermission 等 |
| 编排 | UnusedScanService | 调用 BinaryUnusedCodeAnalyzer + 资源引用扫描 → UnusedScanResult | BinaryUnusedCodeAnalyzer, CodeSizeInfo |
| 展示/持久化 | ViewModels, CoreData | UI、历史、对比、报告 | App 独有 |

Skill 无法直接执行 Swift 代码，只能通过「文档 + 脚本/CLI」与 Mac App 对齐逻辑。

---

## 方案概览

- **方案 A（推荐）**：**核心逻辑下沉到 Swift Package + CLI，Mac App 与 Skill 共用**
  - 新建 **AppThinnerCore** Swift Package，抽出「与 UI/CoreData/沙盒无关」的解析与算法。
  - Mac App 依赖该 Package，仅保留编排、UI、权限、持久化。
  - 同一仓库内增加 **CLI 产物**（如 `app-thinner analyze`），基于 AppThinnerCore，输入：工程路径、LinkMap 路径、主二进制路径（或 .app 路径）；输出：JSON（无用类列表、按文件体积等）。
  - **SKILL**：描述何时使用（iOS 减包、无用类分析、LinkMap 分析），并指导 Agent 在无 Mac App 时**优先调用该 CLI** 并解析 JSON；有 App 时也可引导用户使用 App。逻辑 100% 与 Mac App 共用（同一 Package）。

- **方案 B**：**仅沉淀方法论 + 脚本，不抽 Package**
  - 不改 Mac App 结构，保持现有单工程。
  - 在仓库内维护与当前逻辑**等价**的脚本（如 otool/nm 无用类校验、LinkMap 解析脚本），并写好文档。
  - **SKILL**：文档化「输入/输出、步骤、注意事项」，Agent 按文档执行脚本（如 `scripts/otool_unused_class_validator.sh`、Python 解析 LinkMap 等）。复用的是「方法论 + 脚本」，与 App 无代码级复用，但实现简单、无需改 App。

- **方案 C**：**混合分阶段**
  - 短期：采用 **方案 B**，先落地 SKILL + 脚本 + 文档，立刻可用。
  - 中期：按 **方案 A** 抽出 AppThinnerCore + CLI，Mac App 迁到依赖 Package，Skill 改为优先调用 CLI，实现最大逻辑复用。

---

## 方案 A 详细设计（最大复用）

### 1. AppThinnerCore 包边界

**纳入 Core 的模块（与 Mac App 复用）：**

- **Models**（仅分析相关、无 CoreData/AppKit）  
  - 如：`LinkmapParseResult`, `ObjectFileInfo`, `SymbolInfo`, `CodeSizeInfo`, `UnusedCode`, `ProjectFileEntry`（或精简版），以及分析过程用到的枚举/错误类型。
- **LinkmapAnalyzer**  
  - `parseLinkmapFile` / `parseLinkmapContentWithObjectFiles`、`mapObjectFilesToProjectStructure`、`LinkmapPathAdapter`、`makeProjectFileIndex`。  
  - 依赖：仅 Foundation；不依赖工程内的 CoreData、FilePermission。
- **BinaryUnusedCodeAnalyzer**  
  - classlist/classref/superref/catHost 差集、白名单、路径与体积从 CodeSizeInfo 回填。  
  - 依赖：Foundation + MachOKit + MachOObjCSection（通过 SPM 引入）。
- **可选**：从 AnalysisService 抽出的「纯函数」  
  - 例如：`buildUnusedContentResults` 中仅依赖 CodeSizeInfo + UnusedCode + 路径解析的这部分，放入 Core，接受「已解析好的」CodeSizeInfo 与 UnusedCode 列表，输出统一的「无用内容」结构（供 App 与 CLI 共用）。

**不纳入 Core（留在 Mac App）：**

- CoreData、FilePermission、UI、ViewModels、DependencyContainer 的 UI 相关部分、报告/历史/对比的持久化与展示。

### 2. Mac App 改造

- AppThinnerAnalyzer 工程**依赖** `AppThinnerCore`（本地 path 或 同 repo 子目录）。
- `AnalysisService` / `UnusedScanService` 改为调用 Core 的 API（传入路径、CodeSizeInfo 等），拿到结果后再做 CoreData 持久化、UI 展示、权限与错误提示。
- 业务逻辑（尤其无用类差集、LinkMap 映射）只保留在 Core 中，App 不再重复实现。

### 3. CLI 设计（供 Skill 调用）

- **位置**：与 App 同 repo，例如 `AppThinnerCLI/` 或 `Sources/AppThinnerCLI/` 在 AppThinnerCore 的 Package 中作为 executable target。
- **命令示例**：  
  `app-thinner analyze --project /path/to/project --linkmap /path/to/LinkMap --binary /path/to/App.app/MyApp`  
  或：`--app /path/to/App.app`（内部解析主二进制路径）。
- **输出**：JSON，包含但不限于：  
  - 无用类列表（类名、filePath、estimatedSize、detectionMethod 等，与 `UnusedCode` 对齐）；  
  - 可选：按文件/目录的 CodeSize 汇总（与当前 TreeMap 数据源一致）。  
- **输入**：  
  - 工程路径（用于 ProjectFileEntry/路径映射）；  
  - LinkMap 路径；  
  - 主二进制路径或 .app 路径。  
- CLI 只做「解析 + 分析」，不写数据库、不弹窗；可读 stdin/环境变量做简单配置（如白名单文件路径）。

### 4. SKILL 与 Mac App 的复用关系

- **逻辑复用**：Mac App 与 CLI 都依赖 AppThinnerCore → 同一套 LinkMap 解析、同一套 classlist−classref 差集与白名单、同一套路径/体积回填。
- **Skill 行为**：  
  - **When**：用户进行 iOS 安装包治理、无用类分析、LinkMap 分析、减包评估、与现有文档（如 JOOX 减包分享）结合分析时，触发该 Skill。  
  - **How**：  
    - 若本机有 CLI：优先 `app-thinner analyze ...`，解析 stdout JSON，再基于结果做报告/建议/代码级建议。  
    - 若无 CLI：按 SKILL 内「等价脚本 + 步骤」执行（otool/nm 无用类、脚本化 LinkMap 解析），并说明与 Mac App/CLI 结果一致。  
  - **与 Mac App 的关系**：Skill 文档中明确「与 AppThinnerAnalyzer Mac App 使用同一套分析逻辑（AppThinnerCore）」，避免用户混淆两套标准。

---

## 方案 B 详细设计（仅脚本 + 文档复用）

- 不新增 Swift Package，不拆 Mac App。
- 在仓库中固化与当前逻辑**等价**的流程：
  1. **无用类**：  
     - 使用 `scripts/otool_unused_class_validator.sh`（或同类脚本）：  
       - `otool -v -s __DATA __objc_classrefs`、`otool -v -s __DATA_CONST __objc_classlist`（或 __DATA），差集后 `nm -nma` 解析类名。  
     - 与 BinaryUnusedCodeAnalyzer 的「classlist − classref」思路一致，便于交叉验证。
  2. **LinkMap**：  
     - 提供 Python/Shell 解析脚本或明确格式说明，输出「按编译单元/按文件的 size + 符号列表」，与当前 `CodeSizeInfo` 可对照。
  2. **路径与体积**：  
     - 文档约定：如何从 LinkMap 符号中按类名匹配到文件、如何算 estimatedSize，与 `buildCodeSizeByClassFromSymbols` 等逻辑一致。
- **SKILL**：  
  - 描述上述步骤、输入输出、示例命令；  
  - Agent 在无 Mac App/CLI 时按此执行脚本并解释结果；  
  - 注明「与 AppThinnerAnalyzer 桌面端方法论一致，可互相校验」。

---

## 建议实施顺序

1. **先做方案 B（低成本）**  
   - 在 repo 内完善 `scripts/otool_unused_class_validator.sh`（及文档）。  
   - 新增 **AppThinner 分析 SKILL**：本仓库已提供 Skill 骨架在 **`doc/skills/app-thinner-analysis/`**（含 `SKILL.md`、`reference.md`），可将该目录复制到 **`.cursor/skills/app-thinner-analysis/`** 作为项目 Skill 使用；内容包含触发条件、与 Mac App 一致的核心逻辑、方案 B 的步骤及参考文档链接。
2. **再推进方案 A（高复用）**  
   - 新建 `AppThinnerCore` Swift Package，迁入 LinkmapAnalyzer、BinaryUnusedCodeAnalyzer、必要 Model。  
   - Mac App 改为依赖 Core，删除重复实现。  
   - 增加 CLI target，输出 JSON。  
   - 更新 SKILL：优先调用 CLI，并注明「与 Mac App 共用 AppThinnerCore」。

这样既能尽快把「解析分析逻辑」沉淀为 SKILL 可用，又能在后续与 Mac App 实现最大逻辑复用。
