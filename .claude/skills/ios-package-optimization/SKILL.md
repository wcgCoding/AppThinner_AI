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

- Skill 的**唯一输入**是：**本地文件路径字符串**，例如：
  - `/Users/xxx/Downloads/ai-optimization-report-MyApp.json`
  - 或项目内的相对路径（由上层调用方转换为绝对路径）
- 调用时不要直接粘贴 JSON 内容，而是提供「已经导出的 JSON 文件路径」。

### 2. 文件内容规范

文件内容应当是由 AppThinner 中「Treemap 可视化 → 导出 AI 报告数据」功能生成的 JSON，形如（字段简化示例）：

```jsonc
{
  "version": "1.0",
  "exportedAt": "2026-03-11T12:34:56Z",
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
      /* 递归同结构，relativePath 为业务目录，如 "Modules/Pay", "Features/Live" */
    ]
  },
  "unusedCode": [
    {
      "relativePath": "String",
      "fileName": "String",
      "codeSizeBytes": 0,
      "codeSizeKB": 0.0
    }
  ],
  "unusedResources": [
    {
      "relativePath": "String",
      "fileName": "String",
      "resourceSizeBytes": 0,
      "resourceSizeKB": 0.0
    }
  ],
  "podsDependencies": {
    "podfileLockPath": "Podfile.lock",
    "mainLibSummary": [
      {
        "name": "AFNetworking",
        "version": "4.0.1",
        "sizeBytes": 0,
        "sizeKB": 0.0,
        "unusedSizeBytes": 0,
        "unusedSizeKB": 0.0,
        "unusedRatio": 0.0,
        "dependedByCount": 0,
        "dependedByList": ["MainApp"]
      }
    ],
    "tree": [
      /* PodsDependencyInfo 数组，原始依赖树，仅作结构参考 */
    ]
  }
}
```

### 3. 输入校验要求

Skill 应在读取文件后进行以下校验：

1. 路径是否存在、是否为普通文件；不存在时返回明确错误提示，不继续解析。
2. 是否能够成功解析为 JSON；失败时返回「不是合法 JSON」的错误说明。
3. 顶层是否包含以下关键字段：
   - `version`（期望 `"1.0"`，其他版本需要在报告中标注兼容性提示）
   - `project`
   - `sizeDistribution`
4. 如 `unusedCode` / `unusedResources` / `podsDependencies` 缺失或为空，应被视为「该能力未开启或无结果」，不能简单当作 0。

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

### 1. 体积分布分析（sizeDistribution）

- 从 `sizeDistribution.children` 中选取 **Top N 业务目录**（例如 5–10 个，按 `totalSizeBytes` 降序）。
- 对每个目录输出：
  - `relativePath`（例如 `Modules/Pay`, `Features/Live`, `Pods/AFNetworking`）
  - 总体积及 Code / Resource / Framework 构成占比；
  - `unusedRatio`（如 > 0 时标红或加醒目标记）。
- 在报告中用自然语言小结：
  - 指出「体积大户」模块；
  - 指出「无用占比较高」的目录，作为优先治理对象。

### 2. 无用代码与资源（unusedCode / unusedResources）

- 按 `relativePath` 的上层目录（如前两级路径）对无用项进行聚合：
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

### 3. Pods 依赖优化（podsDependencies）

当 `podsDependencies` 存在时：

- 基于 `mainLibSummary`：
  - 找出体积较大的 Pods（sizeKB 高）；
  - 找出 `unusedRatio` 较高的 Pods；
  - 结合 `dependedByCount`、`dependedByList` 识别「只被少量边缘模块依赖」的库。
- 报告中给出：
  - 可考虑下线/替换的 Pods 列表；
  - 建议治理方式：例如按子模块拆分、替换为更轻量实现、与业务确认后下线等。

### 4. 优先级与路线图

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

