#!/usr/bin/env bash

# 脚本名称: replace_sources_to_tsinghua.sh
# 功能: 将 Ubuntu/Debian/Kali 系统源替换为清华大学镜像源
#       自动适配 Ubuntu 24.04+ 和 Debian 12+ 的 DEB822 格式
# 作者: OopsUnix
# 日期: 2024
# ========================
# Example：
# 
# # 替换为清华源
# sudo ./replace_sources_to_tsinghua.sh
# 
# 一键恢复原始源
# sudo ./replace_sources_to_tsinghua.sh --restore

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请以 root 权限运行此脚本 (sudo 或 su)${NC}"
    exit 1
fi

# ==================== 恢复功能 ====================
if [ "$1" = "--restore" ] || [ "$1" = "-r" ]; then
    RESTORE_MODE=true
else
    RESTORE_MODE=false
fi

# ==================== 系统检测与路径配置 ====================
get_system_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
        VERSION_CODENAME="$VERSION_CODENAME"
        VERSION_ID="$VERSION_ID"
        if [ -z "$VERSION_CODENAME" ] && [ -n "$VERSION" ]; then
            VERSION_CODENAME=$(echo "$VERSION" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
        fi
    else
        echo -e "${RED}错误: 无法确定系统类型${NC}"
        exit 1
    fi
}

detect_system_and_config_path() {
    get_system_info

    case "$DISTRO" in
        ubuntu|Ubuntu)
            SYSTEM="Ubuntu"
            # Ubuntu 24.04+ 使用 DEB822 格式
            if [ -n "$VERSION_ID" ] && {
                [ "$(echo "$VERSION_ID" | cut -d. -f1)" -gt 24 ] ||
                { [ "$(echo "$VERSION_ID" | cut -d. -f1)" -eq 24 ] && [ -n "$(echo "$VERSION_ID" | grep -E '^24\.04')" ]; }
            }; then
                CONFIG_FILE="/etc/apt/sources.list.d/ubuntu.sources"
                USE_DEB822=true
            else
                CONFIG_FILE="/etc/apt/sources.list"
                USE_DEB822=false
            fi

            if [ -z "$VERSION_CODENAME" ]; then
                if command -v lsb_release >/dev/null 2>&1; then
                    VERSION_CODENAME=$(lsb_release -cs 2>/dev/null)
                fi
            fi
            ;;
        debian|Debian)
            SYSTEM="Debian"
            # Debian 12+ 使用 DEB822 格式
            if [ -n "$VERSION_ID" ] && { [ "$VERSION_ID" = "12" ] || [ "$(echo "$VERSION_ID" | cut -d. -f1)" -gt 12 ]; }; then
                CONFIG_FILE="/etc/apt/sources.list.d/debian.sources"
                USE_DEB822=true
            else
                CONFIG_FILE="/etc/apt/sources.list"
                USE_DEB822=false
            fi

            if [ -z "$VERSION_CODENAME" ]; then
                if grep -q "bookworm" /etc/debian_version 2>/dev/null; then
                    VERSION_CODENAME="bookworm"
                elif grep -q "bullseye" /etc/debian_version 2>/dev/null; then
                    VERSION_CODENAME="bullseye"
                elif grep -q "buster" /etc/debian_version 2>/dev/null; then
                    VERSION_CODENAME="buster"
                else
                    VERSION_CODENAME=$(cat /etc/debian_version 2>/dev/null | awk -F. '{print $1}' | tr '[:upper:]' '[:lower:]')
                fi
            fi
            ;;
        kali|Kali)
            SYSTEM="Kali"
            CONFIG_FILE="/etc/apt/sources.list"
            USE_DEB822=false
            if [ -z "$VERSION_CODENAME" ]; then
                VERSION_CODENAME="kali-rolling"
            fi
            ;;
        *)
            echo -e "${RED}错误: 不支持的系统: $DISTRO${NC}"
            echo "本脚本仅支持 Ubuntu、Debian、Kali Linux"
            exit 1
            ;;
    esac

    if [ -z "$VERSION_CODENAME" ]; then
        echo -e "${YELLOW}⚠ 警告: 无法自动检测版本代号，使用默认值${NC}"
        case "$SYSTEM" in
            Ubuntu) VERSION_CODENAME="focal" ;;
            Debian) VERSION_CODENAME="bookworm" ;;
            Kali) VERSION_CODENAME="kali-rolling" ;;
        esac
    fi

    BACKUP_FILE="${CONFIG_FILE}.backup"

    echo -e "${GREEN}✅ 检测到系统: $SYSTEM $VERSION_CODENAME${NC}"
    if [ "$USE_DEB822" = true ]; then
        echo -e "${BLUE}ℹ 使用 DEB822 格式配置文件: $CONFIG_FILE${NC}"
    else
        echo -e "${BLUE}ℹ 使用传统格式配置文件: $CONFIG_FILE${NC}"
    fi
}

# ==================== 备份函数 ====================
backup_sources() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}💾 正在备份原始源文件 → $BACKUP_FILE${NC}"
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo -e "${GREEN}✓ 备份完成${NC}"
    else
        echo -e "${YELLOW}⚠ 警告: $CONFIG_FILE 不存在，将创建新文件${NC}"
        mkdir -p "$(dirname "$CONFIG_FILE")"
    fi
}

# ==================== 恢复函数 ====================
restore_sources() {
    if [ -f "$BACKUP_FILE" ]; then
        echo -e "${BLUE}🔄 正在从备份恢复原始源配置...${NC}"
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        echo -e "${GREEN}✓ 恢复成功！${NC}"
        echo -e "${BLUE}🔄 正在更新软件包列表...${NC}"
        apt update
        echo -e "${GREEN}🎉 操作完成。${NC}"
        exit 0
    else
        echo -e "${RED}❌ 错误: 备份文件 $BACKUP_FILE 不存在，无法恢复。${NC}"
        exit 1
    fi
}

