# 分析结果导出与 Agent 优化决策支持

## 一、需求概述

在现有分析能力（无用类/资源、代码重复、资源重复、Pods 依赖等）基础上，增加**分析结果导出**能力，并支持将导出结果**传给 Agent（如 Cursor/Claude）**，由 Agent 基于结构化数据给出「应优先执行哪部分优化、ROI 最高」的决策建议，便于用户或后续自动化按优先级落地减包。

| 目标 | 说明 |
|------|------|
| **分析结果可导出** | 将当前选中/某次分析结果导出为结构化 JSON，便于存档、对比、或作为 Agent 输入。 |
| **可传给 Agent 做决策** | 用户可将导出内容（或复制摘要）提供给 Cursor 等 Agent，并配合固定 prompt 模板，获得「优化优先级 + ROI 理由」的建议。 |
| **ROI 导向建议** | Agent 输出应包含：优化类型、预估收益（体积/风险）、建议执行顺序，便于优先做高 ROI 项。 |

---

## 二、详细需求点

### 2.1 导出能力

- **导出内容**：单次分析项目（`AnalysisProject`）的完整可序列化结果，包括：
  - 项目元数据：名称、分析时间、工程路径、IPA/Linkmap 路径（可脱敏）、总体积、代码/资源/框架占比。
  - 汇总指标：总大小、无用代码体积、无用资源体积、无用类数量、无用资源数量。
  - 无用类/无用资源列表：路径、类型、大小、来源（静态分析/外部数据/Mach-O 等）。
  - 代码重复组：组数、每组份数、路径列表、相似度（若已开启代码重复扫描）。
  - 资源重复组：组数、每组份数、路径列表、总大小（若已开启资源重复扫描）。
  - Pods 依赖列表：名称、版本、预估体积（若已开启 Pods 依赖扫描）。
- **导出格式**：JSON，字段命名清晰、类型明确，便于 Agent 与脚本解析；可选提供 JSON Schema 文档。
- **导出入口**：
  - 分析 TAB：当存在「当前分析结果」时，工具栏或结果区提供「导出分析结果」按钮。
  - 历史 TAB：在单条历史记录上提供「导出」操作（右键或行内按钮）。
- **导出动作**：弹出保存面板选择路径，默认文件名如 `分析结果-{项目名}-{日期}.json`；可选提供「复制到剪贴板（供 Agent 使用）」并附带一段简短说明或 prompt 提示。

### 2.2 传给 Agent 的方式

- **方式 A：复制 JSON + 手动粘贴**  
  用户导出或复制 JSON 后，在 Cursor 等对话中粘贴，并配合下方推荐 prompt 使用。

- **方式 B：导出为文件 + 在 Agent 中引用**  
  用户将结果导出为文件（如 `analysis-result.json`），在对话中通过 @ 引用该文件或说明路径，由 Agent 读取后分析。

- **方式 C：固定 prompt 模板**  
  App 内或文档中提供一段「推荐 prompt」模板，用户复制后与导出内容一起发给 Agent，即可得到结构化建议（见 2.4）。

### 2.3 Agent 输入约定

- **完整版**：上述导出 JSON 全量内容，适合需要细粒度理由的场景。
- **摘要版（可选）**：仅包含汇总指标 + 各类数量/体积汇总，不含逐条路径，体积更小、适合快速决策；可在导出时提供「仅导出摘要」选项。

### 2.4 Agent 输出期望

Agent 在收到「分析结果 + 推荐 prompt」后，应输出类似结构化的建议（自然语言或 Markdown 列表均可）：

- **优化类型**：如「无用资源清理」「无用代码清理」「代码重复合并」「资源去重」「Pods 瘦身/替换」等。
- **优先级**：按 ROI（收益/成本、风险）从高到低排序。
- **预估收益**：体积减少量或占比（可引用 JSON 中的数值）。
- **风险与注意点**：低/中/高，及简要原因（如需人工复核、可能影响功能）。
- **建议执行顺序**：第一步、第二步… 及每步对应的优化类型与目标。

