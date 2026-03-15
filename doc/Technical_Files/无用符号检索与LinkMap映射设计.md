# 无用 ObjC 方法检索与 LinkMap Object File 映射设计（精简版）

## 1. 目标与范围

- **目标**
  - 基于 **ObjC 方法静态调用图 + LinkMap**，找出「静态上无引用、但仍存在于最终二进制中的 ObjC 方法」。
  - 将这些方法精确映射到 **LinkMap 的 Object File（编译单元）** 和 **工程相对路径**，最终体现在 AppThinner 当前架构中的 **无用代码体积**。
- **范围限定**
  - 仅覆盖 **Objective‑C 方法（类/分类）**，暂不处理 C 函数 / C++ / Swift。
  - 仅依赖 **源码 + 编译 index + LinkMap/Mach‑O**，**不解析 Storyboard/XIB**，也不依赖 IBAction 绑定信息。
  - 结果作为静态分析候选集，需要结合白名单与人工复核。

---

## 2. 总体架构

| 组件 | 职责 |
|------|------|
| **ObjCSourceIndexer** | 基于 clang index/AST 抽取 ObjC 方法定义与调用关系，构建 `MethodSymbol` 列表与调用边。 |
| **CallGraphBuilder** | 从 `MethodSymbol` 构建 ObjC 方法调用图，负责根集合选取与可达性分析。 |
| **BinarySymbolResolver** | 解析 LinkMap/Mach‑O，将 ObjC 方法映射到具体符号、大小与 Object File。 |
| **UnusedObjCAnalyzer** | 交叉「静态不可达」与「仍在二进制中」集合，应用白名单过滤，得到候选无用方法。 |
| **ResultExporter** | 将结果导出为 JSON，供 AppThinner 导入并回灌到 `UnusedCode` / Treemap 体系。 |

新增 CLI 工具 `UnusedSymbolScanner` 调用上述组件，AppThinner 通过命令行或内部 API 调用获取结果。

---

## 3. 数据模型（MethodSymbol 与输出）

### 3.1 MethodSymbol（仅 ObjC）

```text
MethodSymbol {
  id: String            // 例如 "objc:-[FooViewController refreshData]"
  mangledName: String   // 底层链接符号名，供 LinkMap 匹配
  demangledName: String // 人类可读名称，展示用
  sourceFile: String    // 工程内相对路径
  line: Int             // 定义行号

  callees: [String]     // 静态调用边（id）
  callers: [String]     // 反向边（分析后填充）

  inBinary: Bool        // 是否出现在最终二进制
  sizeInBinary: Int64   // 在 LinkMap 中的体积（字节）
  objectFile: String    // 所属编译单元（.o）

  isRootCandidate: Bool // 是否作为根方法参与可达性分析
  tags: Set<String>     // { "+load", "+initialize", "sdkCallback", "whitelist", ... }
}
```

### 3.2 输出 JSON（供 AppThinner 导入）

```json
{
  "version": 1,
  "methods": [
    {
      "id": "objc:-[FooViewController refreshData]",
      "demangledName": "-[FooViewController refreshData]",
      "sourceFile": "App/FooViewController.m",
      "line": 120,
      "sizeInBinary": 512,
      "reason": "UnreachableInObjCCallGraphAndPresentInBinary",
      "tags": []
    }
  ],
  "summary": {
    "candidateCount": 80,
    "totalSize": 153600
  }
}
```

---

## 4. ObjC 方法静态调用图构建

### 4.1 方法发现

- 使用 clang index / AST：
  - 枚举所有 `@implementation` / 分类中的 `-` / `+` 方法实现；
  - 为每个实现创建 `MethodSymbol`，填充 `id` / `sourceFile` / `line`。

### 4.2 显式调用关系

- 对所有 `[obj method]`、`[Class method]`：
  - 利用编译器解析结果确定目标方法实现；
  - 在调用图中添加 `caller → callee`。

### 4.3 selector 相关调用（不含 Storyboard/XIB）

- 支持以下模式：
  - `@selector(foo:)` / `#selector(Foo.foo)`；
  - `performSelector:@selector(...)` 等。
- 将 SEL 与所有实现该 SEL 的 ObjC 方法建立“可能调用”边。

### 4.4 精简版 runtime 模式

