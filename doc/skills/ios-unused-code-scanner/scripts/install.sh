#!/bin/bash

# iOS无用代码及资源扫描Agent Skill - 安装脚本
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
SCRIPT_NAME="iOS无用代码扫描Agent Skill安装脚本"
VERSION="1.0.0"
AUTHOR="AI Assistant"

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_DIR="/usr/local/bin/ios_unused_scanner"
CONFIG_DIR="$HOME/.config/ios_unused_scanner"
LOG_DIR="$HOME/.cache/ios_unused_scanner/logs"

# 显示帮助信息
show_help() {
    cat << EOF
${CYAN}${SCRIPT_NAME} v${VERSION}${NC}

${GREEN}用途：${NC}
    安装iOS无用代码及资源扫描Agent Skill

${GREEN}语法：${NC}
    $0 [选项]

${GREEN}选项：${NC}
    -h, --help          显示此帮助信息
    -v, --version       显示版本信息
    -d, --dir DIR       指定安装目录（默认: ${INSTALL_DIR}）
    -c, --config DIR    指定配置目录（默认: ${CONFIG_DIR}）
    -l, --log DIR       指定日志目录（默认: ${LOG_DIR}）
    --system-wide      系统级安装（需要sudo权限）
    --user-only        仅用户级安装（默认）
    --force            强制重新安装
    --skip-deps        跳过依赖检查
    --dev              开发模式安装

${GREEN}示例：${NC}
    $0                    # 用户级安装
    $0 --system-wide      # 系统级安装
    $0 --dev              # 开发模式安装
    $0 --force            # 强制重新安装

${GREEN}安装目录结构：${NC}
    ${INSTALL_DIR}/
    ├── bin/              # 可执行文件
    ├── configs/          # 配置文件
    ├── src/              # 源代码
    ├── scripts/          # 脚本文件
    ├── docs/             # 文档
    └── logs/             # 日志文件

${YELLOW}注意：${NC}
    • 需要Python 3.6+和macOS 10.15+
    • 系统级安装需要sudo权限
    • 建议在虚拟环境中安装
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
        echo -e "${YELLOW}建议使用Homebrew安装: brew install python3${NC}"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    echo -e "${GREEN}✅ Python版本: ${PYTHON_VERSION}${NC}"
    
    # 检查macOS版本
    if [[ "$(uname)" != "Darwin" ]]; then
        echo -e "${RED}❌ 错误: 本工具仅支持macOS系统${NC}"
        exit 1
    fi
    
    MACOS_VERSION=$(sw_vers -productVersion)
    echo -e "${GREEN}✅ macOS版本: ${MACOS_VERSION}${NC}"
    
    # 检查Xcode
    if ! command -v xcodebuild &> /dev/null; then
        echo -e "${YELLOW}⚠️  警告: 未找到Xcode，某些功能可能受限${NC}"
    else
        XCODE_VERSION=$(xcodebuild -version | head -n1)
        echo -e "${GREEN}✅ ${XCODE_VERSION}${NC}"
    fi
    
    # 检查Git
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}⚠️  警告: 未找到Git，某些功能可能受限${NC}"
    else
        GIT_VERSION=$(git --version)
        echo -e "${GREEN}✅ ${GIT_VERSION}${NC}"
    fi
    
    echo -e "${GREEN}✅ 所有依赖检查通过${NC}"
}

# 安装Python依赖
install_python_deps() {
    echo -e "${BLUE}📦 安装Python依赖...${NC}"
    
    # 检查pip
    if ! command -v pip3 &> /dev/null; then
        echo -e "${RED}❌ 错误: 未找到pip3，请先安装pip${NC}"
        exit 1
    fi
    
    # 安装依赖包
    REQUIRED_PACKAGES=(
        "requests"
        "beautifulsoup4"
        "lxml"
        "jinja2"
        "colorama"
    )
    
    for package in "${REQUIRED_PACKAGES[@]}"; do
        echo -e "${BLUE}安装 ${package}...${NC}"
        if pip3 install "$package" &> /dev/null; then
            echo -e "${GREEN}✅ ${package} 安装成功${NC}"
        else
            echo -e "${RED}❌ ${package} 安装失败${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}✅ Python依赖安装完成${NC}"
}

