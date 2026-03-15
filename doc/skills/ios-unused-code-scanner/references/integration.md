# Integration Guide

## 概述

本指南介绍如何将iOS无用代码扫描器集成到各种开发工具和CI/CD流程中。

---

## CI/CD集成

### GitHub Actions

在 `.github/workflows/unused-scan.yml` 中添加:

```yaml
name: iOS Unused Code Scan

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]
  schedule:
    # 每周一凌晨2点执行
    - cron: '0 2 * * 1'

jobs:
  scan:
    runs-on: macos-latest

    steps:
    - name: Checkout代码
      uses: actions/checkout@v3

    - name: 设置Python环境
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'

    - name: 安装依赖
      run: |
        cd Script/unused_code_scanner_skill
        pip3 install -r requirements.txt

    - name: 执行扫描
      run: |
        cd Script/unused_code_scanner_skill
        ./scripts/run_scan.sh --project ${{ github.workspace }} --quick

    - name: 上传报告
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: unused-scan-results
        path: Script/unused_code_scanner_skill/unused_scan_results/

    - name: 检查阈值
      run: |
        cd Script/unused_code_scanner_skill
        python3 examples/ci_integration.py ${{ github.workspace }} 100

    - name: 评论PR
      if: github.event_name == 'pull_request'
      uses: actions/github-script@v6
      with:
        script: |
          const fs = require('fs');
          const summaryPath = 'Script/unused_code_scanner_skill/unused_scan_results/scan_summary.json';
          if (fs.existsSync(summaryPath)) {
            const summary = JSON.parse(fs.readFileSync(summaryPath, 'utf8'));
            const comment = `## 🔍 无用代码扫描结果

            - **无用类**: ${summary.unused_classes_count}
            - **无用方法**: ${summary.unused_methods_count}
            - **无用资源**: ${summary.unused_resources_count}
            - **总计**: ${summary.total_unused_items}
            - **可节省空间**: ${(summary.total_size_bytes / 1024).toFixed(2)} KB

            查看详细报告请下载构建产物。`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: comment
            });
          }
```

---

### Jenkins Pipeline

在 `Jenkinsfile` 中添加:

```groovy
pipeline {
    agent { label 'macos' }

    environment {
        SCAN_OUTPUT = 'unused_scan_results'
        THRESHOLD = '100'
    }

    stages {
        stage('环境准备') {
            steps {
                sh '''
                    cd Script/unused_code_scanner_skill
                    pip3 install -r requirements.txt
                '''
            }
        }

        stage('代码扫描') {
            steps {
                sh '''
                    cd Script/unused_code_scanner_skill
                    ./scripts/run_scan.sh --project ${WORKSPACE} --quick
                '''
            }
        }

        stage('生成报告') {
            steps {
                publishHTML([
                    allowMissing: false,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: "Script/unused_code_scanner_skill/${SCAN_OUTPUT}",
                    reportFiles: 'unused_scan_report.html',
                    reportName: 'Unused Code Report'
                ])
            }
        }

        stage('质量门禁') {
            steps {
                script {
                    def exitCode = sh(
                        script: """
                            cd Script/unused_code_scanner_skill
                            python3 examples/ci_integration.py ${WORKSPACE} ${THRESHOLD}
                        """,
                        returnStatus: true
                    )

                    if (exitCode != 0) {
                        unstable("发现过多无用代码，超过阈值${THRESHOLD}")
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: "Script/unused_code_scanner_skill/${SCAN_OUTPUT}/**/*",
                             allowEmptyArchive: true
        }

        success {
            echo '✅ 扫描完成，代码质量良好'
        }

        unstable {
            echo '⚠️ 扫描完成，建议清理无用代码'
        }
    }
}
```

---

### GitLab CI

在 `.gitlab-ci.yml` 中添加:

