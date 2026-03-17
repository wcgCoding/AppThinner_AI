## 外部数据导入样例模版

在你的场景下，**外部数据是通过埋点 / 上报系统拿到的：一份「无用类名列表」和一份「实际使用到的资源名列表」**。  
为了让 SKILL 能够利用这两类信息做交叉验证，这里给出一个推荐的 JSON 结构模版。

> 下述字段并非强制要求，SKILL 会按「能识别的字段尽量利用」的原则工作。

### 1. 顶层结构示例（按“类名 / 资源名”组织）

```jsonc
{
  "externalUnusedClasses": [
    {
      "className": "LiveHomeViewController",
      "reason": "线上埋点 30 天无实例化记录",
      "source": "analytics",       // 来源：analytics / manual_review / other
      "confidence": 0.9            // 0~1 置信度，越高表示越建议删除
    },
    {
      "className": "KTVRoomViewController",
      "reason": "业务线确认已下线",
      "source": "product_confirm",
      "confidence": 1.0
    }
  ],
  "externalUsedResources": [
    {
      "resourceName": "ic_live_entry",    // 逻辑资源名 / image name / key
      "reason": "线上埋点存在引用，不应当被误判为无用",
      "source": "analytics",
      "confidence": 0.95
    },
    {
      "resourceName": "bg_ksong_record",
      "reason": "录唱主流程强依赖",
      "source": "manual_review",
      "confidence": 1.0
    }
  ]
}
```

### 2. 推荐字段说明

- `className`：类名字符串（不含命名空间即可，例如 `LiveHomeViewController`）。  
  - SKILL 会尝试将其与 JSON / 工程中的类定义、`unusedCode` 项进行模糊匹配（例如按文件名、路径中是否包含该类名）。
- `resourceName`：资源逻辑名称，例如：
  - 图片的「image name」；
  - 音频的 key / 文件主名；
  - 其他资源在代码中的标识符。
  SKILL 会结合 `unusedResources.fileName`、相对路径和常见命名约定进行匹配。
- `reason`：外部系统对该条目的简要说明（例如「30 天无访问」「业务确认下线」「核心路径仍在使用」）。
- `source`：外部数据来源标记（如 `analytics` / `product_confirm` / `manual_review` / `tool_report`）。
- `confidence`：0~1 浮点数，用于在报告和任务清单中区分「强烈建议」与「仅供参考」。

### 3. SKILL 侧的典型使用方式

- **无用代码（unusedCode）交叉验证：**
  - 当 `unusedCode` 中的某个文件包含类名 `className`（按文件名/内容匹配）且该类出现在 `externalUnusedClasses` 中时：
    - 在报告中对该条目做「外部数据支持」高亮；
    - 在执行任务清单中为对应任务增加标签（例如 `tags: ["external_unused_class", "high_confidence"]`），优先推荐清理。

- **无用资源（unusedResources）误删保护：**
  - 当 `unusedResources` 中的某个资源文件名（去扩展名）出现在 `externalUsedResources.resourceName` 列表中时：
    - 在报告中标记为「外部数据认为仍在使用」；
    - 在执行任务清单中将该资源标记为「需人工复核」或直接从「明确删除」列表中剔除。

> 具体如何将外部数据文件路径或内容传入给 SKILL，由上层调用方约定（例如在对话中额外说明「请同时参考 /path/to/external-usage.json」）。本模版仅提供结构参考，方便在主页/说明文档中快速找到入口并复制使用。