- 仅覆盖常见且易静态识别的 API：
  - `addTarget:action:forControlEvents:`
  - `addObserver:selector:name:object:`
- 从调用点解析出 `selector`，将对应方法视为**可能被调用**，在调用图中加入边或直接作为根方法。

> 说明：不解析 Storyboard/XIB，不自动识别 IBAction 绑定，相关方法需要通过白名单显式保护。

---

## 5. 根集合与可达性分析

- **根集合（`isRootCandidate = true`）包括：**
  - 所有实现 `+load` / `+initialize` 的方法；
  - 通过 `addTarget:action:`、`addObserver:selector:` 等 API 绑定的 selector 对应方法；
  - 白名单配置中显式声明为 root 的方法（例如 SDK 要求实现的回调）。

- **可达性分析流程：**
  1. 从所有根方法出发，对调用图执行 DFS/BFS；
  2. 访问到的节点标记为 `reachable`；
  3. 得到静态不可达集合 `U_objc = { m | reachable(m) == false }`。

---

## 6. 与 LinkMap 的映射与体积计算

### 6.1 方法实现 → 符号名

- 利用 clang index / DWARF debug 信息，为每个 ObjC 方法实现获取底层 `linkage_name`（`mangledName`）。

### 6.2 符号名 → LinkMap 记录

- 解析 LinkMap `Symbols:` 段，得到每条符号的：
  - 名称、地址、大小、`objectFileIndex`。
- 通过 `mangledName` 匹配符号：
  - 成功匹配则为 `MethodSymbol` 填充：
    - `inBinary = true`
    - `sizeInBinary`
    - `objectFile`（由 `objectFileIndex` 映射得到路径）。

### 6.3 候选集合

- 定义候选无用 ObjC 方法集合：

```text
Candidate = { m ∈ U_objc | m.inBinary == true }
```

- 对 `Candidate` 按 `sizeInBinary` 降序排序，用于 UI 展示与收益评估。

---

## 7. 白名单与安全过滤（不支持 Storyboard/XIB 自动识别）

- **配置文件（YAML/JSON 示例）**

```yaml
roots:
  - "-[AppDelegate application:didFinishLaunchingWithOptions:]"
whitelist:
  - "-[LoginManager *]"
  - "-[SomeSDKDelegate onEvent:*]"
```

- **规则**
  - 匹配 `roots` 的方法：强制 `isRootCandidate = true`。
  - 匹配 `whitelist` 的方法：即使属于 `Candidate`，也不输出到结果（为其打上 `whitelist` tag）。
- **Storyboard/XIB 说明**
  - 本设计**不解析 nib/storyboard**，不自动识别 IBAction/IBOutlet；
  - 若某些 IBAction 必须保留，需要在白名单中显式配置对应方法签名。

---

## 8. 回灌到现有 AppThinner 架构

### 8.1 按源文件聚合无用方法体积

- 对每个候选方法 `m ∈ Candidate`：
  - 已知 `objectFile`，通过现有「Object File → 源文件」映射拿到 `sourceFile`（如 `App/FooViewController.m`）；
  - 维护字典 `unusedCodeBytesOfFile[sourceFile] += m.sizeInBinary`。

### 8.2 与 `AnalysisResult` / Treemap 对接

- 在构建 `IntegratedFileInfo` / `AnalysisResult` 时：
  - 为每个文件增加字段 `unusedCodeSizeStaticObjC`（或折算进现有 `unusedCodeSize`）；
  - 在 UI 中通过标签区分来源：`UnusedSource = .staticGraphObjC`。
- 在 `AnalysisSummary` 中：
  - `unusedCodeSize` 纳入这部分体积，使其参与「潜在节省」计算与对比分析。

### 8.3 展示形态

- 按文件/Treemap 节点展示：
  - 每个文件的「无用 ObjC 方法体积」与占比；
  - 支持点击进入，查看该文件下的无用方法明细（方法名 + 体积）。
- 报告中新增小节：
  - 「基于静态调用图的无用 ObjC 方法统计」。

---

## 9. 迭代计划（仅针对 ObjC 方法）

- **阶段 1：基础链路打通（3–5 天）**
  - 目标：仅基于显式调用 + `+load`/`+initialize` + 白名单，跑通：
    - ObjC 方法发现 → 调用图 → 根集合 → `U_objc`；
    - 方法 → 符号 → LinkMap Object File → 源文件；
    - 输出 JSON，并在 AppThinner 中以「文件级无用 ObjC 体积」形式展示。

