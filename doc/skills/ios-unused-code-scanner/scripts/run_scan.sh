#!/bin/bash

# iOS无用代码及资源扫描Agent Skill - 运行脚本
# 版本: 1.0.0
# 创建时间: 2024-01-25

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_NAME="iOS无用代码及资源扫描工具"
VERSION="1.0.0"
AUTHOR="AI Assistant"

# 路径配置（脚本在 scripts/ 下，skill 根目录为上一级）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCANNER_SCRIPT="$SKILL_ROOT/scripts/scanner.py"
CONFIG_FILE="$SKILL_ROOT/assets/default.json"

# 默认配置（CONFIG_FILE 已在顶部设为 skill 的 assets/default.json，此处不覆盖）
PROJECT_ROOT="."
OUTPUT_DIR="unused_scan_results"
SCAN_TYPE="all"
REPORT_FORMATS=("html" "csv" "json")

# 显示帮助信息
show_help() {
    cat << EOF
${CYAN}${SCRIPT_NAME} v${VERSION}${NC}

${GREEN}用途：${NC}
    扫描iOS项目中的无用代码和资源文件，生成详细的HTML和CSV报告

${GREEN}语法：${NC}
    $0 [选项] [项目路径]

${GREEN}选项：${NC}
    -h, --help          显示此帮助信息
    -v, --version       显示版本信息
    -c, --config FILE   指定配置文件路径（默认: ${CONFIG_FILE}）
    -o, --output DIR    指定输出目录（默认: ${OUTPUT_DIR}）
    -p, --project DIR   指定项目根目录（默认: 当前目录）
    --code-only         仅扫描无用代码
    --resource-only     仅扫描无用资源
    --quick             快速扫描模式（跳过详细引用分析）
    --full              完整扫描模式（包含所有分析）
    --clean             清理之前的扫描结果
    --open-report       扫描完成后自动打开HTML报告
    --formats FORMATS   报告格式（html,csv,json，默认: html,csv,json）
    --no-html           不生成HTML报告
    --no-csv            不生成CSV报告
    --no-json           不生成JSON汇总
    --verbose           详细输出模式
    --quiet             静默模式
    --debug             调试模式

${GREEN}示例：${NC}
    $0                           # 扫描当前目录下的iOS项目
    $0 /path/to/ios/project     # 扫描指定路径的iOS项目
    $0 --code-only              # 仅扫描无用代码
    $0 --resource-only          # 仅扫描无用资源
    $0 --quick                  # 快速扫描
    $0 --full                   # 完整扫描
    $0 --clean                  # 清理结果后重新扫描
    $0 --open-report            # 扫描后自动打开报告
    $0 --formats html,csv       # 仅生成HTML和CSV报告
    $0 --verbose                # 详细输出

${GREEN}输出文件：${NC}
    • unused_scan_report.html    - HTML格式的详细报告
    • unused_scan_report.csv    - CSV格式的数据报告
    • scan_summary.json          - JSON格式的汇总统计

${YELLOW}注意：${NC}
    • 确保Python 3.6+已安装
    • 扫描大型项目可能需要较长时间
    • 建议在CI/CD流程中集成使用
EOF
}

# 显示版本信息
show_version() {
    echo -e "${CYAN}${SCRIPT_NAME} v${VERSION}${NC}"
    echo -e "作者: ${AUTHOR}"
    echo -e "Skill根目录: ${SKILL_ROOT}"
}

# 检查依赖
check_dependencies() {
    echo -e "${BLUE}🔍 检查系统依赖...${NC}"
    
    # 检查Python
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}❌ 错误: 未找到Python 3，请先安装Python 3.6+${NC}"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    echo -e "${GREEN}✅ Python版本: ${PYTHON_VERSION}${NC}"
    
    # 检查扫描脚本
    if [[ ! -f "${SCANNER_SCRIPT}" ]]; then
        echo -e "${RED}❌ 错误: 扫描脚本不存在: ${SCANNER_SCRIPT}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ 扫描脚本: ${SCANNER_SCRIPT}${NC}"
    
    # 检查配置文件
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${YELLOW}⚠️  警告: 配置文件不存在: ${CONFIG_FILE}${NC}"
        echo -e "${YELLOW}将使用默认配置${NC}"
    else
        echo -e "${GREEN}✅ 配置文件: ${CONFIG_FILE}${NC}"
    fi
}