便于用户或后续自动化按顺序执行（如先清无用资源、再清无用代码、再处理重复）。

### 2.5 其他细节

- **脱敏**：导出时可选项「脱敏路径」（将工程根路径、用户名等替换为占位符），避免敏感信息外泄。
- **版本与兼容**：导出 JSON 中包含 `exportVersion` 或 `schemaVersion`，便于后续格式演进与解析兼容。
- **与现有导出一致性**：当前已有「可视化 TAB → 导出 JSON」（Treemap 树结构）；本需求侧重「分析结果」导出，可与 Treemap 导出并存，或后续在「导出」入口中统一为「分析结果 / 可视化树」两种格式选项。

---

## 三、技术方案

### 3.1 导出数据模型（与现有 DataModels 对齐）

在 `DataModels.swift` 或新建 `AnalysisExportModels.swift` 中定义可编码的导出 DTO，与 Core Data / 现有模型解耦，仅包含需要对外暴露的字段。

**建议结构示例**（具体字段名与嵌套可按实现微调）：

```swift
/// 分析结果导出根结构
struct AnalysisExportPayload: Encodable {
    let exportVersion: Int
    let exportedAt: String
    let project: ProjectExportSummary
    let summary: SummaryExport
    let unusedCode: [UnusedItemExport]
    let unusedResources: [UnusedItemExport]
    let duplicateCodeGroups: [DuplicateCodeGroup]
    let duplicateResourceGroups: [DuplicateResourceGroup]
    let podsDependency: PodsDependencyResult?
}

struct ProjectExportSummary: Encodable {
    let name: String
    let projectPath: String?
    let ipaPath: String?
    let linkmapPath: String?
    let createdAt: String
    let updatedAt: String
}

struct SummaryExport: Encodable {
    let totalSize: Int64
    let codeSize: Int64
    let resourceSize: Int64
    let frameworkSize: Int64
    let unusedCodeSize: Int64
    let unusedResourceSize: Int64
    let unusedCodeCount: Int
    let unusedResourceCount: Int
}

struct UnusedItemExport: Encodable {
    let relativePath: String
    let fileName: String
    let fileType: String
    let codeSize: Int64
    let resourceSize: Int64
    let isUnusedCode: Bool
    let isUnusedResource: Bool
}
```

- `DuplicateCodeGroup`、`DuplicateResourceGroup`、`PodsDependencyResult` 已为 Codable，可直接复用或做一层薄封装（如仅暴露必要字段）。
- 日期统一为 ISO8601 字符串；路径若开启脱敏，则在编码前替换为占位符。

### 3.2 导出服务层

- **职责**：由 `AnalysisProject`（及关联的 `analysisResults`、`duplicateCodeGroups` 等）构建 `AnalysisExportPayload`，并序列化为 JSON `Data`。
- **实现位置**：  
  - 方案 A：在 `AnalysisService` 中新增 `exportAnalysisResult(project: AnalysisProject, options: ExportOptions) -> Data?`。  
  - 方案 B：新建 `AnalysisExportService`，依赖 Core Data 与 DataModels，仅负责「构建 DTO + 编码」，由调用方写文件或写剪贴板。
- **ExportOptions**：可包含 `maskSensitivePaths: Bool`、`summaryOnly: Bool`（仅导出汇总与数量，不导出逐条列表），便于后续扩展。

### 3.3 UI 与交互

- **分析 TAB**  
  - 当 `viewModel.currentProject != nil` 时，在工具栏或 `AnalysisSummaryView` 区域增加「导出分析结果」按钮。  
  - 点击后：若选择「保存到文件」，弹出 `NSSavePanel`，默认文件名 `分析结果-{项目名}-{日期}.json`，将 `AnalysisExportService`/`AnalysisService` 返回的 `Data` 写入；若选择「复制供 Agent 使用」，则写入剪贴板，并可选弹出 Toast 提示「已复制，可粘贴到 Cursor 并附上推荐 prompt」。