```yaml
unused_code_scan:
  stage: test
  tags:
    - macos

  before_script:
    - cd Script/unused_code_scanner_skill
    - pip3 install -r requirements.txt

  script:
    - ./scripts/run_scan.sh --project $CI_PROJECT_DIR --quick
    - python3 examples/ci_integration.py $CI_PROJECT_DIR 100

  artifacts:
    when: always
    paths:
      - Script/unused_code_scanner_skill/unused_scan_results/
    reports:
      junit: Script/unused_code_scanner_skill/unused_scan_results/junit.xml
    expire_in: 30 days

  only:
    - merge_requests
    - main
    - develop

# 定期扫描
unused_code_scan_scheduled:
  extends: unused_code_scan
  only:
    - schedules
  script:
    - cd Script/unused_code_scanner_skill
    - ./scripts/run_scan.sh --project $CI_PROJECT_DIR --full
```

---

## Fastlane集成

### 基本集成

在 `Fastfile` 中添加:

```ruby
lane :scan_unused_code do |options|
  project_path = options[:project_path] || Dir.pwd
  output_dir = options[:output_dir] || "unused_scan_results"
  threshold = options[:threshold] || 100

  UI.message "🔍 开始扫描无用代码..."

  sh("cd Script/unused_code_scanner_skill && ./scripts/run_scan.sh --project #{project_path}")

  # 读取扫描结果
  summary_file = "Script/unused_code_scanner_skill/#{output_dir}/scan_summary.json"
  if File.exist?(summary_file)
    summary = JSON.parse(File.read(summary_file))
    total_unused = summary["total_unused_items"]

    UI.success "✅ 扫描完成"
    UI.message "   - 无用类: #{summary['unused_classes_count']}"
    UI.message "   - 无用方法: #{summary['unused_methods_count']}"
    UI.message "   - 无用资源: #{summary['unused_resources_count']}"
    UI.message "   - 总计: #{total_unused}"

    if total_unused > threshold
      UI.important "⚠️  发现 #{total_unused} 个无用项，超过阈值 #{threshold}"
      UI.important "   建议清理无用代码以提高代码质量"
    end
  else
    UI.error "❌ 未找到扫描结果文件"
  end
end

# 集成到发布流程
lane :release do
  # 扫描无用代码
  scan_unused_code(threshold: 50)

  # 构建
  build_app

  # 其他发布步骤...
end
```

### 高级集成

```ruby
lane :quality_check do
  # 运行完整扫描
  sh("cd Script/unused_code_scanner_skill && ./scripts/run_scan.sh --full")

  # 解析结果
  summary = parse_scan_summary

  # 发送通知
  send_scan_notification(summary)

  # 生成趋势报告
  track_scan_trends(summary)
end

private_lane :parse_scan_summary do
  summary_file = "Script/unused_code_scanner_skill/unused_scan_results/scan_summary.json"
  JSON.parse(File.read(summary_file))
end

private_lane :send_scan_notification do |summary|
  # 发送到Slack
  slack(
    message: "iOS无用代码扫描完成",
    success: summary["total_unused_items"] < 100,
    payload: {
      "无用类" => summary["unused_classes_count"],
      "无用方法" => summary["unused_methods_count"],
      "无用资源" => summary["unused_resources_count"],
      "总计" => summary["total_unused_items"]
    }
  )
end
```

---

## Xcode集成

### Build Phase集成

1. 在Xcode项目中选择Target
2. 选择 "Build Phases"
3. 点击 "+" 添加 "New Run Script Phase"
4. 添加以下脚本:

```bash
#!/bin/bash

# 仅在Debug配置下运行
if [ "${CONFIGURATION}" = "Debug" ]; then
    SCANNER_PATH="${SRCROOT}/Script/unused_code_scanner_skill"

    if [ -d "${SCANNER_PATH}" ]; then
        echo "🔍 运行无用代码扫描..."
        cd "${SCANNER_PATH}"
        ./scripts/run_scan.sh --project "${SRCROOT}" --quick

        # 检查结果
        SUMMARY_FILE="${SCANNER_PATH}/unused_scan_results/scan_summary.json"
        if [ -f "${SUMMARY_FILE}" ]; then
            TOTAL=$(python3 -c "import json; print(json.load(open('${SUMMARY_FILE}'))['total_unused_items'])")
            echo "📊 发现 ${TOTAL} 个无用项"

            if [ ${TOTAL} -gt 100 ]; then
                echo "⚠️  警告: 无用项较多，建议清理"
            fi
        fi
    fi
fi
```

### Xcode Scheme集成

在 Scheme 的 Pre-actions 或 Post-actions 中添加:

```bash
cd "${SRCROOT}/Script/unused_code_scanner_skill"
./scripts/run_scan.sh --project "${SRCROOT}" --quick
open unused_scan_results/unused_scan_report.html
```

---

## Pre-commit Hook集成

在 `.git/hooks/pre-commit` 中添加:

```bash
#!/bin/bash

echo "🔍 运行无用代码扫描..."

cd Script/unused_code_scanner_skill
./scripts/run_scan.sh --quick

if [ $? -ne 0 ]; then
    echo "❌ 扫描失败"
    exit 1
fi

# 检查是否有新增无用代码
SUMMARY_FILE="unused_scan_results/scan_summary.json"
if [ -f "${SUMMARY_FILE}" ]; then
    TOTAL=$(python3 -c "import json; print(json.load(open('${SUMMARY_FILE}'))['total_unused_items'])")

    if [ ${TOTAL} -gt 150 ]; then
        echo "❌ 无用代码过多 (${TOTAL} 个)，请先清理后再提交"
        exit 1
    fi
fi

echo "✅ 扫描通过"
exit 0
```

---

## VSCode集成

在 `.vscode/tasks.json` 中添加:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "iOS: 扫描无用代码",
            "type": "shell",
            "command": "cd Script/unused_code_scanner_skill && ./scripts/run_scan.sh",
            "problemMatcher": [],
            "presentation": {
                "reveal": "always",
                "panel": "new"
            }
        },
        {
            "label": "iOS: 查看扫描报告",
            "type": "shell",
            "command": "open Script/unused_code_scanner_skill/unused_scan_results/unused_scan_report.html",
            "problemMatcher": []
        }
    ]
}
```

在 `.vscode/settings.json` 中添加:

```json
{
    "files.watcherExclude": {
        "**/Script/unused_code_scanner_skill/unused_scan_results/**": true
    }
}
```

---

## Docker集成

创建 `Dockerfile`:

```dockerfile
FROM python:3.9-slim

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /scanner

# 复制Skill文件
COPY Script/unused_code_scanner_skill /scanner

# 安装Python依赖
RUN pip3 install -r requirements.txt

# 设置入口点
ENTRYPOINT ["./scripts/run_scan.sh"]
```

使用方式:

```bash
# 构建镜像
docker build -t ios-unused-scanner .

# 运行扫描
docker run -v /path/to/ios/project:/project \
           ios-unused-scanner --project /project
```

---

## Webhook集成

### 接收扫描结果

```python
from flask import Flask, request, jsonify
import json

app = Flask(__name__)

@app.route('/webhook/scan-complete', methods=['POST'])
def scan_complete():
    data = request.json

    # 处理扫描结果
    total_unused = data.get('total_unused_items', 0)

    # 发送通知
    if total_unused > 100:
        send_alert(data)

    # 保存历史数据
    save_scan_history(data)

    return jsonify({'status': 'ok'})

if __name__ == '__main__':
    app.run(port=5000)
```

### 触发扫描

```bash
# 在扫描完成后调用webhook
curl -X POST https://your-server.com/webhook/scan-complete \
     -H "Content-Type: application/json" \
     -d @unused_scan_results/scan_summary.json
```

---

## 最佳实践

### 1. 定期扫描

- 每日构建时运行快速扫描
- 每周运行完整扫描
- PR合并前运行扫描

### 2. 阈值设置

- 小型项目: 50个无用项
- 中型项目: 100个无用项
- 大型项目: 200个无用项

### 3. 白名单管理

- 将必要但未使用的代码加入白名单
- 定期审查白名单
- 记录白名单原因

### 4. 报告存档

- 保留历史扫描报告
- 追踪趋势变化
- 定期清理旧报告

---

## 故障排查

### 常见问题

1. **权限问题**
   ```bash
   chmod +x scripts/*.sh
   ```

2. **Python依赖缺失**
   ```bash
   pip3 install -r requirements.txt
   ```

3. **扫描超时**
   - 使用 `--quick` 模式
   - 增加timeout配置

4. **内存不足**
   - 调整 `memory_limit_mb` 配置
   - 分批扫描大型项目

---

## 更多资源

- [API文档](api.md)
- [最佳实践](best_practices.md)
- [README](../README.md)
