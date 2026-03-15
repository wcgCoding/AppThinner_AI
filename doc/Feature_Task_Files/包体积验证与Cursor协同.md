# 包体积验证与 Cursor 协同

在**项目目录不能上传 GitHub、但 IPA 与 LinkMap 可以上传**的前提下，让 Cursor 在本地或云端参与「自动修复 + 验证对齐」的推荐做法。

## 1. 你能怎么做

### 方案 A：仅验证目录单独建库（推荐）

- 新建一个**仅包含验证资产**的 Git 仓库（例如 `AppThinner-verification`）。
- 把当前项目里的 **`verification/` 目录**整份拷贝到新仓库根目录（包含 `ipa/`、`linkmap/`、`expected/`、`compare_analysis.swift`、README 与 VERIFICATION_RULES）。
- 该仓库可以上传到 GitHub；**不包含** AppThinner 源码，只包含：
  - 可上传的 IPA、LinkMap
  - 期望结果 `expected/expected_analysis.json`
  - 对比脚本 `compare_analysis.swift`
  - 说明文档（README、VERIFICATION_RULES）

这样：**项目目录不上传，IPA/LinkMap 可上传**，且 Cursor 在打开该验证库时也能看到规则和脚本。

### 方案 B：本地项目 + 验证目录（Cursor 本地修复）

- 保持完整 AppThinner 项目在本地，**不**推送到 GitHub。
- 在项目内保留并维护 `verification/`（同上：ipa、linkmap、expected、脚本）。
- 在 Cursor 里**打开本地项目**，让 Cursor 读：
  - `verification/VERIFICATION_RULES.md`：何为「对齐」
  - `verification/expected/expected_analysis.json`：期望数值
  - `doc/无用扫描与LinkMap匹配逻辑说明.md`、`doc/核心数据解析及映射说明.md`：数据流与匹配逻辑
- 每次改完分析逻辑后：
  1. 在 App 里用 `verification/ipa`、`verification/linkmap` 再跑一次分析；
  2. 导出结果到 `verification/actual/latest.json`；
  3. 执行：  
     `swift verification/compare_analysis.swift verification/expected/expected_analysis.json verification/actual/latest.json`
  4. 把脚本输出（通过/失败）贴给 Cursor，让 Cursor 根据失败项继续改代码，直到脚本通过。

这样 Cursor **在本地**完成「修复 → 你跑分析 → 你跑脚本 → 再修复」的循环，无需云端代码库。

### 方案 C：云端只用验证库做「标准」定义

- 验证库（方案 A）上传到 GitHub，用于存放**唯一真相**：  
  正确 IPA、LinkMap、期望 JSON、验证规则。
- 你在本地开发时：
  - 要么把验证库 clone 到本机，把其中的 `verification/` 拷进 AppThinner 项目；
  - 要么在 AppThinner 里通过文档/规则手填 `expected`，与验证库里的 expected 保持一致。
- Cursor 打开**本地 AppThinner** 时，通过 `verification/` 和 `doc/` 下的说明理解「何谓对齐」并修复；  
  云端只看到验证库，不看到你私有项目代码。

## 2. 建议的下一步

1. **先落一份「正确」期望**  
   用当前（或修正后）的 App，对**同一份** IPA + LinkMap 做一次分析，确认界面/报告上的包体积、代码/资源/框架占比都正确后，导出该分析结果为 JSON，保存为 `verification/expected/expected_analysis.json`（可删敏感字段，只留 `totalSize`、`summaryCodeSize`、`summaryResourceSize`、`summaryFrameworkSize`）。

2. **固定验证命令**  
   在项目根执行一次：  
   `swift verification/compare_analysis.swift verification/expected/expected_analysis.json verification/actual/latest.json`  
   确认脚本能跑、通过/失败符合预期。之后每次改分析逻辑都跑同一条命令。

3. **把验证流程交给 Cursor**  
   在 Cursor 里可以这样说：  
   「用 `verification/` 下的 IPA 和 LinkMap 做分析，导出到 `verification/actual/latest.json`，然后运行 `verification/compare_analysis.swift`；若不通过，根据 VERIFICATION_RULES 和 核心数据解析及映射说明 修改分析逻辑直到通过。」  
   Cursor 会依赖你本地的 `verification/` 与 `doc/` 做修改，无需访问 GitHub 上的私有项目。

4. **（可选）验证库单独建库并上传**  
   按方案 A 建 `AppThinner-verification` 并推送到 GitHub，以后任何环境（包括 Cursor 云端打开该库）都能用同一套 IPA、LinkMap、expected 和脚本做「标准」校验；实际修代码仍在本地私有项目里完成。

## 3. 小结

| 目标               | 做法 |
|--------------------|------|
| 项目目录不上传     | 仅推送验证库或仅推送 `verification/` 目录。 |
| IPA/LinkMap 可上传 | 放在 `verification/ipa/`、`verification/linkmap/`。 |
| Cursor 自动修复验证 | 本地打开项目，用验证脚本驱动「改代码 → 跑分析 → 跑脚本」循环；或云端只开验证库做标准定义，修代码在本地。 |
| 对齐标准           | 由 `VERIFICATION_RULES.md` 和 `expected_analysis.json` 定义；脚本 `compare_analysis.swift` 做数值对比。 |

按上述任选一种或组合使用即可在「不传项目、可传 IPA/LinkMap」的前提下，用 Cursor 做包体积数据的修复与验证对齐。