- **历史 TAB**  
  - 在每条历史记录行上增加「导出」按钮或右键菜单「导出分析结果」；参数为该条对应的 `AnalysisProject`，逻辑与上一致。
- **可选**：导出前弹出小面板，勾选「脱敏路径」「仅导出摘要」，再执行导出/复制。

### 3.4 Agent 侧：推荐 Prompt 与文档

- **推荐 prompt 模板**（可放在 App 内「帮助」或 doc 下，供用户复制）：

```text
请根据下方「iOS App 分析结果」JSON，给出包体积优化建议：
1. 按 ROI（收益高、风险可控、实施成本低）从高到低排序优化项。
2. 优化类型包括：无用资源清理、无用代码清理、代码重复合并、资源去重、Pods 依赖瘦身等。
3. 对每项给出：优化类型、预估体积收益、风险等级（低/中/高）、简要理由、建议执行顺序。

【分析结果】
（此处粘贴导出的 JSON，或说明 JSON 文件路径）
```

- **文档**：在 `doc/FeatureTasks/` 或 `doc/skills/app-thinner-analysis/` 下补充「分析结果导出与 Agent 使用说明」，说明导出入口、JSON 结构简介、如何配合 Cursor 使用、以及 Agent 输出期望（与 2.4 一致）。若已有 AppThinner SKILL，可在 SKILL 中增加「当用户提供分析结果 JSON 时，按上述结构输出优化优先级建议」的指引。

### 3.5 与现有导出的关系

- **Treemap 导出**：当前「可视化 TAB → 导出 JSON」保留不变，导出的是 Treemap 树结构，用于可视化或其它工具消费。
- **本需求导出**：新增「分析结果」导出，面向「给 Agent 或脚本做优化决策」；两者可并存，入口区分即可（如「导出分析结果」vs「导出可视化 JSON」），或统一为「导出」下拉菜单内两个选项。

---

## 四、开发阶段

### 阶段 1：分析结果导出能力

**目标**：用户可将当前或历史某次分析结果导出为结构化 JSON 文件，并可选复制到剪贴板。

**任务清单**

1. **数据层**
   - 定义 `AnalysisExportPayload`、`ProjectExportSummary`、`SummaryExport`、`UnusedItemExport` 等（见 3.1）；与现有 `DuplicateCodeGroup`、`DuplicateResourceGroup`、`PodsDependencyResult` 复用。
   - 在编码前将 `AnalysisResult`、`AnalysisProject` 及可选 `duplicateCodeGroups`/`duplicateResourceGroups`/`podsDependencyResult` 映射为上述 DTO；日期格式化为 ISO8601；若支持脱敏，则对路径字段做替换。

2. **服务层**
   - 实现 `exportAnalysisResult(project: AnalysisProject, options: ExportOptions) -> Data?`（在 `AnalysisService` 或新建 `AnalysisExportService`）。
   - `ExportOptions` 至少包含：`maskSensitivePaths: Bool`、`summaryOnly: Bool`（可选，阶段 1 可先只做全量导出）。

3. **UI**
   - 分析 TAB：在存在 `currentProject` 时增加「导出分析结果」按钮；点击后弹出保存面板，写入 JSON；可选提供「复制到剪贴板」。
   - 历史 TAB：在单条历史上增加「导出」操作，参数为该条 `AnalysisProject`，逻辑同上。

4. **验收**
   - 导出的 JSON 可被标准 JSON 解析器正确解析；包含项目名、时间、汇总体积、无用类/资源数量及列表、代码/资源重复组、Pods 依赖（若已扫描）；在 Cursor 中粘贴该 JSON 并附上推荐 prompt，能获得可读的优化建议（人工验证即可）。

---

### 阶段 2：Agent 提示词模板与文档

