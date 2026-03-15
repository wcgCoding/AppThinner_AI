# AppThinnerAnalyzer

> iOS 应用包体积本地分析工具，由 AI 辅助开发

一款运行在 macOS 上的 iOS 包体积分析工具。通过融合 **LinkMap 文件**、**IPA/.app 包**、**项目工程目录** 三个独立数据源，生成统一的可交互 TreeMap 可视化视图，帮助开发者快速定位体积瓶颈、识别无用代码与资源、分析第三方库依赖结构。

---

## 功能概览

| 功能 | 说明 |
|---|---|
| **TreeMap 可视化** | 基于 ECharts 的交互式树状图，支持下钻导航，按无用占比热力着色 |
| **LinkMap 解析** | 解析 Xcode 生成的 LinkMap 文件，精确获取每个编译单元的代码体积 |
| **IPA / .app 解析** | 分析实际发布包的文件结构与大小，自动读取版本号与 Build No |
| **无用代码检测** | 解析 Mach-O 二进制的 `__objc_classlist` / `__objc_classrefs`，找出未被引用的 ObjC 类 |
| **无用资源检测** | 通过正则扫描源码中的资源引用，识别未使用的图片等资源文件 |
| **重复内容检测** | 基于内容哈希检测重复代码块与重复资源文件 |
| **Pods 依赖分析** | 解析 `Podfile.lock`，按主库聚合展示依赖关系树与各库体积占比 |
| **历史对比** | CoreData 持久化分析结果，支持跨版本体积变化对比 |
| **AI 报告导出** | 导出结构化 JSON 数据，可直接输入 AI 生成优化建议 |

---

## 运行环境

- macOS 14.0+
- Xcode 15+

---

## 构建方式

用 Xcode 打开 `AppThinnerAnalyzer/AppThinnerAnalyzer.xcodeproj`，按 `⌘R` 运行。

或使用命令行：

```bash
# Debug 构建
xcodebuild -project AppThinnerAnalyzer/AppThinnerAnalyzer.xcodeproj \
  -scheme AppThinnerAnalyzer -destination 'platform=macOS' -configuration Debug build

# Release 构建
xcodebuild -project AppThinnerAnalyzer/AppThinnerAnalyzer.xcodeproj \
  -scheme AppThinnerAnalyzer -destination 'platform=macOS' -configuration Release build
```

---

## 使用方式

**1. 准备输入文件**

三个输入至少提供一个，提供越多分析越完整：

| 输入 | 获取方式 |
|---|---|
| **IPA 文件** | 从 Xcode 归档导出，或直接选择 `.app` bundle |
| **LinkMap 文件** | Xcode Build Settings 中开启 `Write Link Map File`，编译后在 DerivedData 中找到 `.txt` |
| **项目工程目录** | iOS 项目根目录，用于路径解析与资源扫描 |

**2. 启动分析**

打开 App → 在左侧输入区选择文件 → 点击右上角 **Start Analysis**

**3. 配置扫描项（可选）**

点击 **配置** 按钮，按需开启以下扫描（默认关闭，会增加分析耗时）：

- 无用代码扫描
- 无用资源扫描
- 代码重复扫描
- 资源重复扫描
- Pods 依赖扫描

**4. 查看结果**

分析完成后自动跳转到 TreeMap 视图，历史记录保存在左侧侧边栏，随时切换对比。

---

## 架构设计

### 三数据源融合

整个分析流程围绕将三个独立数据源融合为统一文件树展开，**项目相对路径**（`relativePath`）是连接所有数据源的唯一 Key：

```
LinkMap .txt      ──►  LinkmapAnalyzer         ──►  codeSize       ┐
IPA / .app        ──►  PackageParser            ──►  resourceSize   ├──► TreemapGenerator ──► ECharts
项目工程目录       ──►  ProjectResourceScanner   ──►  路径索引        ┘
```

### 分析流水线

```
Phase 1 (并发):  IPA 解析  +  项目目录扫描
                     └──► LinkmapAnalyzer（依赖项目路径索引）

Phase 2:  buildIntegratedDataFromProjectEntries
              └──► IntegratedAnalysisData（每个文件的 codeSize + resourceSize + frameworkSize）

Phase 3:  buildUnusedContentResults
              ├──► BinaryUnusedCodeAnalyzer（Mach-O ObjC 类差集计算）
              └──► UnusedScanService（正则匹配资源引用）

Phase 4:  createAnalysisProject  →  CoreData 持久化
```

### 虚拟 `.o` 节点

当 LinkMap 路径通过 Framework 方式解析时（如 `Pods/SDWebImage/SDWebImage.framework/SDWebImage(SDImageCache.o)`），会生成虚拟节点挂载到对应 Framework 目录下，在 TreeMap 中以编译单元粒度展示框架内部体积，避免框架总体积重复计算。

### 目录结构

```
AppThinnerAnalyzer/
├── AppThinnerAnalyzer/
│   ├── AppThinnerAnalyzerApp.swift
│   ├── Views/                          # SwiftUI 视图层
│   │   ├── MainView.swift              # 主界面（侧边栏 + 导航）
│   │   ├── AnalysisView.swift          # 分析输入与进度
│   │   ├── TreemapView.swift           # TreeMap + 按文件夹展开 + Pods + 重复
│   │   ├── ComparisonView.swift        # 跨版本对比
│   │   ├── HistoryView.swift           # 历史记录
│   │   └── EChartsWebView.swift        # WKWebView 封装
│   ├── ViewModels/                     # ObservableObject 视图模型
│   ├── Services/
│   │   ├── AnalysisService.swift       # 全流程编排（唯一总调度）
│   │   ├── LinkmapAnalyzer.swift       # LinkMap 解析 + 路径解析
│   │   ├── PackageParser.swift         # IPA / .app 解析
│   │   ├── ProjectResourceScanner.swift # 工程目录扫描
│   │   ├── BinaryUnusedCodeAnalyzer.swift # Mach-O 无用类检测
│   │   ├── UnusedScanService.swift     # 无用资源扫描
│   │   ├── TreemapGenerator.swift      # Squarified 矩形树图布局
│   │   ├── CodeDuplicateScanService.swift
│   │   ├── ResourceDuplicateScanService.swift
│   │   ├── PodsDependencyScanService.swift
│   │   └── AIExportService.swift
│   ├── Models/
│   │   └── DataModels.swift            # 全部值类型数据结构
│   ├── CoreData/                       # CoreData 实体扩展
│   └── Resources/
│       ├── EChartsTreemap.html         # TreeMap 渲染（WKWebView 加载）
│       └── EChartsGraph.html           # 依赖关系图渲染
└── MachOObjCSection/                   # 本地 Swift Package，Mach-O ObjC 段解析
```

---

## 依赖

| 库 | 版本 | 用途 |
|---|---|---|
| [MachOKit](https://github.com/p-x9/MachOKit) | 0.46.1 | Mach-O 二进制文件解析 |
| [XcodeProj](https://github.com/tuist/XcodeProj) | 9.10.1 | Xcode 工程文件解析 |
| [AEXML](https://github.com/tadija/AEXML) | 4.7.0 | XML 解析 |
| [PathKit](https://github.com/kylef/PathKit) | 1.0.1 | 路径处理 |
| MachOObjCSection | 本地包 | ObjC 类/引用段提取 |

ECharts 通过 CDN 在 `WKWebView` 内加载，仅图表渲染时需要网络，**分析过程完全离线**。

---

## License

MIT
