---
name: ios_package_optimization_report
description: 基于 AppThinner 导出的 JSON 分析结果，生成标准化的 iOS 安装包优化 HTML 报告（含体积分布、无用代码与资源、Pods 依赖优化建议）。
---

# iOS 安装包优化分析 SKILL

专门用于阅读 **AppThinner AI 报告 JSON 文件**，并生成一份 **HTML 形式**、符合业务内规范的安装包优化分析报告。

> ✅ 输入：本地文件路径（由 AppThinner「导出 AI 报告数据」生成的 JSON 文件）  
> ✅ 输出：一段完整的 `<html>...</html>` 字符串，可直接保存为 HTML 或粘贴到文档系统中展示。

---

## 一、输入约定

### 1. 输入形式

- Skill 的**主要输入**是：**本地文件路径字符串**，例如：
  - `/Users/xxx/Downloads/ai-optimization-report-MyApp.json`
  - 或项目内的相对路径（由上层调用方转换为绝对路径）
- 调用时不要直接粘贴 JSON 内容，而是提供「已经导出的 JSON 文件路径」。

#### 可选输入：执行模式（mode）

为统一行为，建议上层调用在对话或配置中约定一个**执行模式**（非必填，缺省视为 `"report+execute"`）：

- `mode: "report"`  
  - 仅生成 **HTML 报告**，不生成任何「执行任务清单」。
- `mode: "report+execute"`（**默认推荐**）  
  - 在生成 HTML 报告的同时，额外生成一份**瘦身执行任务清单**（例如 Markdown / 结构化 JSON），包含任务类型、改动范围、预估体积等信息，便于人工 review 与后续落地。

> **重要说明：**
> - 即便在 `mode: "report+execute"` 下，本 SKILL **只生成任务清单，不直接对工程代码或文件系统做任何改动**。
> - 「execute」的语义是：**整理并输出三类任务：① 明确的无用资源/无用代码删除候选；② 尝试下架的 Pods 库候选；③ 业务场景下架（目前只给建议，TODO）。具体删除/修改动作需要用户或后续工具在阅读清单后显式确认并执行。**

#### 可选输入：拟下架业务（businessToSunset）

- 若在分析前已确定拟下架的业务模块（如直播、歌房、录唱、短视频），可**额外提供**拟下架业务配置，报告中将自动增加「拟下架业务与可清理范围」章节。
- 配置形式示例（由调用方在对话或上下文中给出）：
  - 业务名称列表：`["直播", "歌房", "录唱", "短视频"]`
  - 或带关键词映射：`{ "直播": ["LiveVideo", "NewLive", "IMLive"], "歌房": ["KTV", "WSKTVRoom", "RoomModule"], "录唱": ["KSong", "Buzz", "Reconmend", "WeSing"], "短视频": ["ShortVideo", "TAVEffectKit", "TAVKit"] }`
- 若未提供，则报告不包含该章节；若只提供业务名列表，则使用下方「业务名 → 路径关键词」默认映射表进行匹配。

### 2. 文件内容规范

文件内容应当是由 AppThinner 中「Treemap 可视化 → 导出 AI 报告数据」功能生成的 JSON。导出前会做**压缩**（minify），即无换行、无多余空格的单行 JSON，解析时按标准 JSON 处理即可。

**最新导出规则（与 AppThinner AIExportService 一致）**：

| 区块 | 规则 |
|------|------|
| **sizeDistribution** | 最多只导出到**第 5 层**（Root 为第 1 层），不展开到叶子/符号；第 5 层节点的 `children` 为空数组。 |
| **unusedCode** | 仅导出按 **codeSizeBytes 降序**的 **Top 500** 条，用于控制 Token 与文件体积。 |
| **unusedResources** | 仅导出按 **resourceSizeBytes 降序**的 **Top 500** 条。 |
| **podsDependencies** | **mainLibSummary** 与 **tree** 均**完整导出**，不做截断。 |

顶层结构形如（字段简化示例）：

