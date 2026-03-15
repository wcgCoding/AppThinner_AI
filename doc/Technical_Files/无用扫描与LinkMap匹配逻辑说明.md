# 无用类/资源扫描与 LinkMap 匹配逻辑说明

> 本文档为《[关键技术难点与核心原理说明](./关键技术难点与核心原理说明.md)》中 **2. 无用扫描及映射到文件列表的原理** 的详细展开，供 PPT/汇报深挖实现时引用。

## 你的理解（结论：正确）

> 无用类及资源扫描出结果后，应该是**直接去跟 linkmap 扫描得到的 object files 进行匹配**，命中的后**更新标记为无用 files**，之后在**构造 treemap 时统计总体体积占比**。

当前实现正是按这一套逻辑做的，匹配的「桥梁」是**工程相对路径**。

---

## 数据流简图

```
LinkMap 解析
  → ObjectFileInfo[]（.o 路径 + totalSize）
  → mapObjectFilesToProjectStructure（projectFileIndex / 静态库 / frameworkNameToPath）
  → CodeSizeInfo[]：每项 = (relativePath=工程路径或 linkmap 回退路径, totalSize, symbols)

工程目录扫描
  → projectFileEntries[]（工程内所有文件，relativePath + fileName）

整合阶段 buildIntegratedDataFromProjectEntries
  → 将 CodeSizeInfo 分为 virtualObjectEntries（relativePath 含 "(") 与 realCodeEntries
  → pathToCodeSize：仅对 realCodeEntries 按 relativePath 聚合，再 aggregateFrameworkObjectPathsToBinary
  → 每个工程文件 + 虚拟 .o 节点：relativePath, codeSize, resourceSize, frameworkSize
  → 产出 integratedData.files（含普通文件与虚拟 .o、.car 未匹配虚拟节点）

无用扫描 buildUnusedContentResults
  → UnusedContentResults(unusedResources, unusedCode)
  → unusedCode[]：每项 (className, filePath=工程路径, …)；unusedResources[]：每项 (relativePath, size, …)

标记阶段 createAnalysisProject
  → 预构建 Set：unusedResourcePaths、unusedClassNames、unusedCodeSourcePaths
    （unusedCodeSourcePaths = unusedCode.filePath 且扩展名为 .m/.mm/.swift/.c/.cc/.cpp）
  → 对 integratedData.files 每条 file：
      isUnusedResource = unusedResourcePaths.contains(file.relativePath)
      isUnusedCode = 若 file.relativePath 为虚拟 .o（含 "(")：
                        virtualNodeContainsUnusedClass(file.relativePath, unusedClassNames)
                    否则：unusedCodeSourcePaths.contains(file.relativePath)
  → 批量写入 Core Data（AnalysisResult），每 500 条 saveContext 一次

Treemap 构造
  → 从 AnalysisResult 建 DirectoryNode / FileNode
  → 每个文件：isUnused = isUnusedResource || isUnusedCode，totalSize = codeSize + resourceSize + frameworkSize
  → 目录：unusedSize = Σ( 若 isUnused 则 totalSize 否则 0 )
  → 占比：unusedRatio = unusedSize / totalSize（用于冷→暖着色）
```

---

## 关键点确认

| 环节 | 说明 |
|-----|------|
| **和 object files 的对应关系** | LinkMap 的 object files 先通过 `mapObjectFilesToProjectStructure` 转成 `CodeSizeInfo`（含工程路径或回退路径）；整合时仅对**非虚拟**条目按工程路径聚合到 `pathToCodeSize`，再填到 `integratedData.files`。无用标记是对「整合后的文件列表」（含虚拟 .o 节点）做路径/类名匹配，**没有**直接对成千上万个 .o 逐条匹配。 |
| **匹配键（普通节点）** | **工程相对路径**：`isUnusedResource` 用 `unusedResourcePaths.contains(file.relativePath)`；`isUnusedCode` 用 `unusedCodeSourcePaths.contains(file.relativePath)`。`unusedCodeSourcePaths` 仅包含无用类对应的**源文件路径**（扩展名 .m/.mm/.swift/.c/.cc/.cpp）。 |
| **匹配键（虚拟 .o 节点）** | 虚拟节点（relativePath 含 `"("`）的 **isUnusedCode** 通过 `virtualNodeContainsUnusedClass(relativePath, unusedClassNames)` 判断：该编译单元符号中是否包含任一无用类名。 |
| **命中的含义** | 命中 = 该条文件/虚拟节点在 Core Data 中记为 `isUnusedResource` 或 `isUnusedCode`；其 codeSize/resourceSize/frameworkSize 在整合阶段已由 LinkMap / IPA 归属确定。 |
| **Treemap 体积占比** | 每个节点 `totalSize` = code+resource+framework 之和；`unusedSize` = 被标为无用的文件的 `totalSize` 之和；占比 = `unusedSize / totalSize`，用于冷→暖着色。 |
| **写入方式** | `createAnalysisProject` 中按条 `createAnalysisResult`，每 500 条调用一次 `saveContext`，以降低 I/O 压力。 |

因此：**用无用扫描结果（路径集合 + 类名集合）与整合后的文件列表做匹配 → 标成无用并写入 AnalysisResult → Treemap 按总体积算占比**；虚拟 .o 节点通过「该类 .o 的符号是否含无用类」参与 isUnusedCode 判断。

---

## 可选增强（路径归一化）

若出现「扫描说是无用、但 treemap 没标红」或反过来，多半是**路径写法不一致**（如有无前缀、大小写、`\` vs `/`）。可在匹配前对 `UnusedCode.filePath`、`UnusedResource.relativePath` 与 `file.relativePath` 做统一归一化（如 `(path as NSString).standardizingPath` 或统一转小写）。当前代码为**直接字符串相等**比较，在工程路径统一为相对路径且无多余写法差异时逻辑合理。

---

## 代码位置速查

| 环节 | 文件 | 说明 |
|------|------|------|
| 无用扫描 | `AnalysisService`、静态分析 / Mach-O / 外部数据 | `buildUnusedContentResults` → `UnusedContentResults(unusedResources, unusedCode)` |
| 标记与入库 | `AnalysisService.swift` | `createAnalysisProject`：`unusedResourcePaths`、`unusedClassNames`、`unusedCodeSourcePaths`，`virtualNodeContainsUnusedClass`、`isVirtualObjectPath`，批量 500 条 `createAnalysisResult` + `saveContext` |
| Treemap 占比 | `TreemapGenerator.swift` | 从 AnalysisResult 建节点，`unusedRatio` 计算与着色 |

---