- **阶段 2：完善 runtime 模式与白名单（5–7 天）**
  - 目标：加入 `@selector`、`#selector`、`addTarget:action:`、`addObserver:selector:` 等模式；
  - 完善白名单匹配语法（支持通配符），降低误报；
  - UI 增加「方法级明细」视图和来源标签。

- **风险与约束**
  - 动态反射（`NSClassFromString`、字符串拼接 selector 等）难以完全覆盖，只能依赖白名单；
  - 不支持 Storyboard/XIB 自动识别，IBAction 必须通过配置保护；
  - 结果视为高置信度候选，仍需结合实际业务与测试验证再做删除决策。

### 9.1 第一步 CLI 已实现（UnusedSymbolScanner）

- **位置**：Xcode 工程内独立 target `UnusedSymbolScanner`，入口 `AppThinnerAnalyzer/UnusedSymbolScanner/main.swift`。
- **能力**：基于**现有无用类（Mach-O + LinkMap）**与 **UnusedSymbolMappingService**，打通「工程 + LinkMap + IPA/.app → 无用类 → 无用符号 → 按 Object File 聚合」并输出 JSON（不依赖 ObjC 方法调用图）。
- **用法**：
  ```bash
  UnusedSymbolScanner --linkmap <path> [--project <path>] [--ipa <path>|--app <path>] [--output <path>]
  ```
- **输出**：JSON 含 `unusedClasses`、`unusedSymbolMapping`（含 `unusedSymbols`、`byObjectFile`、`totalUnusedSymbolSize`）、`summary`。
- **构建**：在 Xcode 中选择 scheme `UnusedSymbolScanner` 编译，或：
  ```bash
  xcodebuild -project AppThinnerAnalyzer/AppThinnerAnalyzer.xcodeproj -scheme UnusedSymbolScanner -destination 'platform=macOS' build
  ```

# 无用符号检索与 LinkMap Object File 映射设计

## 1. 目标

- **检索**：在分析结果中检索出「无用符号」的**名称**与**大小**（字节）。
- **映射**：将每条无用符号映射到 **LinkMap 的 Object Files**（即具体 `.o` / 编译单元），便于按文件查看无用体积分布。
- **统计**：上述无用符号体积作为**无用体积的一部分**，与现有「无用类」口径一致（总和应等于各无用类的 `estimatedSize` 之和）。

## 2. 当前架构要点

| 组件 | 职责 |
|------|------|
| **LinkmapAnalyzer** | 解析 LinkMap：得到 `LinkmapParseResult`（`objectFileInfos` + `symbols`）。每条 `SymbolInfo` 含 `symbolName`、`size`、`objectFileIndex`。 |
| **mapObjectFilesToProjectStructure** | 将 Object 按路径匹配到工程结构，得到 `[CodeSizeInfo]`（按 `relativePath` 聚合，每条含 `symbols`）。 |
| **BinaryUnusedCodeAnalyzer** | 基于 Mach-O 的 classlist/classrefs 等得到无用类名集合，并结合 `codeSizeInfo` 为每个无用类算 `estimatedSize` 与 `filePath`。 |
| **AnalysisService.buildUnusedContentResults** | 调用无用扫描、合并外部数据，并用 `buildCodeSizeByClassFromSymbols` 为无用类填 `estimatedSize`。 |

当前**未**暴露「符号级」无用明细，也未显式把无用符号映射回 LinkMap 的 Object File（`[N] path`）。

## 3. 数据模型（已实现）

- **UnusedSymbolRecord**（`DataModels.swift`）
  - `symbolName`：符号名（如 `_OBJC_CLASS_$_Foo`、`_-[Foo bar]`）
  - `size`：该符号在 LinkMap 中的大小（字节）
  - `objectFileIndex`：LinkMap Object files 段中的编号
  - `objectFilePath`：LinkMap 中该 Object 的原始路径
  - `resolvedRelativePath`：解析后的项目相对路径（与 Treemap/分析结果一致）
  - `className`：所属无用类名（若由无用类推导）

