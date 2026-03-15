# 包体积数据验证规则

用于判断「当前分析结果」与「期望」是否对齐，供脚本与 Cursor 使用。

## 1. 对比维度

与 `expected_analysis.json` 对比时，至少校验以下字段（与 App 导出 JSON 一致）：

| 字段 | 说明 | 容差建议 |
|------|------|----------|
| `totalSize` | 包总体积（字节） | 可与 IPA 解压后 Payload/*.app 总大小一致，容差 0 或 ±少量（如 0.1%） |
| `summaryCodeSize` | 来自 LinkMap 的代码体积汇总 | 与 LinkMap 解析得到的 .o 体积之和一致，容差 0 |
| `summaryResourceSize` | 资源体积 | 与 .app 内资源文件累加一致，可设 ±1% |
| `summaryFrameworkSize` | 框架/动态库体积 | 与 .app 内 Frameworks 等一致，可设 ±1% |

可选：`analysisResults` 或文件条数、关键路径的 codeSize 是否与 LinkMap 中对应 .o 一致。

## 2. 期望文件格式（expected_analysis.json）

与 CoreData 导出格式一致，至少包含：

```json
{
  "totalSize": 123456789,
  "summaryCodeSize": 45678901,
  "summaryResourceSize": 23456789,
  "summaryFrameworkSize": 54321098
}
```

若使用完整导出 JSON，可包含 `name`、`ipaPath`、`linkmapPath` 等；对比脚本只取上述数值字段。

## 3. 如何得到「正确」的期望值

- **totalSize**：解压 IPA，对 `Payload/*.app` 做递归 `du -sk` 或 Finder 显示「计算所有大小」，或与 Xcode Organizer 中包体积一致。  
- **summaryCodeSize**：由 LinkMap 的 `# Object files` + `# Symbols` 解析后，对所有 .o 的 totalSize 求和。  
- **summaryResourceSize / summaryFrameworkSize**：由 .app 内非可执行文件、Frameworks 等分别累加得到。

一次在 App 中分析无误后，用该次导出的 JSON 作为 expected，即可作为后续对比基准。

## 4. 路径与匹配

- 验证时使用**同一份** IPA 与 LinkMap；工程路径若不同机器不一致，可只对比汇总值（totalSize / summary*），不对比单文件路径。  
- 若需验证「无用代码/资源与 LinkMap 匹配」是否正确，可在 expected 中增加样例路径及其 codeSize，脚本中增加对应断言。
