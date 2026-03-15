# Requirements Document

## Introduction

iOS应用包大小分析工具是一个专业的macOS应用程序，专门用于分析iOS应用的包大小分布、检测无用资源和代码，并提供优化建议。该工具支持离线本地分析，面向个人开发者，提供专业级的分析报告和优化功能。

## Glossary

- **App_Analyzer**: 主要的iOS应用包分析系统
- **Package_Parser**: 解析.ipa/.app文件的组件
- **Linkmap_Analyzer**: 分析linkmap.txt文件的组件
- **Resource_Scanner**: 扫描和分析资源文件的组件
- **Code_Analyzer**: 分析代码大小和无用代码的组件
- **Treemap_Generator**: 生成可交互treemap图表的组件
- **Report_Generator**: 生成HTML报告的组件
- **Optimizer**: 执行压缩和删除操作的组件
- **External_Data_Importer**: 导入外部无用资源和代码列表的组件
- **CoreData_Manager**: 管理本地数据存储的组件

## Requirements

### Requirement 1: 多源数据解析和映射

**User Story:** 作为iOS开发者，我希望能够导入.ipa/.app文件、linkmap.txt文件和项目目录，并将这些数据源的信息映射到统一的项目目录结构中进行分析。

#### Acceptance Criteria

1. WHEN用户拖拽或选择.ipa文件到应用中，THE Package_Parser SHALL解析文件结构并提取所有组件的大小信息
2. WHEN用户导入.app文件，THE Package_Parser SHALL分析应用包内容并识别所有资源和代码文件的实际大小
3. WHEN用户提供linkmap.txt文件，THE Linkmap_Analyzer SHALL解析符号信息并计算每个源文件对应的代码大小
4. WHEN用户选择项目目录，THE Resource_Scanner SHALL扫描项目结构并建立文件路径映射关系
5. THE App_Analyzer SHALL将linkmap中的代码大小、ipa中的资源大小、framework大小统一映射到项目目录结构中
6. THE App_Analyzer SHALL处理路径映射冲突并提供映射准确性报告

### Requirement 2: 基于项目目录的包大小分布可视化

**User Story:** 作为开发者，我希望看到以项目目录结构为基础的包大小分布图表，将linkmap、ipa资源和framework大小映射到对应的项目文件夹中。

#### Acceptance Criteria

1. WHEN分析完成后，THE Treemap_Generator SHALL以项目目录结构为基础生成交互式treemap图表
2. THE App_Analyzer SHALL将linkmap中的代码大小信息映射到对应的项目源文件目录
3. THE App_Analyzer SHALL将ipa中的资源文件大小映射到项目中对应的资源目录
4. THE App_Analyzer SHALL将framework大小信息关联到项目中引用的framework位置
5. WHEN用户点击treemap中的目录区块，THE App_Analyzer SHALL支持下钻查看子目录详情
6. WHEN鼠标悬停在图表区域，THE App_Analyzer SHALL显示项目路径、文件类型和实际包大小信息
7. THE App_Analyzer SHALL支持在深色模式和浅色模式下正确显示图表

### Requirement 3: 无用资源和代码检测

**User Story:** 作为开发者，我希望工具能够自动检测无用的资源和代码，同时支持导入外部提供的无用资源和代码列表，并在可视化图表中标识出来。

#### Acceptance Criteria

1. WHEN提供完整项目信息时，THE Resource_Scanner SHALL静态分析并识别未被引用的图片、音频等资源文件
2. WHEN有linkmap信息时，THE Code_Analyzer SHALL检测未被调用的类和方法
3. WHEN用户导入外部无用资源列表时，THE App_Analyzer SHALL合并外部列表与静态分析结果
4. WHEN用户导入外部无用代码类列表时，THE App_Analyzer SHALL整合外部数据与本地检测结果
5. THE App_Analyzer SHALL生成最终的无用资源列表并显示可节省的空间大小
6. THE App_Analyzer SHALL生成最终的无用代码列表并估算代码体积减少量
7. THE Treemap_Generator SHALL在主可视化图表中用不同颜色或标记突出显示无用资源和代码
8. WHEN检测到无用内容时，THE App_Analyzer SHALL提供详细的文件路径和建议操作

### Requirement 4: 优化处理功能

**User Story:** 作为开发者，我希望工具能够直接执行优化操作，包括压缩图片和删除无用文件。

#### Acceptance Criteria

1. WHEN用户选择压缩图片时，THE Optimizer SHALL使用无损压缩算法减少图片文件大小
2. WHEN用户确认删除无用资源时，THE Optimizer SHALL安全删除选定的无用文件
3. WHEN用户选择删除无用代码时，THE Optimizer SHALL移除未使用的类和方法（仅限源码项目）
4. THE Optimizer SHALL在执行任何删除操作前创建备份
5. THE App_Analyzer SHALL显示优化前后的大小对比和节省空间统计

### Requirement 5: HTML报告生成

**User Story:** 作为开发者，我希望能够导出详细的分析报告，以便与团队分享或存档。

#### Acceptance Criteria

1. WHEN分析完成后，THE Report_Generator SHALL生成包含所有分析结果的HTML报告
2. THE Report_Generator SHALL在报告中包含treemap图表的静态版本
3. THE Report_Generator SHALL列出所有检测到的无用资源和代码清单
4. THE Report_Generator SHALL包含优化建议和预期节省空间的统计信息
5. THE Report_Generator SHALL生成专业格式的报告，支持打印和在线分享

### Requirement 6: 数据持久化

**User Story:** 作为开发者，我希望工具能够保存分析历史，以便对比不同版本的包大小变化。

#### Acceptance Criteria

1. THE CoreData_Manager SHALL保存每次分析的完整结果到本地数据库
2. WHEN用户重新打开应用时，THE App_Analyzer SHALL显示历史分析记录列表
3. THE App_Analyzer SHALL支持对比不同版本的分析结果
4. THE CoreData_Manager SHALL支持导出和导入分析数据
5. THE App_Analyzer SHALL提供清理旧数据的功能以管理存储空间

### Requirement 7: 用户界面和体验

**User Story:** 作为开发者，我希望使用专业、直观的界面进行包大小分析工作。

#### Acceptance Criteria

1. THE App_Analyzer SHALL提供符合macOS设计规范的专业界面风格
2. THE App_Analyzer SHALL完全支持macOS深色模式和浅色模式
3. WHEN执行耗时操作时，THE App_Analyzer SHALL显示进度指示器和当前操作状态
4. THE App_Analyzer SHALL支持拖拽文件到应用窗口进行快速导入
5. THE App_Analyzer SHALL提供键盘快捷键支持常用操作

### Requirement 8: 系统兼容性

**User Story:** 作为macOS用户，我希望工具能够在我的Apple Silicon Mac上稳定运行。

#### Acceptance Criteria

1. THE App_Analyzer SHALL仅支持macOS 14.0及以上版本
2. THE App_Analyzer SHALL原生支持Apple Silicon处理器并优化性能
3. THE App_Analyzer SHALL使用SwiftUI框架构建用户界面
4. THE App_Analyzer SHALL使用CoreData进行本地数据管理
5. THE App_Analyzer SHALL遵循macOS安全和隐私要求，仅访问用户授权的文件