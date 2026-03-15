# AppThinner 分析 Skill 参考

## 使用方式

- **项目内**：将本目录复制到 `.cursor/skills/app-thinner-analysis/` 即可在 Cursor 中作为项目 Skill 使用。  
- **个人全局**：复制到 `~/.cursor/skills/app-thinner-analysis/` 可在所有项目中使用。

## 与 Mac App 逻辑复用方案

详见仓库根目录下：

- **`doc/AppThinner_SKILL_与MacApp逻辑复用方案.md`**

要点：

- **方案 A**：抽出 AppThinnerCore Swift Package + CLI，Mac App 与 Skill（通过调用 CLI）共用同一套解析与差集逻辑，复用度最高。  
- **方案 B**：仅用脚本 + 文档复现同一方法论，Skill 按步骤执行脚本并与 App 结果对照。  
- **方案 C**：先 B 后 A，先落地 Skill 与脚本，再逐步迁移到 Core + CLI。

## 关键代码位置（Mac App）

| 逻辑         | 文件 |
|--------------|------|
| LinkMap 解析 | `AppThinnerAnalyzer/Services/LinkmapAnalyzer.swift` |
| 无用类差集   | `AppThinnerAnalyzer/Services/BinaryUnusedCodeAnalyzer.swift` |
| 无用结果编排 | `AppThinnerAnalyzer/Services/AnalysisService.swift`（buildUnusedContentResults） |
| 数据模型     | `AppThinnerAnalyzer/Models/DataModels.swift`（UnusedCode、CodeSizeInfo 等） |

## 校验脚本（若已提供）

- 使用 otool/nm 做无用类校验时，可参考方案文档中的命令与 `scripts/` 下脚本（如 otool_unused_class_validator.sh），注意 classlist 可能在 `__DATA_CONST`。