```jsonc
{
  "version": "1.0",
  "exportedAt": "2026-03-11T12:34:56Z",
  "instructionsForAI": "String",
  "project": {
    "name": "String",
    "projectPath": "String",
    "ipaPath": "String",
    "linkmapPath": "String",
    "totalSizeBytes": 0,
    "totalSizeKB": 0.0,
    "codeSizeKB": 0.0,
    "resourceSizeKB": 0.0,
    "frameworkSizeKB": 0.0,
    "potentialSavingsBytes": 0,
    "potentialSavingsKB": 0.0
  },
  "sizeDistribution": {
    "name": "Root",
    "relativePath": "",
    "totalSizeBytes": 0,
    "codeSizeBytes": 0,
    "resourceSizeBytes": 0,
    "frameworkSizeBytes": 0,
    "unusedSizeBytes": 0,
    "unusedRatio": 0.0,
    "children": [
      /* 递归同结构，最多 5 层；第 5 层 children 为 [] */
    ]
  },
  "unusedCode": [
    { "relativePath": "String", "fileName": "String", "codeSizeBytes": 0, "codeSizeKB": 0.0 }
  ],
  "unusedResources": [
    { "relativePath": "String", "fileName": "String", "resourceSizeBytes": 0, "resourceSizeKB": 0.0 }
  ],
  "totalUnusedCodeCount": 0,
  "totalUnusedResourcesCount": 0,
  "podsDependencies": {
    "podfileLockPath": "Podfile.lock",
    "mainLibSummary": [
      { "name": "AFNetworking", "version": "4.0.1", "sizeBytes": 0, "sizeKB": 0.0, "unusedSizeBytes": 0, "unusedSizeKB": 0.0, "unusedRatio": 0.0, "dependedByCount": 0, "dependedByList": ["MainApp"] }
    ],
    "tree": [ /* PodsDependencyInfo 数组，完整依赖树 */ ]
  }
}
```

- **totalUnusedCodeCount** / **totalUnusedResourcesCount**：全量无用代码/资源条数。若大于 `unusedCode.length` / `unusedResources.length`，表示已按体积截断，报告中应注明「共 N 条，此处仅展示体积 Top 500」。

### 3. 输入校验要求

Skill 应在读取文件后进行以下校验：

1. 路径是否存在、是否为普通文件；不存在时返回明确错误提示，不继续解析。
2. 是否能够成功解析为 JSON；**导出的 JSON 可能为压缩单行**，解析逻辑与美化 JSON 一致；失败时返回「不是合法 JSON」的错误说明。
3. 顶层是否包含以下关键字段：
   - `version`（期望 `"1.0"`，其他版本需要在报告中标注兼容性提示）
   - `project`
   - `sizeDistribution`
4. 如 `unusedCode` / `unusedResources` / `podsDependencies` 缺失或为空，应被视为「该能力未开启或无结果」，不能简单当作 0。
5. 若存在 **totalUnusedCodeCount** / **totalUnusedResourcesCount** 且大于对应数组长度，表示无用代码/资源已按体积截断为 Top 500，报告中应在「无用代码与无用资源」章节明确写出「共 N 条无用代码，此处仅展示体积 Top 500」（资源同理），避免读者误以为仅有 500 条。

在发现数据明显异常时（例如 `totalSizeBytes` 极小、`sizeDistribution.children` 为空），需要在最终 HTML 报告的「风险提示」章节中明确指出「输入数据可能不完整或未开启相应分析」，避免误导。

---

## 二、输出约定（HTML 报告）

### 1. 输出形式

- Skill 的基础输出仍然是**完整的 HTML 文本**，以：
  - `<!DOCTYPE html>` 开头
  - `<html>...</html>` 结尾
- 建议仅内嵌少量 CSS（放在 `<style>` 标签中），不依赖外部资源，便于直接在浏览器或 Confluence / 飞书文档中渲染。
- 所有内容使用 **中文**。

#### 1.1 直接写入 HTML 文件（与 JSON 同级目录）

- 在返回 HTML 字符串的**同时**，Skill 应尽量将报告写入一个实际文件，方便用户直接双击打开：
  - 若输入路径为：`/path/to/ai-optimization-report-xxx.json`
  - 则推荐写入：`/path/to/ai-optimization-report-xxx.html`
- 写入失败（例如权限受限、路径只读等）时：
  - 不能影响 HTML 字符串的正常返回；
  - 可在 HTML 顶部或结尾附带一行「文件写入失败」的提示文案，但不要中断主流程。