# 清理之前的扫描结果
clean_previous_results() {
    echo -e "${BLUE}🧹 清理之前的扫描结果...${NC}"
    
    if [[ -d "${OUTPUT_DIR}" ]]; then
        rm -rf "${OUTPUT_DIR}"
        echo -e "${GREEN}✅ 已清理输出目录: ${OUTPUT_DIR}${NC}"
    else
        echo -e "${YELLOW}ℹ️  输出目录不存在，无需清理${NC}"
    fi
}

# 显示扫描配置
show_scan_config() {
    echo -e "${CYAN}📋 扫描配置：${NC}"
    echo -e "  ${BLUE}•${NC} 项目路径: ${PROJECT_ROOT}"
    echo -e "  ${BLUE}•${NC} 输出目录: ${OUTPUT_DIR}"
    echo -e "  ${BLUE}•${NC} 扫描模式: ${SCAN_TYPE}"
    echo -e "  ${BLUE}•${NC} 报告格式: ${REPORT_FORMATS[*]}"
    if [[ -n "$CONFIG_FILE" ]]; then
        echo -e "  ${BLUE}•${NC} 配置文件: ${CONFIG_FILE}"
    fi
    echo -e "  ${BLUE}•${NC} 扫描脚本: ${SCANNER_SCRIPT}"
    echo -e ""
}