# 创建目录结构
create_directories() {
    echo -e "${BLUE}📁 创建目录结构...${NC}"
    
    local dirs=(
        "$INSTALL_DIR"
        "$INSTALL_DIR/bin"
        "$INSTALL_DIR/configs"
        "$INSTALL_DIR/src"
        "$INSTALL_DIR/scripts"
        "$INSTALL_DIR/docs"
        "$CONFIG_DIR"
        "$LOG_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            echo -e "${GREEN}✅ 创建目录: $dir${NC}"
        else
            echo -e "${YELLOW}ℹ️  目录已存在: $dir${NC}"
        fi
    done
}

# 复制文件
copy_files() {
    echo -e "${BLUE}📄 复制文件...${NC}"
    
    # 复制配置文件
    cp -r "$SKILL_ROOT/configs/"* "$INSTALL_DIR/configs/" 2>/dev/null || true
    echo -e "${GREEN}✅ 配置文件复制完成${NC}"
    
    # 复制源代码
    cp -r "$SKILL_ROOT/src/"* "$INSTALL_DIR/src/" 2>/dev/null || true
    echo -e "${GREEN}✅ 源代码复制完成${NC}"
    
    # 复制脚本文件
    cp -r "$SKILL_ROOT/scripts/"* "$INSTALL_DIR/scripts/" 2>/dev/null || true
    echo -e "${GREEN}✅ 脚本文件复制完成${NC}"
    
    # 复制文档
    cp -r "$SKILL_ROOT/docs/"* "$INSTALL_DIR/docs/" 2>/dev/null || true
    echo -e "${GREEN}✅ 文档复制完成${NC}"
    
    # 创建可执行文件
    cat > "$INSTALL_DIR/bin/ios_unused_scanner" << 'EOF'
#!/bin/bash
# iOS无用代码扫描器 - 命令行入口

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$INSTALL_DIR/src/scanner.py" "$@"
EOF
    
    chmod +x "$INSTALL_DIR/bin/ios_unused_scanner"
    echo -e "${GREEN}✅ 可执行文件创建完成${NC}"
}

# 创建符号链接
create_symlinks() {
    echo -e "${BLUE}🔗 创建符号链接...${NC}"
    
    local bin_dir="/usr/local/bin"
    
    if [[ ! -w "$bin_dir" ]]; then
        echo -e "${YELLOW}⚠️  需要sudo权限创建符号链接${NC}"
        sudo ln -sf "$INSTALL_DIR/bin/ios_unused_scanner" "$bin_dir/ios_unused_scanner" 2>/dev/null || {
            echo -e "${YELLOW}⚠️  符号链接创建失败，使用本地路径${NC}"
            return
        }
    else
        ln -sf "$INSTALL_DIR/bin/ios_unused_scanner" "$bin_dir/ios_unused_scanner" 2>/dev/null || {
            echo -e "${YELLOW}⚠️  符号链接创建失败${NC}"
        }
    fi
    
    echo -e "${GREEN}✅ 符号链接创建完成${NC}"
}

# 创建配置文件
create_configs() {
    echo -e "${BLUE}⚙️  创建配置文件...${NC}"
    
    # 创建默认配置文件
    cat > "$CONFIG_DIR/default.json" << EOF
{
    "skill": {
        "name": "ios_unused_code_scanner",
        "version": "1.0.0",
        "install_path": "$INSTALL_DIR",
        "config_path": "$CONFIG_DIR",
        "log_path": "$LOG_DIR",
        "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    },
    "paths": {
        "install_dir": "$INSTALL_DIR",
        "config_dir": "$CONFIG_DIR",
        "log_dir": "$LOG_DIR"
    }
}
EOF
    
    echo -e "${GREEN}✅ 配置文件创建完成${NC}"
}

# 设置环境变量
setup_environment() {
    echo -e "${BLUE}🌍 设置环境变量...${NC}"
    
    local shell_rc=""
    
    case "$SHELL" in
        */bash)
            shell_rc="$HOME/.bashrc"
            ;;
        */zsh)
            shell_rc="$HOME/.zshrc"
            ;;
        */fish)
            shell_rc="$HOME/.config/fish/config.fish"
            ;;
        *)
            echo -e "${YELLOW}⚠️  无法检测Shell类型，请手动设置环境变量${NC}"
            return
            ;;
    esac
    
    if [[ -f "$shell_rc" ]]; then
        # 检查是否已设置
        if ! grep -q "IOS_UNUSED_SCANNER_HOME" "$shell_rc"; then
            cat >> "$shell_rc" << EOF