# ==================== 生成清华源配置 ====================
generate_tsinghua_sources() {
    # 确保目录存在
    mkdir -p "$(dirname "$CONFIG_FILE")"

    if [ "$USE_DEB822" = true ]; then
        case "$SYSTEM" in
            Ubuntu)
                cat > "$CONFIG_FILE" << EOF
# 清华大学 Ubuntu 镜像源 (DEB822 格式)
# Generated by replace_sources_to_tsinghua.sh
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
Suites: $VERSION_CODENAME $VERSION_CODENAME-updates $VERSION_CODENAME-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# Types: deb-src
# URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
# Suites: $VERSION_CODENAME $VERSION_CODENAME-updates $VERSION_CODENAME-backports
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# 安全更新源
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
Suites: $VERSION_CODENAME-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# 源码仓库（默认注释）
# Types: deb-src
# URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
# Suites: $VERSION_CODENAME-security
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
            ;;

        Debian)
            cat > "$CONFIG_FILE" << EOF
# 清华大学 Debian 镜像源 (DEB822 格式)
# Generated by replace_sources_to_tsinghua.sh
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian/
Suites: $VERSION_CODENAME $VERSION_CODENAME-updates $VERSION_CODENAME-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# Types: deb-src
# URIs: https://mirrors.tuna.tsinghua.edu.cn/debian/
# Suites: $VERSION_CODENAME $VERSION_CODENAME-updates $VERSION_CODENAME-backports
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 安全更新源
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian-security
Suites: $VERSION_CODENAME-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Types: deb-src
# URIs: https://mirrors.tuna.tsinghua.edu.cn/debian-security
# Suites: $VERSION_CODENAME-security
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
                ;;
        esac
    else
        # 传统格式：Ubuntu <24.04 / Debian <12 / Kali
        case "$SYSTEM" in
            Ubuntu)
                cat > "$CONFIG_FILE" << EOF
# 清华大学 Ubuntu 镜像源
# Generated by replace_sources_to_tsinghua.sh
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $VERSION_CODENAME main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $VERSION_CODENAME-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $VERSION_CODENAME-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $VERSION_CODENAME-security main restricted universe multiverse

# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $VERSION_CODENAME main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $VERSION_CODENAME-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $VERSION_CODENAME-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $VERSION_CODENAME-security main restricted universe multiverse
EOF
                ;;

            Debian)
                cat > "$CONFIG_FILE" << EOF
# 清华大学 Debian 镜像源
# Generated by replace_sources_to_tsinghua.sh
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $VERSION_CODENAME main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $VERSION_CODENAME-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $VERSION_CODENAME-backports main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security $VERSION_CODENAME-security main contrib non-free non-free-firmware

# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ $VERSION_CODENAME main contrib non-free non-free-firmware
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ $VERSION_CODENAME-updates main contrib non-free non-free-firmware
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ $VERSION_CODENAME-backports main contrib non-free non-free-firmware
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian-security $VERSION_CODENAME-security main contrib non-free non-free-firmware
EOF
                ;;

            Kali)
                cat > "$CONFIG_FILE" << EOF
# 清华大学 Kali Linux 镜像源
# Generated by replace_sources_to_tsinghua.sh
deb https://mirrors.tuna.tsinghua.edu.cn/kali kali-rolling main non-free contrib non-free-firmware
deb-src https://mirrors.tuna.tsinghua.edu.cn/kali kali-rolling main non-free contrib non-free-firmware
EOF
                ;;
        esac
    fi

    echo -e "${GREEN}✓ 已生成清华大学镜像源配置${NC}"
}

# ==================== 更新源 ====================
update_package_list() {
    echo -e "${BLUE}🔄 正在更新软件包列表...${NC}"
    if apt update; then
        echo -e "${GREEN}✓ 软件包列表更新成功${NC}"
    else
        echo -e "${YELLOW}⚠ 警告: 软件包列表更新失败，但源替换已完成${NC}"
        echo "请检查网络连接或手动运行 'apt update'"
    fi
}

# ==================== 显示当前配置 ====================
show_current_sources() {
    echo -e "${BLUE}📄 当前源配置 (${CONFIG_FILE}):${NC}"
    echo "========================================"
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo "⚠ 文件尚未创建或已被删除"
    fi
    echo "========================================"
}

# ==================== 主流程 ====================
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   Ubuntu/Debian/Kali 源替换为清华镜像${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}📌 提示: 运行 ${GREEN}./$(basename $0) --restore${YELLOW} 可从备份恢复原始源${NC}"
    echo

    # 检测系统和配置文件路径
    detect_system_and_config_path

    # 如果是恢复模式，直接恢复并退出
    if [ "$RESTORE_MODE" = true ]; then
        restore_sources
    fi

    # 备份原始配置
    backup_sources

    # 生成清华源
    generate_tsinghua_sources

    # 询问是否更新
    read -p "是否立即更新软件包列表? (y/n, 默认 y): " update_choice
    update_choice=${update_choice:-y}

    if [[ "$update_choice" =~ ^[Yy]$ ]]; then
        update_package_list
    fi

    # 显示结果
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎉 操作完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ 系统源已成功替换为清华大学镜像源${NC}"
    echo -e "${YELLOW}📌 备份文件: $BACKUP_FILE${NC}"
    echo -e "${BLUE}🔄 恢复原始源命令:${NC}"
    echo -e "  sudo ./${0##*/} --restore"
    echo

    show_current_sources

    echo -e "${GREEN}✅ 脚本执行完毕!${NC}"
}

# 执行主函数
main