### 2. 页面结构（建议模板）

HTML 结构建议如下（可以在实现时按此骨架组织）：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <title>iOS 安装包优化分析报告 - {{project.name}}</title>
  <style>
    /* 轻量、适合内网报告的样式，注意暗/亮配色兼容性 */
  </style>
</head>
<body>
  <h1>iOS 安装包优化分析报告 - {{project.name}}</h1>
  <p>报告生成时间：{{exportedAt}}</p>

  <h2>一、总体概览</h2>
  <!-- 项目路径、总体积、Code/Resource/Framework 占比、可节约空间等 -->

  <h2>二、体积分布与热点模块</h2>
  <!-- 基于 sizeDistribution，列出 Top N 目录及体积构成、无用占比 -->

  <h2>三、无用代码与无用资源清理建议</h2>
  <!-- 按业务目录聚合 unusedCode / unusedResources，生成分组表格 + checklist -->

  <!-- 可选：当提供 businessToSunset 时插入 -->
  <h2>拟下架业务与可清理范围</h2>
  <!-- 按路径关键词匹配，汇总每类业务的无用代码条数/体积、无用资源条数/体积及建议 -->

  <h2>四、Pods 库依赖优化建议</h2>
  <!-- 基于 podsDependencies.mainLibSummary，分析体积大户、高无用占比 Pods 及被依赖情况 -->

  <h2>五、优化路线与优先级规划</h2>
  <!-- 按 P0/P1/P2 划分行动项，列表化展示 -->

  <h2>六、风险提示与验证建议</h2>
  <!-- 运行时反射、动态加载、A/B 实验等风险说明及验证策略 -->