# 运行扫描
run_scan() {
    local scan_args=("${SCANNER_SCRIPT}" "${PROJECT_ROOT}" "-o" "${OUTPUT_DIR}")
    
    # 添加配置文件参数
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        scan_args+=("--config" "$CONFIG_FILE")
    fi
    
    # 根据扫描模式添加参数（与 scanner.py --scan-type 对应）
    case "${SCAN_TYPE}" in
        "code-only")
            scan_args+=("--scan-type" "code")
            ;;
        "resource-only")
            scan_args+=("--scan-type" "resources")
            ;;
        "quick")
            # 快速模式暂与 all 一致，scanner 未实现 --quick
            scan_args+=("--scan-type" "all")
            ;;
        "full")
            scan_args+=("--scan-type" "all")
            ;;
    esac
    
    # 添加报告格式参数
    if [[ ${#REPORT_FORMATS[@]} -gt 0 ]]; then
        scan_args+=("--formats" $(IFS=,; echo "${REPORT_FORMATS[*]}"))
    fi
    
    # 添加详细级别
    if [[ "$VERBOSE" == "true" ]]; then
        scan_args+=("--verbose")
    elif [[ "$DEBUG" == "true" ]]; then
        scan_args+=("--debug")
    elif [[ "$QUIET" == "true" ]]; then
        scan_args+=("--quiet")
    fi
    
    echo -e "${BLUE}🚀 开始扫描...${NC}"
    echo -e "${YELLOW}命令: python3 ${scan_args[*]}${NC}"
    echo -e "${YELLOW}这可能需要几分钟时间，请耐心等待...${NC}"
    echo -e ""
    
    # 执行扫描
    if python3 "${scan_args[@]}"; then
        echo -e "${GREEN}✅ 扫描完成！${NC}"
        return 0
    else
        echo -e "${RED}❌ 扫描失败！${NC}"
        return 1
    fi
}

# 显示扫描结果
show_results() {
    local html_report="${OUTPUT_DIR}/unused_scan_report.html"
    local csv_report="${OUTPUT_DIR}/unused_scan_report.csv"
    local summary_file="${OUTPUT_DIR}/scan_summary.json"
    
    echo -e "${CYAN}📊 扫描结果：${NC}"
    
    if [[ -f "${summary_file}" ]]; then
        local total_items=$(python3 -c "import json; data=json.load(open('${summary_file}')); print(data.get('total_unused_items', 0))" 2>/dev/null || echo "0")
        local unused_classes=$(python3 -c "import json; data=json.load(open('${summary_file}')); print(data.get('unused_classes', 0))" 2>/dev/null || echo "0")
        local unused_methods=$(python3 -c "import json; data=json.load(open('${summary_file}')); print(data.get('unused_methods', 0))" 2>/dev/null || echo "0")
        local unused_images=$(python3 -c "import json; data=json.load(open('${summary_file}')); print(data.get('unused_images', 0))" 2>/dev/null || echo "0")
        local total_size=$(python3 -c "import json; data=json.load(open('${summary_file}')); print(data.get('total_size_bytes', 0))" 2>/dev/null || echo "0")
        
        echo -e "  ${GREEN}•${NC} 总共发现无用项目: ${total_items}"
        echo -e "  ${GREEN}•${NC} 无用类: ${unused_classes}"
        echo -e "  ${GREEN}•${NC} 无用方法: ${unused_methods}"
        echo -e "  ${GREEN}•${NC} 无用图片: ${unused_images}"
        echo -e "  ${GREEN}•${NC} 总大小: $(numfmt --to=iec ${total_size} 2>/dev/null || echo ${total_size} B)"
    else
        echo -e "  ${YELLOW}⚠️  汇总文件不存在${NC}"
    fi
    
    echo -e ""
    echo -e "${CYAN}📁 生成的文件：${NC}"
    
    if [[ -f "${html_report}" ]]; then
        echo -e "  ${GREEN}•${NC} HTML报告: ${html_report}"
    else
        echo -e "  ${RED}•${NC} HTML报告: 未生成"
    fi
    
    if [[ -f "${csv_report}" ]]; then
        echo -e "  ${GREEN}•${NC} CSV报告: ${csv_report}"
    else
        echo -e "  ${RED}•${NC} CSV报告: 未生成"
    fi
    
    if [[ -f "${summary_file}" ]]; then
        echo -e "  ${GREEN}•${NC} 汇总统计: ${summary_file}"
    else
        echo -e "  ${RED}•${NC} 汇总统计: 未生成"
    fi
    
    echo -e ""
}

# 打开报告
open_report() {
    local html_report="${OUTPUT_DIR}/unused_scan_report.html"
    
    if [[ "${OPEN_REPORT}" == "true" && -f "${html_report}" ]]; then
        echo -e "${BLUE}🌐 正在打开HTML报告...${NC}"
        
        if command -v open &> /dev/null; then
            # macOS
            open "${html_report}"
        elif command -v xdg-open &> /dev/null; then
            # Linux
            xdg-open "${html_report}"
        elif command -v start &> /dev/null; then
            # Windows (WSL)
            start "${html_report}"
        else
            echo -e "${YELLOW}⚠️  无法自动打开报告，请手动打开: ${html_report}${NC}"
        fi
    fi
}

# 主函数
main() {
    # 默认参数
    local CLEAN_RESULTS=false
    local OPEN_REPORT=false
    local VERBOSE=false
    local QUIET=false
    local DEBUG=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_ROOT="$(cd "$2" && pwd)"
                shift 2
                ;;
            --code-only)
                SCAN_TYPE="code-only"
                shift
                ;;
            --resource-only)
                SCAN_TYPE="resource-only"
                shift
                ;;
            --quick)
                SCAN_TYPE="quick"
                shift
                ;;
            --full)
                SCAN_TYPE="full"
                shift
                ;;
            --clean)
                CLEAN_RESULTS=true
                shift
                ;;
            --open-report)
                OPEN_REPORT=true
                shift
                ;;
            --formats)
                IFS=',' read -ra REPORT_FORMATS <<< "$2"
                shift 2
                ;;
            --no-html)
                REPORT_FORMATS=(${REPORT_FORMATS[@]/html/})
                shift
                ;;
            --no-csv)
                REPORT_FORMATS=(${REPORT_FORMATS[@]/csv/})
                shift
                ;;
            --no-json)
                REPORT_FORMATS=(${REPORT_FORMATS[@]/json/})
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            -*)
                echo -e "${RED}❌ 错误: 未知选项 $1${NC}"
                show_help
                exit 1
                ;;
            *)
                PROJECT_ROOT="$(cd "$1" && pwd)"
                shift
                ;;
        esac
    done
    
    # 显示标题
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         ${SCRIPT_NAME} v${VERSION}${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e ""
    
    # 检查依赖
    check_dependencies
    echo -e ""
    
    # 清理结果（如果需要）
    if [[ "${CLEAN_RESULTS}" == "true" ]]; then
        clean_previous_results
        echo -e ""
    fi
    
    # 显示配置
    show_scan_config
    
    # 运行扫描
    if run_scan; then
        echo -e ""
        show_results
        echo -e ""
        open_report
        echo -e "${GREEN}🎉 扫描流程完成！${NC}"
    else
        echo -e ""
        echo -e "${RED}❌ 扫描流程失败！${NC}"
        exit 1
    fi
}

# 运行主函数
main "$@"