- **UnusedSymbolMappingResult**
  - `unusedSymbols`：无用符号明细列表
  - `byObjectFile`：按 `objectFileIndex` 聚合，便于按 .o 查看
  - `totalUnusedSymbolSize`：无用符号总体积（应与无用类 `estimatedSize` 之和一致）

## 4. 检索逻辑（已实现：UnusedSymbolMappingService）

- **输入**
  - `parseResult: LinkmapParseResult?`：LinkMap 解析结果（可为 nil，此时仅用 codeSizeInfo 做路径）
  - `codeSizeInfo: [CodeSizeInfo]`：已按工程路径聚合的代码信息（含 symbols）
  - `unusedClassNames: Set<String>`：无用类名集合（与 `UnusedCode` 一致）

- **判定「无用符号」**
  - 与 `AnalysisService.buildCodeSizeByClassFromSymbols` 一致：若符号属于某无用类，则记为无用。
  - 规则：ObjC 正则匹配 `_OBJC_CLASS_$_` / `_OBJC_METACLASS_$_`、`_-[Class method]` / `_+[Class method]`；符号数超过阈值时关闭「类名 contains」回退，避免卡顿。

- **映射到 Object File**
  - `objectFileIndex` 已在 `SymbolInfo` 中，直接使用。
  - `objectFilePath`：由 `parseResult.objectFileInfos` 中 `index → ObjectFileInfo.filePath` 得到；`parseResult == nil` 时为空字符串。
  - `resolvedRelativePath`：由 `codeSizeInfo` 建立 `objectFileIndex → relativePath`，保证与 Treemap/分析结果一致。

- **输出**
  - `UnusedSymbolMappingResult`：含 `unusedSymbols`、`byObjectFile`、`totalUnusedSymbolSize`。

## 5. 集成点（待接入）

- **LinkMap 解析结果传递**
  - 当前 `parseLinkmapFiles` 只返回 `[CodeSizeInfo]`，不返回 `LinkmapParseResult`。
  - **建议**：改为返回 `(codeSizeInfo: [CodeSizeInfo], parseResult: LinkmapParseResult)`（或封装成 struct），并在 `DataSourceResults` 中增加 `linkmapParseResult: LinkmapParseResult?`，在 `parseAllDataSources` 里一并传入下游。

- **在 buildUnusedContentResults 中调用**
  - 在得到 `mergedCode`（无用类列表）之后：
    - 取 `unusedClassNames = Set(mergedCode.map(\.className))`
    - 调用 `unusedSymbolMappingService.buildUnusedSymbolMapping(parseResult: linkmapParseResult, codeSizeInfo: codeSizeInfo, unusedClassNames: unusedClassNames)`
  - 将得到的 `UnusedSymbolMappingResult` 作为无用内容结果的一部分传递（例如扩展 `UnusedContentResults` 或单独字段）。

- **存储与展示**
  - **存储**：可选将 `UnusedSymbolMappingResult` 序列化存 CoreData（如 AnalysisProject 的关联表或 JSON 字段），便于报告与二次分析。
  - **展示**：在「无用代码」或「无用体积」视图中增加：
    - 按 Object File（或按 resolved path）分组的无用符号列表（符号名 + 大小）；
    - 小计：每个 .o 的无用符号数量与体积，以及总体无用符号体积（作为无用体积的一部分）。

## 6. 一致性说明

- `totalUnusedSymbolSize` 应与 `unusedCode.reduce(0) { $0 + $1.estimatedSize }` 一致（同一套符号、同一套无用类判定）。
- 若未来支持「按符号白名单/黑名单」或「仅部分类参与统计」，需在检索阶段与 `buildCodeSizeByClassFromSymbols` 使用同一套类名集合与判定规则。

## 7. 小结

| 项 | 说明 |
|----|------|
| 检索 | 由无用类名 + LinkMap 符号表，用现有 ObjC 正则与回退规则筛出无用符号，得到名称与大小。 |
| 映射 | 通过 `objectFileIndex` 关联到 `ObjectFileInfo`，得到 LinkMap 原始路径与工程相对路径。 |
| 数据 | `UnusedSymbolRecord` + `UnusedSymbolMappingResult`，已定义；`UnusedSymbolMappingService` 已实现并加入 DI。 |
| 集成 | 需在分析链路中传入 `LinkmapParseResult` 并在 `buildUnusedContentResults` 中调用映射服务，将结果写入存储/UI。 |

