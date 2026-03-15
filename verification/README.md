# 包体积数据验证目录

本目录**仅用于验证对齐**：放置 IPA、LinkMap 与期望结果，供 Cursor 或本地脚本做「包体积数据是否正确」的校验。  
**可单独上传到 GitHub**（项目源码目录不上传时，可只推送本目录到单独仓库或分支）。

## 目录结构

```
verification/
├── README.md                 # 本说明
├── VERIFICATION_RULES.md     # 验证规则与对齐标准
├── compare_analysis.swift    # 对比「实际分析结果」与「期望」的脚本（可云端运行）
├── ipa/                      # 放置待分析的 .ipa（可上传）
├── linkmap/                  # 放置对应的 LinkMap 文件（可上传）
├── expected/                 # 期望结果（手工填写或从一次正确分析导出）
│   └── expected_analysis.json
└── actual/                   # 当前分析导出结果（App 导出后放于此，用于对比）
    └── .gitkeep
```

## 使用流程

1. **准备数据**  
   - 将用于验证的 `.ipa` 放入 `ipa/`，对应的 LinkMap 文本放入 `linkmap/`。

2. **生成期望结果（首次或基准更新时）**  
   - 在 AppThinner 中：选择该 IPA + LinkMap + 工程目录，执行一次分析。  
   - 确认包体积、代码/资源/框架占比无误后，在应用内「导出」该分析项目。  
   - 将导出的 JSON 保存为 `expected/expected_analysis.json`（或按 VERIFICATION_RULES 中的字段整理）。

3. **日常验证**  
   - 在 App 中再次用同一份 IPA + LinkMap 做分析，导出到 `actual/`（例如 `actual/latest.json`）。  
   - 在项目根目录执行：  
     `swift verification/compare_analysis.swift expected/expected_analysis.json actual/latest.json`  
   - 脚本以退出码 0 表示对齐通过，非 0 表示不通过并打印差异。

4. **让 Cursor 自动修复与验证**  
   - 见项目根目录下 `doc/包体积验证与Cursor协同.md`：如何用本目录配合 Cursor 做「自动修复 + 验证对齐」。

## 可上传与不可上传

| 内容           | 是否可上传 |
|----------------|------------|
| 本目录（ipa、linkmap、expected、脚本） | ✅ 可上传 |
| 项目源码（AppThinnerAnalyzer 等）     | ❌ 按你要求不上传 |

若只希望把验证相关资产放到 GitHub：可新建仓库仅包含本 `verification/` 目录，或使用单独分支只推送该目录。