**目标**：用户能无歧义地将「导出结果 + 固定 prompt」交给 Agent，并得到 ROI 导向的优化顺序建议。

**任务清单**

1. **推荐 prompt**
   - 在 App 内「帮助 / 使用说明」或关于页中增加「复制推荐 prompt」按钮或文案，内容与 3.4 一致；或导出后弹窗中提供「已复制 JSON，点击复制推荐 prompt」。
   - 在 `doc/` 下新增或更新文档（如 `分析结果导出与Agent使用说明.md`），包含：导出入口、JSON 字段简要说明、推荐 prompt 全文、Agent 输出期望示例。

2. **SKILL / 规则（可选）**
   - 若使用 `doc/skills/app-thinner-analysis/`：在 `reference.md` 或 SKILL 中增加「当用户提供 AppThinner 分析结果 JSON 时，应按照 ROI 排序给出优化类型、预估收益、风险与执行顺序」的指引，便于 Cursor 等 Agent 稳定输出预期格式。

3. **验收**
   - 文档与 prompt 可被用户直接使用；用一份真实导出 JSON + 推荐 prompt 在 Cursor 中跑通，能得到结构化的优化建议（人工抽查）。

---

### 阶段 3（可选）：摘要导出与脱敏

**目标**：支持「仅导出摘要」与「脱敏路径」，满足轻量分享与安全需求。

**任务清单**

1. **ExportOptions 扩展**
   - `summaryOnly: true` 时，仅输出 `project`、`summary` 及各类数量/体积汇总，不输出 `unusedCode`/`unusedResources` 的逐条列表及重复组明细（或仅输出组数/总体积）。
   - `maskSensitivePaths: true` 时，对 `projectPath`、`ipaPath`、`linkmapPath` 及每条 `relativePath` 做占位符替换（如 `/Users/xxx/Project` → `{PROJECT_ROOT}`）。

2. **UI**
   - 导出前弹窗或菜单中勾选「仅导出摘要」「脱敏路径」，再执行导出/复制。

3. **验收**
   - 摘要版 JSON 体积明显小于全量；脱敏后无真实路径泄露。

---

## 五、文件与接口变更摘要

| 变更类型 | 文件/位置 |
|----------|------------|
| 新增模型 | `AnalysisExportPayload`、`ProjectExportSummary`、`SummaryExport`、`UnusedItemExport`、`ExportOptions`（DataModels 或 AnalysisExportModels.swift） |
| 服务 | `AnalysisService.exportAnalysisResult(project:options:)` 或新建 `AnalysisExportService` |
| UI | AnalysisView / 分析结果区：导出按钮；HistoryView / 历史行：导出操作 |
| 文档 | `doc/分析结果导出与Agent使用说明.md`（或合并到现有 doc）；`doc/skills/app-thinner-analysis/reference.md` 补充 Agent 使用说明 |
| 可选 | 导出前选项面板（摘要/脱敏）；帮助页「推荐 prompt」 |

---

## 六、风险与注意点

- **数据量**：单次分析结果可能包含大量 `AnalysisResult` 行，导出 JSON 体积可能较大；提供「仅导出摘要」可缓解，必要时可对列表做数量上限或分页（仅导出前 N 条并在 summary 中注明）。
- **兼容性**：导出格式一旦对外使用，后续新增字段尽量采用可选或默认值，并维护 `exportVersion`，便于 Agent 或脚本做版本判断。
- **脱敏规则**：脱敏需明确规则（如仅替换用户主目录、工程根路径），并在文档中说明，避免用户误以为已脱敏而泄露信息。
- **Agent 输出稳定性**：推荐 prompt 与 SKILL 描述越清晰，Agent 输出越一致；可在文档中提供 1～2 份「期望输出示例」，便于用户对照。

按上述阶段实施，即可实现「分析结果导出 + 传给 Agent 获得 ROI 导向的优化决策建议」的完整链路。