此设计在现有「无用类 + LinkMap 符号」架构下，实现无用符号的检索与到 LinkMap Object Files 的映射，并作为无用体积的一部分参与统计与展示。

---

## 8. 不依赖无用类的方案：直接基于 Mach-O 符号表与重定位

**结论：可以。** 无用符号的判定可以不依赖「无用类」，直接通过解析 Mach-O 得到「已定义且未被引用」的符号集合，再与 LinkMap 按地址对齐得到带大小、Object File 的无用符号列表。

### 8.1 思路

- **已定义符号**：来自 Mach-O 的 **LC_SYMTAB** 符号表，`n_type == N_SECT` 的项表示在本二进制内有定义的符号（含地址、名称、section）。
- **被引用符号**：来自 Mach-O 的 **重定位（relocations）** 与 **间接符号表（indirect symbol table）**：
  - 重定位表中，每条 relocation 会引用一个符号（symbol index）；所有被引用到的符号索引构成「被引用集合」。
  - 间接符号表（LC_DYSYMTAB + indirect symbol table）里，__stubs / __got / __la_symbol_ptr 等会通过 reserved1 + offset 指向符号表索引，这些索引也应视为被引用。
- **无用符号**：**已定义符号索引集合 − 被引用符号索引集合**（再排除入口、导出等需保留的符号，按需处理）。

得到的是「在 Mach-O 内未被引用」的符号索引（或地址/名称），与语言无关（ObjC / Swift / C / C++ 均适用）。

### 8.2 与 LinkMap 的衔接

- LinkMap 提供的是：每条符号的 **地址**、**大小**、**名称**、**objectFileIndex**；名称可能与 Mach-O 符号表不一致（strip、Swift 混淆等）。
- 因此用 **地址** 做对齐更可靠：
  1. 从 Mach-O 得到「无用符号的地址集合」`unusedAddresses`（由无用符号的 n_value 得到，注意 ASLR 时用 slide 校正，主可执行文件通常为 0）。
  2. 遍历 LinkMap 的每条符号：若 `symbol.address`（解析出的 0x... 值）落在 `unusedAddresses` 中，则该 LinkMap 符号视为无用，直接得到其 **名称、大小、objectFileIndex**，进而映射到 Object File 与 resolved path。

这样就不再依赖「无用类」或任何类名匹配，完全由 Mach-O 的「定义 − 引用」决定无用符号。

### 8.3 实现要点（MachOKit）

- **符号表**：MachOKit 提供对 LC_SYMTAB 的访问（如 `machO.symbols64` / symbol table 相关 API），可得到 defined symbols 的 index、name、address。
- **重定位**：需解析各 section 的 relocation 条目（LC_DYSYMTAB 与 section 的 relocations），收集每条 relocation 的 symbol index，得到 referenced set。MachOKit 支持 rebase/binding 等，是否直接暴露「每条 relocation 的 symbol index」需查当前 API。
- **间接符号表**：LC_DYSYMTAB 的 indirectsymtab 与各 section 的 reserved1 结合，可得到通过 stub/got 引用的符号索引，也应并入 referenced set。

若当前 MachOKit 对「普通 relocation 的 symbol index」支持不完整，可考虑仅用「间接符号表 + ObjC classrefs 等已有引用」作为 referenced 的保守子集，仍能筛掉一部分无用符号；或对 relocation 做一次底层解析。

### 8.4 与当前「无用类」方案的关系

| 方式 | 优点 | 缺点 |
|------|------|------|
| **无用类 → 符号**（当前） | 对 ObjC 语义准确（classrefs 等）；实现简单，已落地。 | 只覆盖「属于某无用类」的符号；依赖类名与 LinkMap 符号名的匹配。 |
| **Mach-O 定义 − 引用 → 符号**（本方案） | 不依赖无用类；语言无关；理论上可覆盖 C/Swift/C++/ObjC 所有未引用符号。 | 依赖 MachOKit 对符号表与重定位的完整解析；strip 后需依赖地址对齐。 |

建议：**两套可并存**——优先用「Mach-O 直接判定」产出无用符号集合（若实现完整），再与 LinkMap 按地址对齐得到 UnusedSymbolRecord；对未集成的平台或需要与现有「无用类」口径一致时，仍保留「无用类 → 符号」的路径，并在文档中注明两种口径的差异与选用场景。