# iOS无用代码扫描器环境变量
export IOS_UNUSED_SCANNER_HOME="$INSTALL_DIR"
export PATH="\$IOS_UNUSED_SCANNER_HOME/bin:\$PATH"
EOF
            echo -e "${GREEN}✅ 环境变量已添加到 $shell_rc${NC}"
            echo -e "${YELLOW}ℹ️  请重新加载Shell配置: source $shell_rc${NC}"
        else
            echo -e "${YELLOW}ℹ️  环境变量已设置${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  未找到Shell配置文件: $shell_rc${NC}"
    fi
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}🔍 验证安装...${NC}"
    
    # 检查可执行文件
    if [[ -f "$INSTALL_DIR/bin/ios_unused_scanner" ]]; then
        echo -e "${GREEN}✅ 可执行文件验证通过${NC}"
    else
        echo -e "${RED}❌ 可执行文件验证失败${NC}"
        return 1
    fi
    
    # 检查Python模块
    if python3 -c "import sys; sys.path.append('$INSTALL_DIR/src'); from scanner import iOSUnusedScanner; print('✅ Python模块验证通过')" &> /dev/null; then
        echo -e "${GREEN}✅ Python模块验证通过${NC}"
    else
        echo -e "${RED}❌ Python模块验证失败${NC}"
        return 1
    fi
    
    # 测试运行
    echo -e "${BLUE}🧪 测试运行...${NC}"
    if "$INSTALL_DIR/bin/ios_unused_scanner" --help &> /dev/null; then
        echo -e "${GREEN}✅ 测试运行通过${NC}"
    else
        echo -e "${RED}❌ 测试运行失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ 安装验证完成${NC}"
    return 0
}

# 显示安装摘要
show_summary() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}        🎉 安装完成！${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e ""
    echo -e "${GREEN}📁 安装目录: ${INSTALL_DIR}${NC}"
    echo -e "${GREEN}⚙️  配置目录: ${CONFIG_DIR}${NC}"
    echo -e "${GREEN}📝 日志目录: ${LOG_DIR}${NC}"
    echo -e ""
    echo -e "${BLUE}🚀 使用方法：${NC}"
    echo -e "  ${CYAN}•${NC} 扫描当前目录: ${GREEN}ios_unused_scanner${NC}"
    echo -e "  ${CYAN}•${NC} 扫描指定项目: ${GREEN}ios_unused_scanner /path/to/ios/project${NC}"
    echo -e "  ${CYAN}•${NC} 仅扫描代码: ${GREEN}ios_unused_scanner --code-only${NC}"
    echo -e "  ${CYAN}•${NC} 仅扫描资源: ${GREEN}ios_unused_scanner --resource-only${NC}"
    echo -e ""
    echo -e "${YELLOW}📚 更多信息请查看文档: ${INSTALL_DIR}/docs/${NC}"
    echo -e ""
    echo -e "${GREEN}🎯 下一步：${NC}"
    echo -e "  1. 重新加载Shell配置: ${CYAN}source ~/.zshrc${NC} (或 ~/.bashrc)"
    echo -e "  2. 运行扫描测试: ${CYAN}ios_unused_scanner --help${NC}"
    echo -e "  3. 查看详细文档: ${CYAN}cat ${INSTALL_DIR}/docs/README.md${NC}"
    echo -e ""
}

# 主函数
main() {
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
            -d|--dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_DIR="$2"
                shift 2
                ;;
            -l|--log)
                LOG_DIR="$2"
                shift 2
                ;;
            --system-wide)
                INSTALL_DIR="/usr/local/share/ios_unused_scanner"
                CONFIG_DIR="/etc/ios_unused_scanner"
                LOG_DIR="/var/log/ios_unused_scanner"
                shift
                ;;
            --user-only)
                # 使用默认值
                shift
                ;;
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --dev)
                DEV_MODE=true
                shift
                ;;
            -*)
                echo -e "${RED}❌ 错误: 未知选项 $1${NC}"
                show_help
                exit 1
                ;;
            *)
                echo -e "${RED}❌ 错误: 未知参数 $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 显示标题
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         ${SCRIPT_NAME} v${VERSION}${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e ""
    
    # 检查是否已安装
    if [[ -d "$INSTALL_DIR" && "$FORCE_INSTALL" != "true" ]]; then
        echo -e "${YELLOW}⚠️  Skill已安装于 ${INSTALL_DIR}${NC}"
        read -p "是否重新安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}安装已取消${NC}"
            exit 0
        fi
    fi
    
    # 执行安装步骤
    if [[ "$SKIP_DEPS" != "true" ]]; then
        check_dependencies
        echo -e ""
        install_python_deps
        echo -e ""
    fi
    
    create_directories
    echo -e ""
    copy_files
    echo -e ""
    create_symlinks
    echo -e ""
    create_configs
    echo -e ""
    setup_environment
    echo -e ""
    
    if verify_installation; then
        show_summary
        echo -e "${GREEN}🎉 iOS无用代码扫描Agent Skill安装成功！${NC}"
    else
        echo -e "${RED}❌ 安装验证失败，请检查错误信息${NC}"
        exit 1
    fi
}

# 运行主函数
main "$@"