</body>
</html>
```

#### 2.1 固化 HTML 报告模板（建议）

- 为保证不同项目、不同时间的报告风格一致，已经在当前仓库中提供了一份**固定 HTML 模板**：
  - 路径：`.claude/skills/ios-package-optimization/assets/report-template.html`
  - 风格：暗色背景 + 总览卡片 + 分节结构 + 表格 + checklist，与内部评审场景适配。
- 模板中各位置通过占位符预留数据注入点，示例：
  - 顶部项目信息：`{{project.name}}`、`{{project.projectPath}}`、`{{project.ipaPath}}`、`{{project.linkmapPath}}`；
  - 总览数字：`{{summary.totalSizeKB}}`、`{{summary.codeSizeKB}}`、`{{summary.resourceSizeKB}}`、`{{summary.frameworkSizeKB}}`、`{{summary.potentialSavingsKB}}` 以及对应的 `*Human`（带 MB 文案）字段；
  - 各章节文案与表格：`{{section1.overviewParagraph}}`、`{{section2.columnsHTML}}`、`{{section3.checklistHTML}}`、`{{section4.tableHTML}}`、`{{section5.tableHTML}}`、`{{section6.itemsHTML}}` 等。
- Skill 的推荐实现方式：
  1. 读取 `report-template.html` 为字符串；
  2. 先基于 JSON 计算出 `project` / `summary` / `sectionN` 所需的所有字段；
  3. 按占位符做字符串替换后，返回最终 HTML 文本并尝试写入与 JSON 同级目录的 `*.html` 文件。
- 如模板文件因路径或权限原因无法读取：
  - 可以在 Skill 内部回退到内置的模板常量字符串（保持结构与 `report-template.html` 一致）；
  - 或简化为原来的骨架结构，但应在报告中标注「当前为降级版报告布局」以便用户识别。

### 3. 内容风格要求

- **结构清晰**：使用 `<h1> ~ <h3>` 组织章节，列表使用 `<ul>/<ol>`。
- **可执行**：对每个主要建议给出：
  - 涉及模块/目录/Pods 名称；
  - 预估收益（KB/MB，保留 1–2 位小数）；
  - 建议执行步骤（例如「清理 → 编译 → 回归 → 上灰度 → 观察指标」）；
  - 需要协同的角色（客户端、服务端、产品、QA 等）。
- **谨慎用词**：避免使用「直接删」「一定安全」等绝对性措辞，统一使用「建议清理」「在充分验证后可以移除」等表述。

---

## 三、分析逻辑（建议实现思路）

与当前导出规则对应：**sizeDistribution** 已最多 5 层、**unusedCode** / **unusedResources** 已为体积 Top 500、**podsDependencies** 为完整导出。生成报告时按上述范围解读即可，并在存在截断时注明总条数。

### 1. 体积分布分析（sizeDistribution）

- 导出规则下 **sizeDistribution 已最多 5 层**，不再展开到叶子/符号；直接遍历现有树即可，无需再做深度截断。
- 从 `sizeDistribution.children` 中选取 **Top N 业务目录**（例如 5–10 个，按 `totalSizeBytes` 降序）；若某层 `children` 已按体积排序则可直接取前 N 个。
- 对每个目录输出：
  - `relativePath`（例如 `Modules/Pay`, `Features/Live`, `Pods/AFNetworking`）
  - 总体积及 Code / Resource / Framework 构成占比；
  - `unusedRatio`（如 > 0 时标红或加醒目标记）。
- 在报告中用自然语言小结：
  - 指出「体积大户」模块；
  - 指出「无用占比较高」的目录，作为优先治理对象。

### 2. 无用代码与资源（unusedCode / unusedResources）

- **截断说明**：导出规则下 **unusedCode** / **unusedResources** 仅包含按体积排序的 **Top 500**。若存在 **totalUnusedCodeCount** / **totalUnusedResourcesCount** 且大于 500，在报告中该章节开头明确写出：「共 N 条无用代码，此处仅展示体积 Top 500」/「共 M 条无用资源，此处仅展示体积 Top 500」，避免误导。
- 按 `relativePath` 的上层目录（如前两级路径）对**当前数组内**无用项进行聚合：
  - 例如：`Modules/Pay/XXX.swift` → 归到 `Modules/Pay`；
  - `Resources/Images/xxx.png` → 归到 `Resources/Images`。
- 对每个目录统计：
  - 无用代码文件数与总 codeSize；
  - 无用资源文件数与总 resourceSize。
- 输出：
  - 汇总表格（每行一个目录，附上无用项总数与体积）；
  - 关键目录的 checklist 行动项（P0/P1/P2）。

#### 2.1 IDE 集成：导出无用项 CSV 按钮（推荐）

- 为方便研发同学在 IDE / GUI 中接收清单，建议在 AppThinner 的 Treemap 可视化界面中提供一个显式按钮，例如：
  - 按钮文案：`导出无用代码 & 资源 CSV`
  - 触发行为：将当前分析项目的 `unusedCode` 与 `unusedResources` 聚合为一个或两个 CSV 文件并弹出保存面板。
- CSV 推荐字段（可按实际需要增减）：
  - `type`：`code` / `resource`
  - `relativePath`：工程相对路径（与 AppThinner Treemap 一致）
  - `fileName`：文件名
  - `sizeBytes` / `sizeKB`：文件体积
  - `unusedSource`：无用来源（如「二进制分析」「正则扫描」等，可选）
- Skill 在生成 HTML 报告时，可以在「无用代码与无用资源清理建议」章节中明确提示：
  - 如「建议搭配 AppThinner 中的『导出无用代码 & 资源 CSV』功能，获取完整清单并导入 Excel / BI 工具做进一步筛选与跟踪」。

### 3. 拟下架业务与路径关键词匹配（可选）

当调用方提供了 **拟下架业务**（businessToSunset）时：

- **匹配规则**：
  - **无用代码/无用资源**：对 JSON 中 `unusedCode[].relativePath`、`unusedResources[].relativePath` 做**不区分大小写**的子串匹配；若路径中包含该业务任一关键词，则将该条计入该业务（用于表格中的「无用代码」「无用资源」列，仅统计导出 Top 500）。
  - **路径是否 Pods**：`relativePath` 以 `Pods/` 开头或包含 `/Pods/` 视为 Pods 三方库，否则视为端上源码。
  - **可节约（约）**：仅统计**端上源码**（排除 Pods）。从 **sizeDistribution** 树递归遍历：若某节点 `relativePath` 包含该业务任一关键词且**非 Pods 路径**，则计入该节点的 `totalSizeBytes`，且不再递归其子节点；否则递归子节点。**疑似关联 Pods**：同上逻辑但仅统计 **Pods 路径**，放入展开明细供参考（评估依赖下线时的额外收益）。
- **业务名 → 路径关键词**默认映射表（可根据工程实际目录调整）：

| 业务名 | 路径关键词（任一词匹配即计入） |
|--------|--------------------------------|
| 直播   | LiveVideo, NewLive, IMLive     |
| 歌房   | KTV, WSKTVRoom, RoomModule     |
| 录唱   | KSong, Buzz, Reconmend, WeSing |
| 短视频 | ShortVideo, TAVEffectKit, TAVKit |

- **统计输出**：对每个业务汇总：
  - 无用代码：条数、总 codeSizeBytes（或 KB/MB），来自 unusedCode 按关键词匹配；
  - 无用资源：条数、总 resourceSizeBytes（或 KB/MB），来自 unusedResources 按关键词匹配；
  - **可节约（约）**：该业务路径关键词在 sizeDistribution 中匹配到的**端上源码目录总体积**（排除 Pods）；
  - **展开明细**：按关键词列出「端上源码」与「疑似关联 Pods（供参考）」两列，并给出端上合计与 Pods 合计；
  - 建议：一句简短落地建议（可提及端上移除与 Pods 评估下线）。
- 报告中该章节需注明：可节约仅统计端上源码（排除 Pods）；Pods 内匹配关键字的目录体积见展开明细，供评估依赖下线时参考。

### 4. Pods 依赖优化（podsDependencies）

当 `podsDependencies` 存在时：

- 基于 `mainLibSummary`：
  - 找出体积较大的 Pods（sizeKB 高）；
  - 找出 `unusedRatio` 较高的 Pods；
  - 结合 `dependedByCount`、`dependedByList` 识别「只被少量边缘模块依赖」的库。
- 报告中给出：
  - 可考虑下线/替换的 Pods 列表；
  - 建议治理方式：例如按子模块拆分、替换为更轻量实现、与业务确认后下线等。

### 5. 优先级与路线图

- 将所有建议拆分为：
  - **P0：短期可落地（1–2 个版本内）**；
  - **P1：需跨团队评审后执行**；
  - **P2：中长期结构性治理（架构/资源体系重构）**。
- 对每个优先级内的条目，生成包含：
  - 模块/目录/Pods 名称；
  - 操作步骤；
  - 预估收益；
  - 风险点与验证策略。

---

### 6. 执行任务清单（execute 模式，仅生成计划，不直接改代码）

当上层调用方以 `mode: "report+execute"` 调用本 SKILL 时，除了 HTML 报告外，还应额外生成一份「安装包瘦身执行任务清单」，用于**人工确认后再实施**。  
本清单仅基于 JSON + 约定规则给出建议，**不对工程做任何改动**。任务分为三类：

#### 6.1 类别一：明确的无用资源 / 无用代码删除

来源：`unusedResources` / `unusedCode`，结合规则筛选出「可以直接考虑删除」的候选项。

- **筛选规则（建议）**
  - 资源：
    - 来自 `unusedResources`；
    - 可排除明显公共目录（例如某些全局 Assets 目录，可按项目需要配置白名单）；
    - 可按 `resourceSizeBytes` 设定最小阈值（避免为几 KB 的资源生成过多任务）。
  - 代码：
    - 来自 `unusedCode`；
    - 可排除高风险目录（如运行时注入框架、反射较多模块）；具体可按路径前缀维护黑/白名单。
- **任务内容示例（每条）**
  - `type`: `"delete_unused_resource"` / `"delete_unused_code"`
  - `path`: `relativePath`（工程相对路径）
  - `sizeKB`: 体积（KB）
  - `reason`: `"标记为 unusedResources / unusedCode，静态分析未发现引用"`
  - `suggestedAction`: 文本建议（例如「建议先从 Target / 工程引用中移除，如无异常再物理删除文件」）
- **执行形态**
  - 本 SKILL **只输出任务清单**（例如 Markdown 或 JSON 数组），不实际移动 / 删除文件。
  - 后续由人工或其他工具根据清单逐条确认并执行。

#### 6.2 类别二：尝试下架某一个 Pods 库（试探性建议）

来源：`podsDependencies.mainLibSummary` + `podsDependencies.tree` +（可选）业务关键字匹配结果。

- **候选 Pods 选择建议**
  - 体积较大：`sizeKB` 较高；
  - 无用占比较高：`unusedRatio` 高；
  - 依赖关系较「边缘」：`dependedByCount` 小，或者只被拟下架业务模块依赖；
  - 可结合「拟下架业务」分析中的「疑似关联 Pods」列表，优先推荐只被某业务使用的库。
- **任务内容示例（每条）**
  - `type`: `"try_remove_pod"`
  - `podName`: 例如 `"KSongKit"`
  - `sizeKB`: 该 Pod 体积；
  - `unusedRatio`: 无用占比；
  - `dependedBy`: 依赖该 Pod 的上层模块列表（来自 `dependedByList`）；
  - `relatedBusinessModules`（可选）：与之高度相关的业务（如「录唱」）。
  - `suggestedAction`: 文本建议（例如「建议在独立分支中尝试从 Podfile 移除该库，并对相关功能做完整回归」）。
- **执行形态**
  - 本 SKILL 不自动修改 Podfile / 执行 `pod install`，只在任务清单中给出「可尝试下架的 Pods」候选及影响面提示。

#### 6.3 类别三：尝试下架某一个业务场景（TODO 预留）

来源：业务模块定义（如「直播」「歌房」「录唱」「短视频」）+ `sizeDistribution` + `unusedCode` / `unusedResources` + 「拟下架业务与可清理范围」章节中的分析结果。

- **当前版本定位**
  - 当前版本仅在 HTML 报告中提供「拟下架业务」的体积评估和路径关键词分布；
  - 执行任务清单中可以给出**高层级的业务下架建议**（例如「录唱业务可节约端上约 22.8 MB，Pods 约 90.7 MB，建议先关闭入口再分批下线内部模块」），暂不自动展开到具体代码改动。
- **后续规划（可在后续版本实现）**
  - 为每个业务模块生成：
    - 入口路由 / Tab / 按钮所在文件的大致位置信息；
    - 主要功能模块目录（如 `Modules/Live`、`Modules/KSong`）；
    - 可节约体积（端上源码 + 疑似关联 Pods）。
  - 形成更细粒度的任务：
    - `type`: `"try_disable_business"`
    - `businessName`: 例如 `"录唱"`
    - `entryPoints`: 入口所在文件路径 + 描述
    - `mainDirectories`: 主要业务目录列表
    - `suggestedAction`: 「先在配置层关闭入口，再分阶段移除内部模块及 Pods」

> **结论：**
> - 当前正式版 SKILL 中，「execute」仅指**生成上述三类任务的「计划/清单」**，不会直接改代码或文件。
> - 多 Target 场景暂不在本 SKILL 的执行范围内，所有任务都以 `relativePath` 和 Pod 名等信息给出，由调用方结合具体工程结构执行。

---

## 四、错误处理与降级策略

在以下场景中，Skill 应该返回**合理的 HTML 提示页面**，而不是空结果或报错堆栈：

1. **文件不存在或无法访问**  
   - 返回一个简单 HTML，说明无法读取文件，并在 `<body>` 中给出：
     - 错误原因（路径不存在 / 权限不足）；
     - 建议检查项（路径是否正确、是否已经导出 JSON）。

2. **JSON 解析失败**  
   - 返回 HTML，提示「文件内容不是合法 JSON」，并建议重新从 AppThinner 导出。

3. **关键字段缺失**  
   - 报告中照常展示能分析的部分，同时在「风险提示」章节中标记哪些能力未开启或数据缺失。

---

## 五、目录结构建议

参考内部规范，Skill 目录结构建议如下（已在当前项目根目录下创建）：

```text
ios-package-optimization/
├── SKILL.md          # 当前文件，描述 Skill 行为与输入输出规范
├── scripts/          # （可选）后续若需要 CLI 或自动化脚本可放置于此
├── assets/           # （可选）可以放示例 JSON、HTML 模板等
└── docs/             # （可选）更详细的使用说明或案例
```

当前版本仅提供 `SKILL.md` 规范说明，实际行为由 LLM 根据本说明执行；后续如有需要，可在 `scripts/` 与 `assets/` 中补充自动化工具与模板。

