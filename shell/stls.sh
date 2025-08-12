#!/bin/bash

# =============================================================================
# stls.sh - ShadowTLS 管理脚本
# 支持一键安装、升级和卸载 SS2022 + ShadowTLS
# 版本: 1.0.0
# GitHub: https://github.com/oopsunix/script
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PLAIN='\033[0m'

# 全局配置路径
## 定义系统路径
INSTALL_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
## Shadowsocks Rust 相关路径
SS_BIN_PATH="/usr/local/bin/ss-rust"
SS_CONFIG_DIR="/etc/shadowsocks"
SS_CONFIG_PATH="$SS_CONFIG_DIR/config.json"
SS_SERVICE_PATH="$SYSTEMD_DIR/shadowsocks.service"
SS_VER_PATH="$SS_CONFIG_DIR/ver.txt"
## ShadowTLS 相关路径
STLS_BIN_PATH="/usr/local/bin/shadow-tls"
STLS_SERVICE_PATH="$SYSTEMD_DIR/shadow-tls.service"
STLS_VER_PATH="/etc/shadowtls/ver.txt"

# 全局变量
SCRIPT_VERSION="1.0.0"
SS_REPO="shadowsocks/shadowsocks-rust"
STLS_REPO="ihciah/shadow-tls"
FASTOPEN="false"
DEFAULT_PASSWORD="CtGErUIpb9VJoooe"


# =============================================================================
# 系统模块
# =============================================================================

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}请以 root 权限运行此脚本${PLAIN}"
        exit 1
    fi
}

# 检测操作系统兼容性
check_os() {
    # 检查是否为支持的Linux系统
    if [[ ! -f /etc/os-release ]] && [[ ! -f /etc/redhat-release ]] && [[ ! -f /etc/debian_version ]]; then
        echo -e "${RED}不支持的操作系统，请在Linux系统上运行此脚本${PLAIN}"
        exit 1
    fi
}

# 包管理器检测
check_package_manager() {
    if command -v apt &> /dev/null; then
        PM="apt"
        PM_UPDATE="apt update"
        PM_INSTALL="apt install -y"
    elif command -v yum &> /dev/null; then
        PM="yum"
        PM_UPDATE="yum makecache"
        PM_INSTALL="yum install -y"
    elif command -v dnf &> /dev/null; then
        PM="dnf"
        PM_UPDATE="dnf makecache"
        PM_INSTALL="dnf install -y"
    elif command -v pacman &> /dev/null; then
        PM="pacman"
        PM_UPDATE="pacman -Sy"
        PM_INSTALL="pacman -S --noconfirm"
    else
        echo -e "${RED}无法确定包管理器，请手动安装依赖工具${PLAIN}"
        exit 1
    fi
}

# 安装依赖工具
install_dependencies() {
    local tools=("wget" "curl" "jq" "qrencode")
    local missing_tools=()
    
    echo -e "${BLUE}检查依赖工具...${PLAIN}"
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
            echo -e "${YELLOW}检测到 $tool 未安装${PLAIN}"
        else
            echo -e "${GREEN}$tool 已安装${PLAIN}"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}正在安装缺失工具：${missing_tools[*]}...${PLAIN}"
        
        # 特殊处理不同包管理器的包名差异
        local install_packages=()
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "qrencode")
                    if [[ "$PM" == "apt" ]]; then
                        install_packages+=("qrencode")
                    elif [[ "$PM" == "yum" || "$PM" == "dnf" ]]; then
                        install_packages+=("qrencode")
                    elif [[ "$PM" == "pacman" ]]; then
                        install_packages+=("qrencode")
                    fi
                    ;;
                *)
                    install_packages+=("$tool")
                    ;;
            esac
        done
        
        $PM_UPDATE && $PM_INSTALL "${install_packages[@]}" || {
            echo -e "${RED}安装依赖工具失败，请检查网络或手动安装${PLAIN}"
            exit 1
        }
        echo -e "${GREEN}依赖工具安装完成${PLAIN}"
    fi
}


# 系统工具函数
show_system_info() {
    echo -e "${CYAN}系统信息：${PLAIN}"
    echo -e "操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo -e "内核版本: $(uname -r)"
    echo -e "架构: $(uname -m)"
    echo -e "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
    echo -e "内存: $(free -h | grep Mem | awk '{print $2}')"
    echo -e "磁盘: $(df -h / | tail -1 | awk '{print $2}')"
    echo -e "运行时间: $(uptime -p)"
}

show_network_status() {
    echo -e "${CYAN}网络状态：${PLAIN}"
    echo -e "${YELLOW}活动连接：${PLAIN}"
    netstat -tuln | grep LISTEN
    echo -e "\n${YELLOW}网络接口：${PLAIN}"
    ip addr show
}

show_service_logs() {
    echo -e "${CYAN}服务日志：${PLAIN}"
    echo -e "${YELLOW}Shadowsocks 日志：${PLAIN}"
    journalctl -u shadowsocks --no-pager -n 20
    echo -e "\n${YELLOW}ShadowTLS 日志：${PLAIN}"
    if [ -f "/var/log/shadowtls.log" ]; then
        tail -20 "/var/log/shadowtls.log"
    else
        echo "日志文件不存在"
    fi
}

firewall_management() {
    echo -e "${CYAN}防火墙管理：${PLAIN}"
    echo -e "${YELLOW}当前防火墙状态：${PLAIN}"
    
    if command -v ufw &> /dev/null; then
        ufw status
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --state
        firewall-cmd --list-all
    else
        echo "未检测到防火墙管理工具"
    fi
}

system_optimization() {
    echo -e "${CYAN}系统优化：${PLAIN}"
    echo -e "${YELLOW}正在优化系统参数...${PLAIN}"
    
    # 优化网络参数
    cat >> /etc/sysctl.conf <<EOF
# ShadowTLS 优化参数
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_frto = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.core.netdev_max_backlog = 5000
EOF
    
    sysctl -p
    echo -e "${GREEN}系统优化完成${PLAIN}"
}



# =============================================================================
# 工具函数模块
# =============================================================================

# 获取服务器 IP 地址（支持 IPv4/IPv6，多接口故障转移）
get_server_ip() {
    local ipv4_sources=(
        "https://api.ipify.org"
        "https://api.ip.sb/ip"
        "https://icanhazip.com"
        "https://ipecho.net/plain"
        "https://checkip.amazonaws.com"
        "https://ip.sb"
    )
    
    local ipv6_sources=(
        "https://api6.ipify.org"
        "https://ip.sb"
        "https://icanhazip.com"
    )
    
    local ipv4=""
    local ipv6=""
    
    # 尝试获取 IPv4 地址
    for source in "${ipv4_sources[@]}"; do
        ipv4=$(curl -s -4 -m 10 "$source" 2>/dev/null | tr -d '\n\r')
        if [[ -n "$ipv4" && "$ipv4" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        fi
        ipv4=""
    done
    
    # 尝试获取 IPv6 地址
    for source in "${ipv6_sources[@]}"; do
        ipv6=$(curl -s -6 -m 10 "$source" 2>/dev/null | tr -d '\n\r')
        if [[ -n "$ipv6" && "$ipv6" =~ ^[0-9a-fA-F:]+$ ]]; then
            break
        fi
        ipv6=""
    done
    
    # 判断IP类型并返回
    if [[ -n "$ipv4" && -n "$ipv6" ]]; then
        # 双栈，优先返回IPv4
        public_ip="$ipv4"
        # echo -e "${GREEN}检测到双栈网络，IPv4: $ipv4, IPv6: $ipv6${PLAIN}"
    elif [[ -n "$ipv4" ]]; then
        # 仅IPv4
        public_ip="$ipv4"
        # echo -e "${GREEN}检测到 IPv4 网络: $ipv4${PLAIN}"
    elif [[ -n "$ipv6" ]]; then
        # 仅IPv6
        public_ip="$ipv6"
        # echo -e "${GREEN}检测到 IPv6 网络: $ipv6${PLAIN}"
    else
        # 如果无法获取公网IP，尝试使用内网IP
        echo -e "${YELLOW}无法获取公网 IP 地址，尝试使用内网 IP 地址${PLAIN}"
        if command -v ip >/dev/null 2>&1; then
            ipv4=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -n 1)
        elif command -v ifconfig >/dev/null 2>&1; then
            ipv4=$(ifconfig | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -n 1)
        fi
        if [[ -n "$ipv4" ]]; then
            public_ip="$ipv4"
        else
            echo -e "${RED}无法获取服务器 IP 地址${PLAIN}" >&2
            return 1
        fi
    fi
    
    echo "$public_ip"
    return 0
}

# 获取最新版本信息
get_latest_version() {
    local repo="$1"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    
    echo -e "${YELLOW}正在获取 $repo 最新版本信息...${PLAIN}" >&2
    
    local api_response
    api_response=$(curl -s -m 30 "$api_url" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$api_response" ]; then
        echo -e "${RED}获取版本信息失败，请检查网络连接${PLAIN}" >&2
        return 1
    fi
    
    local latest_tag
    latest_tag=$(echo "$api_response" | jq -r '.tag_name' 2>/dev/null)
    
    if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
        echo -e "${RED}解析版本信息失败，请检查网络连接${PLAIN}" >&2
        return 1
    fi
    
    echo "$latest_tag"
}

# 端口检测和管理
check_port_usage() {
    local port="$1"
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        return 0  # 端口被占用
    else
        return 1  # 端口可用
    fi
}

# 生成随机端口
generate_random_port() {
    local min_port=${1:-10000}
    local max_port=${2:-65535}
    local port
    
    for i in {1..10}; do
        port=$(shuf -i "$min_port-$max_port" -n 1)
        if ! check_port_usage "$port"; then
            echo "$port"
            return 0
        fi
    done
    
    echo -e "${RED}无法找到可用端口${PLAIN}"
    return 1
}

# 验证端口范围
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# URL安全Base64编码
urlsafe_base64() {
    echo -n "$1" | base64 -w 0 | tr '+/' '-_' | tr -d '='
}

# 生成 SS 链接和多平台客户端配置
generate_ss_links() {
    local ss_port="$1"
    local ss_method="$2"
    local ss_password="$3"
    local stls_port="$4"
    local stls_password="$5"
    local stls_sni="$6"
    
    # 如果没有传入参数，从配置文件读取
    if [ -z "$ss_port" ] && [ -f "$STLS_SERVICE_PATH" ] && [ -f "$SS_CONFIG_PATH" ]; then
        ss_port=$(get_ssrust_port)
        ss_method=$(get_ssrust_method)
        ss_password=$(get_ssrust_password)
        stls_port=$(get_shadowtls_config "port")
        stls_password=$(get_shadowtls_config "password")
        stls_sni=$(get_shadowtls_config "domain")
    elif [ -z "$ss_port" ]; then
        echo -e "${RED}配置文件不存在且未提供参数${PLAIN}"
        return 1
    fi
    
    local server_ip=$(get_server_ip)

    echo -e "\n${YELLOW}================== 服务器配置 ==================${PLAIN}"
    echo -e "${GREEN}服务器 IP：${server_ip}${PLAIN}"
    echo -e "\n${CYAN}Shadowsocks 配置：${PLAIN}"
    echo -e "  监听端口：${ss_port}"
    echo -e "  加密方式：${ss_method}"
    echo -e "  连接密码：${ss_password}"
    echo -e "  连接模式：tcp_and_udp"
    echo -e "  Fast Open：false"
    echo -e "\n${CYAN}ShadowTLS 配置：${PLAIN}"
    echo -e "  监听端口：${stls_port}"
    echo -e "  连接密码：${stls_password}"
    echo -e "  SNI 域名：${stls_sni}"
    echo -e "  版本：3"
    
    # 生成 SS + ShadowTLS 合并链接
    local userinfo=$(echo -n "${ss_method}:${ss_password}" | base64 | tr -d '\n')
    local shadow_tls_config="{\"version\":\"3\",\"password\":\"${stls_password}\",\"host\":\"${stls_sni}\",\"port\":\"${stls_port}\",\"address\":\"${server_ip}\"}"
    local shadow_tls_base64=$(echo -n "${shadow_tls_config}" | base64 | tr -d '\n')
    local ss_url="ss://${userinfo}@${server_ip}:${ss_port}?shadow-tls=${shadow_tls_base64}#SS-ShadowTLS"
    
    echo -e "\n${YELLOW}------------------ Shadowrocket 配置 ------------------${PLAIN}"
    echo -e "${GREEN}SS + ShadowTLS 链接：${PLAIN}${ss_url}"
    echo -e "${GREEN}二维码：${PLAIN}"
    qrencode -t UTF8 "${ss_url}"
    
    echo -e "\n${YELLOW}------------------ Surge 配置 ------------------${PLAIN}"
    echo -e "${GREEN}SS+sTLS = ss, ${server_ip}, ${stls_port}, encrypt-method=${ss_method}, password=${ss_password}, shadow-tls-password=${stls_password}, shadow-tls-sni=${stls_sni}, shadow-tls-version=3, udp-relay=true, udp-port=${stls_port}${PLAIN}"
    
    echo -e "\n${YELLOW}------------------ Loon 配置 ------------------${PLAIN}"
    echo -e "${GREEN}SS+sTLS = Shadowsocks, ${server_ip}, ${stls_port}, ${ss_method}, \"${ss_password}\", shadow-tls-password=${stls_password}, shadow-tls-sni=${stls_sni}, shadow-tls-version=3, udp-port=${stls_port}, fast-open=false, udp=true${PLAIN}"
    
    echo -e "\n${YELLOW}------------------ Mihomo (Clash Meta) 配置 ------------------${PLAIN}"
    echo -e "${GREEN}proxies:${PLAIN}"
    echo -e "  - name: SS+sTLS"
    echo -e "    type: ss"
    echo -e "    server: ${server_ip}"
    echo -e "    port: ${stls_port}"
    echo -e "    cipher: ${ss_method}"
    echo -e "    password: \"${ss_password}\""
    echo -e "    plugin: shadow-tls"
    echo -e "    plugin-opts:"
    echo -e "      host: \"${stls_sni}\""
    echo -e "      password: \"${stls_password}\""
    echo -e "      version: 3"
    
    echo -e "\n${YELLOW}------------------ Sing-box 配置 ------------------${PLAIN}"
    echo -e "${GREEN}{${PLAIN}"
    echo -e "  \"type\": \"shadowsocks\","
    echo -e "  \"tag\": \"ss2022+sTLS\","
    echo -e "  \"method\": \"${ss_method}\","
    echo -e "  \"password\": \"${ss_password}\","
    echo -e "  \"detour\": \"shadowtls-out\","
    echo -e "  \"udp_over_tcp\": {"
    echo -e "    \"enabled\": true,"
    echo -e "    \"version\": 2"
    echo -e "  }"
    echo -e "},"
    echo -e "{"
    echo -e "  \"type\": \"shadowtls\","
    echo -e "  \"tag\": \"shadowtls-out\","
    echo -e "  \"server\": \"${server_ip}\","
    echo -e "  \"server_port\": ${listen_port},"
    echo -e "  \"version\": 3,"
    echo -e "  \"password\": \"${stls_password}\","
    echo -e "  \"tls\": {"
    echo -e "    \"enabled\": true,"
    echo -e "    \"server_name\": \"${stls_sni}\","
    echo -e "    \"utls\": {"
    echo -e "      \"enabled\": true,"
    echo -e "      \"fingerprint\": \"chrome\""
    echo -e "    }"
    echo -e "  }"
    echo -e "}"
    
}



# =============================================================================
# Shadowsocks 管理模块
# =============================================================================

# 检查Shadowsocks安装状态
check_ssrust_installed() {
    if [ -f "$SS_BIN_PATH" ]; then
        return 0
    else
        return 1
    fi
}

# 获取Shadowsocks当前版本
get_ssrust_version() {
    local version=$(cat "$SS_VER_PATH" 2>/dev/null | tr -d '\n')
    if [ -z "$version" ]; then
        echo "未知"
        return 1
    fi
    echo "$version"
}

# 获取 SS 端口
get_ssrust_port() {
    if [ ! -f "$SS_CONFIG_PATH" ]; then
        return 1
    fi
    local port=$(jq -r '.server_port' "$SS_CONFIG_PATH" 2>/dev/null)
    echo "$port"
}

# 获取 SS 密码
get_ssrust_password() {
    if [ ! -f "$SS_CONFIG_PATH" ]; then
        return 1
    fi
    local password=$(jq -r '.password' "$SS_CONFIG_PATH" 2>/dev/null)
    echo "$password"
}

# 获取 SS 加密方式
get_ssrust_method() {
    if [ ! -f "$SS_CONFIG_PATH" ]; then
        return 1
    fi
    local method=$(jq -r '.method' "$SS_CONFIG_PATH" 2>/dev/null)
    echo "$method"
}

# 下载并安装Shadowsocks Rust二进制文件
download_ssrust() {
    # 获取最新版本
    local latest_version
    latest_version=$(get_latest_version "$SS_REPO")
    if [ $? -ne 0 ]; then
        echo -e "${RED}获取 Shadowsocks 版本信息失败${PLAIN}"
        return 1
    fi
    
    echo -e "${YELLOW}正在下载版本: $latest_version${PLAIN}"
    local version="$latest_version"
    
    # 获取系统架构并构造文件名后缀
    local arch=$(uname -m)
    local arch_suffix
    case "$arch" in
        x86_64|amd64) arch_suffix="x86_64-unknown-linux-musl" ;;
        aarch64|arm64) arch_suffix="aarch64-unknown-linux-musl" ;;
        *) echo -e "${RED}不支持的架构: $arch${PLAIN}"; return 1 ;;
    esac
    
    # 从版本号中去掉 'v' 前缀用于构建URL和文件名
    local version_str=${version#v}
    local download_url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/shadowsocks-v${version_str}.${arch_suffix}.tar.xz"
    local tmp_file="/tmp/ss-rust.tar.xz"
    
    echo -e "${BLUE}正在下载 Shadowsocks...${PLAIN}"
    if ! wget -O "$tmp_file" "$download_url" --show-progress; then
        echo -e "${RED}下载失败，请检查网络连接${PLAIN}"
        return 1
    fi
    
    echo -e "${BLUE}正在解压文件...${PLAIN}"
    mkdir -p /tmp/ss-rust-dist
    if ! tar -xf "$tmp_file" -C /tmp/ss-rust-dist ssserver; then
        echo -e "${RED}解压失败${PLAIN}"
        rm -rf "$tmp_file" /tmp/ss-rust-dist
        return 1
    fi
    
    echo -e "${BLUE}正在安装二进制文件...${PLAIN}"
    if ! mv -f /tmp/ss-rust-dist/ssserver "$SS_BIN_PATH"; then
        echo -e "${RED}移动文件失败${PLAIN}"
        rm -rf "$tmp_file" /tmp/ss-rust-dist
        return 1
    fi
    chmod +x "$SS_BIN_PATH"
    
    # 清理临时文件
    rm -rf "$tmp_file" /tmp/ss-rust-dist
    
    # 记录版本信息
    mkdir -p "$(dirname "$SS_VER_PATH")"
    echo "$version" > "$SS_VER_PATH"
    
    echo -e "${GREEN}Shadowsocks 二进制文件安装完成${PLAIN}"
    return 0
}

# 安装Shadowsocks Rust
install_ssrust() {
    # 检查二进制文件是否存在
    if ! check_ssrust_installed; then
        echo -e "${BLUE}Shadowsocks 二进制文件不存在，开始下载安装...${PLAIN}"
        
        # 下载并安装二进制文件
        if ! download_ssrust; then
            echo -e "${RED}Shadowsocks 下载失败${PLAIN}"
            return 1
        fi
    fi
    
    # 检查服务是否已运行且配置文件存在
    if systemctl is-active --quiet shadowsocks && [ -f "$SS_CONFIG_PATH" ]; then
        echo -e "${GREEN}Shadowsocks 服务已运行且配置完整，跳过配置步骤${PLAIN}"
        return 0
    fi
    
    echo -e "${BLUE}开始配置 Shadowsocks 服务...${PLAIN}"

    # 1.设置端口
    local ss_port
    read -p "请输入 Shadowsocks 端口 (1024-65535，回车随机生成): " ss_port
    
    if [[ -z "$ss_port" ]]; then
        ss_port=$(generate_random_port 10000 50000)
        if [ $? -ne 0 ]; then
            echo -e "${RED}生成随机端口失败${PLAIN}"
            return 1
        fi
        echo -e "${GREEN}使用随机端口: $ss_port${PLAIN}"
    elif ! validate_port "$ss_port"; then
        echo -e "${RED}无效端口，使用随机端口${PLAIN}"
        ss_port=$(generate_random_port 10000 50000)
        echo -e "${GREEN}使用随机端口: $ss_port${PLAIN}"
    elif check_port_usage "$ss_port"; then
        echo -e "${YELLOW}端口 $ss_port 已被占用，使用随机端口${PLAIN}"
        ss_port=$(generate_random_port 10000 50000)
        echo -e "${GREEN}使用随机端口: $ss_port${PLAIN}"
    else
        echo -e "${GREEN}使用指定端口: $ss_port${PLAIN}"
    fi
    
    # 2. 设置加密方式
    echo -e "${BLUE}请选择加密方法:${PLAIN}"
    echo "1) 2022-blake3-aes-128-gcm"
    echo "2) 2022-blake3-aes-256-gcm 【推荐】"
    echo "3) 2022-blake3-chacha20-poly1305"
    echo "4) aes-256-gcm"
    echo "5) aes-128-gcm"
    echo "6) chacha20-ietf-poly1305"
    
    local encryption_choice
    local method
    read -p "请输入选项数字 (默认为 2): " encryption_choice
    encryption_choice=${encryption_choice:-2}
    case $encryption_choice in
        1) method="2022-blake3-aes-128-gcm" ;;
        2) method="2022-blake3-aes-256-gcm" ;;
        3) method="2022-blake3-chacha20-poly1305" ;;
        4) method="aes-256-gcm" ;;
        5) method="aes-128-gcm" ;;
        6) method="chacha20-ietf-poly1305" ;;
        *)
            echo -e "${YELLOW}无效选项，使用默认方法${PLAIN}"
            method="2022-blake3-aes-256-gcm"
            ;;
    esac
    echo -e "${GREEN}已选择加密方法: $method${PLAIN}"
    
    # 3. 设置密码
    read -rp "请输入 Shadowsocks 密码 (留空则自动生成): " input_password
    local ss_password
    if [[ -z "$input_password" ]]; then
        if [[ "$method" == "2022-blake3-aes-256-gcm" || "$method" == "2022-blake3-chacha20-poly1305" ]]; then
            ss_password=$(openssl rand -base64 32)
        elif [[ "$method" == "2022-blake3-aes-128-gcm" ]]; then
            ss_password=$(openssl rand -base64 16)
        else
            ss_password=$(openssl rand -base64 16)
        fi
        echo -e "${GREEN}已生成随机密码: $ss_password${PLAIN}"
    else
        ss_password="$input_password"
        echo -e "${GREEN}已设置密码: $ss_password${PLAIN}"
    fi
    
    # 4. 保存配置文件    
    mkdir -p "$SS_CONFIG_DIR"
    cat > "$SS_CONFIG_PATH" <<EOF
{
    "server": "::",
    "server_port": $ss_port,
    "password": "$ss_password",
    "method": "$method",
    "fast_open": false,
    "mode": "tcp_and_udp"
}
EOF
    
    # 5. 生成systemd服务文件
    cat > "$SYSTEMD_DIR/shadowsocks.service" <<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
Type=simple
ExecStart=$SS_BIN_PATH -c $SS_CONFIG_PATH
Restart=on-abort
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
        
    # 6. 启动服务
    systemctl daemon-reload
    # 启动 Shadowsocks 服务
    echo -e "${BLUE}正在启动 Shadowsocks 服务...${PLAIN}"
    systemctl enable shadowsocks
    service_control "shadowsocks" "start"
    
    # 获取服务器ip
    local server_ip=$(get_server_ip)
    # 构建并输出 ss:// 格式的链接
    local base64_password=$(echo -n "$method:$ss_password" | base64 -w 0)
    local node_name="SS-ShadowTLS"
    echo -e "${GREEN}ss链接: ss://${base64_password}@${server_ip}:$ss_port#$node_name${PLAIN}"
}

# 同步更新 ShadowTLS 后端端口配置
sync_shadowtls_backend_port() {
    local new_ss_port="$1"
    
    # 检查 ShadowTLS 是否已安装和配置
    if [ ! -f "$STLS_SERVICE_PATH" ]; then
        echo -e "${YELLOW}ShadowTLS 未配置，跳过端口同步${PLAIN}"
        return 0
    fi
    
    echo -e "${BLUE}检测到 ShadowTLS 已配置，正在同步后端端口...${PLAIN}"
    
    # 获取当前 ShadowTLS 配置
    local current_stls_port=$(get_shadowtls_config "port")
    local current_stls_password=$(get_shadowtls_config "password")
    local current_tls_domain=$(get_shadowtls_config "domain")
    local current_ss_port=$(get_shadowtls_config "ss_port")
    
    if [ -z "$current_stls_port" ] || [ -z "$current_stls_password" ] || [ -z "$current_tls_domain" ]; then
        echo -e "${RED}无法获取 ShadowTLS 当前配置，跳过端口同步${PLAIN}"
        return 1
    fi
    
    # 检查后端端口是否需要更新
    if [[ "$current_ss_port" == "$new_ss_port" ]]; then
        echo -e "${GREEN}ShadowTLS 后端端口已是最新，无需更新${PLAIN}"
        return 0
    fi
    
    echo -e "${YELLOW}更新 ShadowTLS 后端端口: $current_ss_port -> $new_ss_port${PLAIN}"
    
    # 停止 ShadowTLS 服务
    local shadowtls_was_running=false
    if systemctl is-active --quiet shadow-tls; then
        shadowtls_was_running=true
        echo -e "${BLUE}停止 ShadowTLS 服务...${PLAIN}"
        service_control "shadow-tls" "stop"
    fi
    
    # 使用现有函数重新创建服务配置
    create_shadowtls_service "$new_ss_port" "$current_stls_port" "$current_tls_domain" "$current_stls_password"
    
    # 重新加载 systemd 配置
    systemctl daemon-reload
    
    # 如果之前服务在运行，重新启动服务
    if [[ "$shadowtls_was_running" == "true" ]]; then
        echo -e "${BLUE}重新启动 ShadowTLS 服务...${PLAIN}"
        service_control "shadow-tls" "start"
        
        if systemctl is-active --quiet shadow-tls; then
            echo -e "${GREEN}ShadowTLS 后端端口同步成功，服务已重启${PLAIN}"
        else
            echo -e "${RED}ShadowTLS 服务重启失败，请检查配置${PLAIN}"
            return 1
        fi
    else
        echo -e "${GREEN}ShadowTLS 后端端口配置已更新${PLAIN}"
    fi
    
    return 0
}

# 修改 Shadowsocks 配置
modify_ssrust_config() {
    # 检查是否已安装
    if ! check_ssrust_installed; then
        echo -e "${RED}Shadowsocks 未安装，请先安装${PLAIN}"
        return 1
    fi

    if [ ! -f "$SS_CONFIG_PATH" ]; then
        echo -e "${RED}Shadowsocks 配置文件不存在，请重新安装${PLAIN}"
        return 1
    fi
    
    echo -e "${CYAN}修改 Shadowsocks 配置${PLAIN}"
    
    # 读取当前配置
    local current_port=$(jq -r '.server_port' "$SS_CONFIG_PATH" 2>/dev/null)
    local current_password=$(jq -r '.password' "$SS_CONFIG_PATH" 2>/dev/null)
    local current_method=$(jq -r '.method' "$SS_CONFIG_PATH" 2>/dev/null)
    
    echo -e "\n${YELLOW}当前配置：${PLAIN}"
    echo -e "端口: $current_port"
    echo -e "密码: $current_password"
    echo -e "加密方法: $current_method"
    echo
    
    # 询问是否修改端口
    read -p "是否修改端口？(y/n，默认n): " change_port
    local new_port=$current_port
    
    if [[ "$change_port" == "y" || "$change_port" == "Y" ]]; then
        read -p "请输入新端口(1024-65535): " new_port
        # 验证端口合法性
        if [[ -z "$new_port" || ! "$new_port" =~ ^[0-9]+$ || "$new_port" -lt 1024 || "$new_port" -gt 65535 ]]; then
            echo -e "${RED}无效的端口，使用原端口${PLAIN}"
            new_port=$current_port
        elif check_port_usage "$new_port"; then
            echo -e "${YELLOW}端口 $new_port 已被占用，使用原端口${PLAIN}"
            new_port=$current_port
        fi
    fi
    
    # 询问是否修改加密方法
    read -p "是否修改加密方法？(y/n，默认n): " change_method
    local new_method=$current_method
    
    if [[ "$change_method" == "y" || "$change_method" == "Y" ]]; then
        echo -e "${BLUE}请选择新的加密方法:${PLAIN}"
        echo "1) 2022-blake3-aes-128-gcm"
        echo "2) 2022-blake3-aes-256-gcm 【推荐】"
        echo "3) 2022-blake3-chacha20-poly1305"
        echo "4) aes-256-gcm"
        echo "5) aes-128-gcm"
        echo "6) chacha20-ietf-poly1305"
        
        read -p "请输入选项数字: " encryption_choice
        encryption_choice=${encryption_choice:-2}
        case $encryption_choice in
            1) new_method="2022-blake3-aes-128-gcm" ;;
            2) new_method="2022-blake3-aes-256-gcm" ;;
            3) new_method="2022-blake3-chacha20-poly1305" ;;
            4) new_method="aes-256-gcm" ;;
            5) new_method="aes-128-gcm" ;;
            6) new_method="chacha20-ietf-poly1305" ;;
            *)
                echo -e "${YELLOW}无效选项，使用原方法${PLAIN}"
                new_method=$current_method
                ;;
        esac
    fi
    
    # 询问是否修改密码
    read -p "是否修改密码？(y/n，默认n): " change_password
    local new_password=$current_password
    
    if [[ "$change_password" == "y" || "$change_password" == "Y" ]]; then
        # 根据加密方法自动生成或设置密码
        if [[ "$new_method" == "2022-blake3-aes-256-gcm" || "$new_method" == "2022-blake3-chacha20-poly1305" ]]; then
            new_password=$(openssl rand -base64 32)
            echo -e "${GREEN}已生成随机密码: $new_password${PLAIN}"
        elif [[ "$new_method" == "2022-blake3-aes-128-gcm" ]]; then
            new_password=$(openssl rand -base64 16)
            echo -e "${GREEN}已生成随机密码: $new_password${PLAIN}"
        else
            read -p "请输入新密码 (留空为默认密码 $DEFAULT_PASSWORD): " custom_password
            if [[ -z "$custom_password" ]]; then
                new_password="$DEFAULT_PASSWORD"
                echo -e "${GREEN}使用默认密码: $new_password${PLAIN}"
            else
                new_password="$custom_password"
            fi
        fi
    fi
    
    # 检查是否有配置变更
    local config_changed=false
    if [[ "$new_port" != "$current_port" || "$new_password" != "$current_password" || "$new_method" != "$current_method" ]]; then
        config_changed=true
    fi
    
    if [[ "$config_changed" == "true" ]]; then
        echo -e "\n${CYAN}正在更新配置...${PLAIN}"
        
        # 更新配置文件
        cat > "$SS_CONFIG_PATH" <<EOF
{
    "server": "::",
    "server_port": $new_port,
    "password": "$new_password",
    "method": "$new_method",
    "fast_open": false,
    "mode": "tcp_and_udp"
}
EOF
        
        # 重启服务以应用新配置
        service_control "shadowsocks" "restart"
        
        if systemctl is-active --quiet shadowsocks; then
            echo -e "${GREEN}配置更新成功，服务已重启${PLAIN}"
            
            # 如果端口发生变化，同步更新 ShadowTLS 后端端口
            if [[ "$new_port" != "$current_port" ]]; then
                sync_shadowtls_backend_port "$new_port"
            fi
            
            # 显示更新后的配置信息
            echo -e "\n${YELLOW}更新后的配置：${PLAIN}"
            echo -e "监听端口: $new_port"
            echo -e "连接密码: $new_password"
            echo -e "加密方法: $new_method"
            
            # 生成新的连接信息
            local server_ip=$(get_server_ip)
            local base64_password=$(echo -n "$new_method:$new_password" | base64 -w 0)
            local node_name="SS-ShadowTLS"
            echo -e "\n${GREEN}新的 ss 链接: ss://${base64_password}@${server_ip}:$new_port#$node_name${PLAIN}"
        else
            echo -e "${RED}服务重启失败，请检查配置${PLAIN}"
            return 1
        fi
    else
        echo -e "\n${YELLOW}配置未发生变更${PLAIN}"
    fi
}

# 升级Shadowsocks Rust
upgrade_ssrust() {
    # 检查是否已安装
    if ! check_ssrust_installed; then
        echo -e "${RED}Shadowsocks 未安装，请先安装${PLAIN}"
        return 1
    fi
    
    echo -e "${BLUE}正在检查 Shadowsocks 升级...${PLAIN}"
    
    # 检查当前版本
    local current_version
    current_version=$(get_ssrust_version)
    
    # 获取最新版本
    local latest_version
    latest_version=$(get_latest_version "$SS_REPO")
    if [ $? -ne 0 ]; then
        echo -e "${RED}获取 Shadowsocks 版本信息失败${PLAIN}"
        return 1
    fi
    
    echo -e "${CYAN}当前版本: $current_version${PLAIN}"
    echo -e "${CYAN}最新版本: $latest_version${PLAIN}"
    
    if [[ "$current_version" == "$latest_version" ]]; then
        echo -e "${GREEN}Shadowsocks 已是最新版本，无需升级${PLAIN}"
        return 0
    fi
    
    echo -e "${YELLOW}发现新版本，准备升级...${PLAIN}"
    
    # 停止服务
    service_control "shadowsocks" "stop"
    
    # 下载并安装新版本
    if ! download_ssrust; then
        echo -e "${RED}升级失败${PLAIN}"
        return 1
    fi
    
    # 重启服务
    service_control "shadowsocks" "start"
    
    if systemctl is-active --quiet shadowsocks; then
        echo -e "${GREEN}Shadowsocks 升级成功并已重启服务${PLAIN}"
    else
        echo -e "${RED}升级完成但服务启动失败，请检查配置${PLAIN}"
    fi
    
    return 0
}

# 卸载 Shadowsocks Rust
uninstall_ssrust() {
    # 检查是否已安装
    if ! check_ssrust_installed; then
        echo -e "${RED}Shadowsocks Rust 未安装${PLAIN}"
        return 1
    fi
    
    echo -e "${YELLOW}警告: 此操作将完全卸载 Shadowsocks 服务及其配置文件！${PLAIN}"
    read -p "是否继续？(y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${GREEN}已取消卸载${PLAIN}"
        return 0
    fi

    echo -e "${CYAN}正在卸载 Shadowsocks...${PLAIN}"
    
    # 停止并禁用服务
    service_control "shadowsocks" "stop"
    systemctl disable shadowsocks 2>/dev/null
    
    # 删除服务文件
    rm -f "$SYSTEMD_DIR/shadowsocks.service"
    
    # 删除二进制文件
    rm -f "$INSTALL_DIR/ssserver"
    rm -f "$INSTALL_DIR/sslocal"
    rm -f "$INSTALL_DIR/ssmanager"
    rm -f "$INSTALL_DIR/ssurl"
    rm -f "$SS_BIN_PATH"
    
    # 删除配置文件
    rm -rf "$SS_CONFIG_DIR"
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    echo -e "${GREEN}Shadowsocks 已成功卸载${PLAIN}"
}



# =============================================================================
# ShadowTLS 管理模块
# =============================================================================

# 检查ShadowTLS安装状态
check_shadowtls_installed() {
    if [ -f "$STLS_BIN_PATH" ] || systemctl is-active shadow-tls &>/dev/null; then
        echo -e "${GREEN}ShadowTLS 已安装${PLAIN}"
        return 0
    else
        return 1
    fi
}

# 获取 ShadowTLS 当前版本
get_shadowtls_version() {
    if [ ! -f "$STLS_VER_PATH" ]; then
        echo "未知"
        return 1
    fi
    local version=$(cat "$STLS_VER_PATH" 2>/dev/null | tr -d '\n')
    if [ -z "$version" ]; then
        echo "未知"
        return 1
    fi
    echo "$version"
}

# 从服务文件中提取 ShadowTLS 配置信息
get_shadowtls_config() {
    local config_type="$1"  # port, password, domain, ss_port
    
    if [ ! -f "$STLS_SERVICE_PATH" ]; then
        echo -e "${RED}ShadowTLS 服务文件不存在${PLAIN}" >&2
        return 1
    fi
    
    # 从 ExecStart 行提取配置信息
    local exec_start=$(grep "^ExecStart=" "$STLS_SERVICE_PATH" 2>/dev/null)
    if [ -z "$exec_start" ]; then
        echo -e "${RED}无法找到 ExecStart 配置${PLAIN}" >&2
        return 1
    fi
    
    case "$config_type" in
        "port"|"stls_port")
            # 提取 --listen 参数中的端口号，支持 IPv4 和 IPv6 格式
            echo "$exec_start" | sed -n 's/.*--listen \[::]:*\([0-9]*\).*/\1/p'
            ;;
        "password"|"stls_password")
            # 提取 --password 参数
            echo "$exec_start" | sed -n 's/.*--password \([^ ]*\).*/\1/p'
            ;;
        "domain"|"tls_domain")
            # 提取 --tls 参数
            echo "$exec_start" | sed -n 's/.*--tls \([^ ]*\).*/\1/p'
            ;;
        "ss_port"|"backend_port")
            # 提取 --server 参数中的端口号
            echo "$exec_start" | sed -n 's/.*--server [^:]*:\([0-9]*\).*/\1/p'
            ;;
        "all")
            # 返回所有配置信息
            local stls_port=$(echo "$exec_start" | sed -n 's/.*--listen \[::]:*\([0-9]*\).*/\1/p')
            local stls_password=$(echo "$exec_start" | sed -n 's/.*--password \([^ ]*\).*/\1/p')
            local tls_domain=$(echo "$exec_start" | sed -n 's/.*--tls \([^ ]*\).*/\1/p')
            local ss_port=$(echo "$exec_start" | sed -n 's/.*--server [^:]*:\([0-9]*\).*/\1/p')
            
            echo "stls_port=$stls_port"
            echo "stls_password=$stls_password"
            echo "tls_domain=$tls_domain"
            echo "ss_port=$ss_port"
            ;;
        *)
            echo -e "${RED}无效的配置类型: $config_type${PLAIN}" >&2
            echo -e "${YELLOW}支持的类型: port, password, domain, ss_port, all${PLAIN}" >&2
            return 1
            ;;
    esac
}

# 下载并安装ShadowTLS二进制文件
download_shadowtls() {
    # 获取最新版本
    local latest_version
    latest_version=$(get_latest_version "$STLS_REPO")
    if [ $? -ne 0 ]; then
        echo -e "${RED}获取 ShadowTLS 版本信息失败${PLAIN}"
        return 1
    fi
    
    echo -e "${YELLOW}正在下载版本: $latest_version${PLAIN}"
    local version="$latest_version"
    
    # 获取系统架构并构造文件名后缀
    local arch=$(uname -m)
    local arch_suffix
    case "$arch" in
        x86_64) arch_suffix="x86_64-unknown-linux-musl" ;;
        aarch64) arch_suffix="aarch64-unknown-linux-musl" ;;
        *) echo -e "${RED}不支持的架构: $arch${PLAIN}"; return 1 ;;
    esac
    
    # 下载并安装
    local download_url="https://github.com/ihciah/shadow-tls/releases/download/${version}/shadow-tls-${arch_suffix}"
    local tmp_file="/tmp/shadow-tls.tmp"
    
    echo -e "${BLUE}正在下载 ShadowTLS...${PLAIN}"
    if ! wget -O "$tmp_file" "$download_url" --show-progress; then
        echo -e "${RED}下载失败，请检查网络连接${PLAIN}"
        return 1
    fi
    
    echo -e "${BLUE}正在安装二进制文件...${PLAIN}"
    if ! mv "$tmp_file" "$STLS_BIN_PATH"; then
        echo -e "${RED}移动文件失败${PLAIN}"
        rm -f "$tmp_file"
        return 1
    fi
    chmod +x "$STLS_BIN_PATH"
    
    # 清理临时文件
    rm -f "$tmp_file"
    
    # 记录版本信息
    mkdir -p "$(dirname "$STLS_VER_PATH")"
    echo "$version" > "$STLS_VER_PATH"
    
    echo -e "${GREEN}ShadowTLS 二进制文件安装完成${PLAIN}"
    return 0
}

# 安装 ShadowTLS
install_shadowtls() {
    # 检查二进制文件是否存在
    if ! [ -f "$STLS_BIN_PATH" ]; then
        echo -e "${BLUE}ShadowTLS 二进制文件不存在，开始下载安装...${PLAIN}"
        # 下载并安装 ShadowTLS 二进制文件
        echo -e "${BLUE}开始下载 ShadowTLS...${PLAIN}"
        if ! download_shadowtls; then
            echo -e "${RED}ShadowTLS 下载失败${PLAIN}"
            return 1
        fi
    fi
    
    # 检查服务文件是否存在
    if [ -f "$STLS_SERVICE_PATH" ]; then
        echo -e "${GREEN}ShadowTLS 服务文件已存在且服务未运行，跳过配置步骤${PLAIN}"
        return 0
    fi
    
    # 检测 Shadowsocks 服务是否已安装
    if ! check_ssrust_installed; then
        echo -e "${YELLOW}Shadowsocks 未安装，是否自动安装？(y/n): ${PLAIN}"
        read -p "" confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            install_ssrust
        else
            echo -e "${RED}请先安装 Shadowsocks 服务${PLAIN}"
            return 1
        fi
    fi

    # 检查 Shadowsocks 配置文件是否存在并获取 Shadowsocks 端口
    if [ ! -f "$SS_CONFIG_PATH" ]; then
        echo -e "${RED}Shadowsocks 配置文件不存在${PLAIN}"
        return 1
    fi
    # 获取 Shadowsocks 配置端口
    local ss_port=$(get_ssrust_port)
    
    echo -e "${BLUE}开始配置 ShadowTLS...${PLAIN}"

    # 1. 设置 ShadowTLS 监听端口
    local stls_port
    read -p "请输入 ShadowTLS 监听端口 (1024-65535，回车随机生成): " stls_port
    
    if [[ -z "$stls_port" ]]; then
        stls_port=$(generate_random_port 10000 50000)
        if [ $? -ne 0 ]; then
            echo -e "${RED}生成随机端口失败${PLAIN}"
            return 1
        fi
        echo -e "${GREEN}使用随机端口: $stls_port${PLAIN}"
    elif ! validate_port "$stls_port"; then
        echo -e "${RED}无效端口，使用随机端口${PLAIN}"
        stls_port=$(generate_random_port 10000 50000)
        echo -e "${GREEN}使用随机端口: $stls_port${PLAIN}"
    elif check_port_usage "$stls_port"; then
        echo -e "${YELLOW}端口 $stls_port 已被占用，使用随机端口${PLAIN}"
        stls_port=$(generate_random_port 10000 50000)
        echo -e "${GREEN}使用随机端口: $stls_port${PLAIN}"
    else
        echo -e "${GREEN}使用指定端口: $stls_port${PLAIN}"
    fi
    
    # 2. 设置 TLS 伪装域名
    local tls_domain
    read -p "请输入 TLS 伪装域名 (回车默认为 www.microsoft.com): " tls_domain
    if [ -z "$tls_domain" ]; then
        tls_domain="www.microsoft.com"
    fi
    echo -e "${GREEN}使用域名: $tls_domain${PLAIN}"
    
    # 3. 生成随机密码
    local stls_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    echo -e "${GREEN}使用密码: $stls_password${PLAIN}"
    
    # 4. 创建 ShadowTLS 服务文件
    create_shadowtls_service "$ss_port" "$stls_port" "$tls_domain" "$stls_password"
    
    # 5. 启动服务
    systemctl daemon-reload
    systemctl enable shadow-tls
    service_control "shadow-tls" "start"
    
    if systemctl is-active --quiet shadow-tls; then
        echo -e "${GREEN}ShadowTLS 安装和配置完成并已启动${PLAIN}"
        
        # 生成客户端配置
        local ss_password=$(get_ssrust_password)
        local ss_method=$(get_ssrust_method)
        generate_ss_links "${ss_port}" "${ss_method}" "${ss_password}" "${stls_port}" "${stls_password}" "${tls_domain}"
        return 0
    else
        echo -e "${RED}ShadowTLS 启动失败${PLAIN}"
        return 1
    fi
}

# 创建 ShadowTLS 服务文件
create_shadowtls_service() {
    local ss_port=$1
    local stls_port=$2
    local tls_domain=$3
    local stls_password=$4

    local service_file="$STLS_SERVICE_PATH"
    local description="Shadow-TLS Server Service for Shadowsocks"
    local identifier="shadow-tls-ss"
    
    cat > "$service_file" << EOF
[Unit]
Description=${description}
Documentation=man:shadow-tls
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment=RUST_BACKTRACE=1
Environment=RUST_LOG=info
ExecStart=$STLS_BIN_PATH --v3 server --listen [::]:${stls_port} --server 127.0.0.1:${ss_port} --tls ${tls_domain} --password ${stls_password}
StandardOutput=append:/var/log/shadowtls-${identifier}.log
StandardError=append:/var/log/shadowtls-${identifier}.log
SyslogIdentifier=${identifier}
Restart=always
RestartSec=3

# 性能优化参数
LimitNOFILE=65535
CPUAffinity=0
Nice=0
IOSchedulingClass=realtime
IOSchedulingPriority=0
MemoryLimit=512M
CPUQuota=50%
LimitCORE=infinity
LimitRSS=infinity
LimitNPROC=65535
LimitAS=infinity
SystemCallFilter=@system-service
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

    # 创建日志文件
    touch "/var/log/shadowtls-${identifier}.log"
    chmod 640 "/var/log/shadowtls-${identifier}.log"
    chown root:root "/var/log/shadowtls-${identifier}.log"
}

# 修改 ShadowTLS 配置
modify_shadowtls_config() {
    if [ ! -f "$STLS_SERVICE_PATH" ]; then
        echo -e "${RED}ShadowTLS 未配置${PLAIN}"
        pause_and_continue
        return 1
    fi
    
    echo -e "${CYAN}修改 ShadowTLS 配置${PLAIN}"
    # 读取当前配置
    local STLS_PORT=$(get_shadowtls_config "port")
    local STLS_PASSWORD=$(get_shadowtls_config "password")
    local TLS_DOMAIN=$(get_shadowtls_config "domain")
    
    echo -e "\n${YELLOW}当前配置：${PLAIN}"
    echo -e "1. ShadowTLS 端口: $STLS_PORT"
    echo -e "2. ShadowTLS 密码: $STLS_PASSWORD"
    echo -e "3. TLS 域名: $TLS_DOMAIN"
    echo -e "4. 返回主菜单"
    
    read -rp "请选择要修改的项目 [1-4]: " choice
    
    case "$choice" in
        1)
            local new_port
            read -p "请输入新的 ShadowTLS 端口 (当前: $STLS_PORT): " new_port
            if [ ! -z "$new_port" ] && validate_port "$new_port" && ! check_port_usage "$new_port"; then
                STLS_PORT=$new_port
                echo -e "${GREEN}端口已更新为: $STLS_PORT${PLAIN}"
            else
                echo -e "${YELLOW}端口未更改或无效${PLAIN}"
            fi
            ;;
        2)
            local new_password
            read -p "请输入新的 ShadowTLS 密码 (当前: $STLS_PASSWORD，回车随机生成): " new_password
            if [ -z "$new_password" ]; then
                STLS_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
                echo -e "${GREEN}已生成新密码: $STLS_PASSWORD${PLAIN}"
            else
                STLS_PASSWORD=$new_password
                echo -e "${GREEN}密码已更新${PLAIN}"
            fi
            ;;
        3)
            local new_domain
            read -p "请输入新的 TLS 域名 (当前: $TLS_DOMAIN): " new_domain
            if [ ! -z "$new_domain" ]; then
                TLS_DOMAIN=$new_domain
                echo -e "${GREEN}域名已更新为: $TLS_DOMAIN${PLAIN}"
            else
                echo -e "${YELLOW}域名未更改${PLAIN}"
            fi
            ;;
        4)
            return 0
            ;;
        *)
            echo -e "${RED}无效选择${PLAIN}"
            return 1
            ;;
    esac
    
    # 获取 SS_PORT
    local SS_PORT=$(get_shadowtls_config "ss_port")
    
    # 重新创建服务文件
    create_shadowtls_service "$SS_PORT" "$STLS_PORT" "$TLS_DOMAIN" "$STLS_PASSWORD"
    
    # 重启服务
    systemctl daemon-reload
    service_control "shadow-tls" "restart"
    
    if systemctl is-active --quiet shadow-tls; then
        echo -e "${GREEN}配置更新成功${PLAIN}"
        generate_ss_links
    else
        echo -e "${RED}服务重启失败${PLAIN}"
    fi
    
    pause_and_continue
}

# 升级 ShadowTLS
upgrade_shadowtls() {
    # 检查是否已安装
    if ! check_shadowtls_installed; then
        echo -e "${RED}ShadowTLS 未安装，请先安装${PLAIN}"
        return 1
    fi
    
    echo -e "${BLUE}正在检查 ShadowTLS 升级...${PLAIN}"
    
    # 获取当前版本
    local current_version=$(get_shadowtls_version)
    
    # 获取最新版本
    local latest_version=$(get_latest_version "$STLS_REPO")
    if [ -z "$latest_version" ]; then
        echo -e "${RED}获取版本信息失败${PLAIN}"
        return 1
    fi
    
    echo -e "${CYAN}当前版本: $current_version${PLAIN}"
    echo -e "${CYAN}最新版本: $latest_version${PLAIN}"
    
    if [[ "$current_version" == "$latest_version" ]]; then
        echo -e "${GREEN}ShadowTLS 已是最新版本，无需升级${PLAIN}"
        return 0
    fi
    
    echo -e "${YELLOW}发现新版本，准备升级...${PLAIN}"
    
    # 停止服务
    service_control "shadow-tls" "stop"
    
    # 下载并安装新版本
    if ! download_shadowtls; then
        echo -e "${RED}升级失败${PLAIN}"
        return 1
    fi
    
    # 重启服务
    service_control "shadow-tls" "start"
    
    if systemctl is-active --quiet shadow-tls; then
        echo -e "${GREEN}ShadowTLS 升级成功并已重启服务${PLAIN}"
    else
        echo -e "${RED}升级完成但服务启动失败，请检查配置${PLAIN}"
    fi
    
    return 0
}

# 卸载 ShadowTLS
uninstall_shadowtls() {
    # 检查是否已安装
    if ! check_shadowtls_installed; then
        echo -e "${RED}ShadowTLS 未安装${PLAIN}"
        return 1
    fi

    echo -e "${YELLOW}警告: 此操作将完全卸载 ShadowTLS 服务及其配置文件！${PLAIN}"
    read -p "是否继续？(y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${GREEN}已取消卸载${PLAIN}"
        return 0
    fi

    echo -e "${CYAN}正在卸载 ShadowTLS...${PLAIN}"
    
    # 停止并禁用服务
    service_control "shadow-tls" "stop"
    systemctl disable shadow-tls 2>/dev/null
    
    # 删除服务文件
    rm -f "$STLS_SERVICE_PATH"
    
    # 删除二进制文件
    rm -f "$STLS_BIN_PATH"
    
    # 删除配置文件
    rm -rf "$STLS_CONFIG_DIR"
    
    # 删除日志文件
    rm -f "/var/log/shadowtls.log"
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    echo -e "${GREEN}ShadowTLS 已成功卸载${PLAIN}"
}



##################################################################################
##################################################################################

# 统一服务控制函数
service_control() {
    local service_name="$1"
    local action="$2"
    
    # 检查服务类型并验证安装状态
    case "$service_name" in
        "shadowsocks")
            if ! check_ssrust_installed; then
                echo -e "${RED}Shadowsocks 未安装，请先安装${PLAIN}"
                return 1
            fi
            ;;
        "shadow-tls")
            if ! check_shadowtls_installed; then
                echo -e "${RED}ShadowTLS 未安装，请先安装${PLAIN}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}不支持的服务类型: $service_name${PLAIN}"
            return 1
            ;;
    esac
    
    # 执行服务操作
    case "$action" in
        "start")
            echo -e "${CYAN}正在启动 $service_name 服务...${PLAIN}"
            systemctl start "$service_name"
            if systemctl is-active --quiet "$service_name"; then
                echo -e "${GREEN}$service_name 服务启动成功${PLAIN}"
            else
                echo -e "${RED}$service_name 服务启动失败${PLAIN}"
                systemctl status "$service_name" --no-pager -l
                return 1
            fi
            ;;
        "stop")
            echo -e "${CYAN}正在停止 $service_name 服务...${PLAIN}"
            systemctl stop "$service_name"
            if ! systemctl is-active --quiet "$service_name"; then
                echo -e "${GREEN}$service_name 服务已停止${PLAIN}"
            else
                echo -e "${RED}$service_name 服务停止失败${PLAIN}"
                return 1
            fi
            ;;
        "restart")
            echo -e "${CYAN}正在重启 $service_name 服务...${PLAIN}"
            systemctl restart "$service_name"
            if systemctl is-active --quiet "$service_name"; then
                echo -e "${GREEN}$service_name 服务重启成功${PLAIN}"
            else
                echo -e "${RED}$service_name 服务重启失败${PLAIN}"
                systemctl status "$service_name" --no-pager -l
                return 1
            fi
            ;;
        "status")
            echo -e "${CYAN}$service_name 服务状态：${PLAIN}"
            if systemctl is-active --quiet "$service_name"; then
                echo -e "${GREEN}● $service_name 服务正在运行${PLAIN}"
            else
                echo -e "${RED}● $service_name 服务未运行${PLAIN}"
            fi
            systemctl status "$service_name" --no-pager -l
            ;;
        *)
            echo -e "${RED}不支持的操作: $action${PLAIN}"
            echo -e "${YELLOW}支持的操作: start, stop, restart, status${PLAIN}"
            return 1
            ;;
    esac
}

# 生成客户端配置
generate_client_config() {
    show_banner

    if [ -f "$STLS_SERVICE_PATH" ]; then
        generate_ss_links
    elif [ -f "$SS_CONFIG_PATH" ]; then
        echo -e "${YELLOW}仅 Shadowsocks 配置：${PLAIN}"
        jq '.' "$SS_CONFIG_PATH" 2>/dev/null || cat "$SS_CONFIG_PATH"
    else
        echo -e "${RED}未找到任何配置${PLAIN}"
    fi
    
    pause_and_continue
}

# 一键安装
install_all() {
    echo -e "${CYAN}↓↓↓ 一键安装 Shadowsocks + ShadowTLS ↓↓↓${PLAIN}"
    
    # 安装 Shadowsocks
    if ! systemctl is-active --quiet shadowsocks; then
        echo -e "${YELLOW}正在安装 Shadowsocks...${PLAIN}"
        install_ssrust
        if [ $? -ne 0 ]; then
            echo -e "${RED}Shadowsocks 安装失败${PLAIN}"
            pause_and_continue
            return 1
        fi
    else
        echo -e "${GREEN}Shadowsocks 已安装并运行${PLAIN}"
    fi
    
    # 安装 ShadowTLS
    echo -e "${YELLOW}正在安装 ShadowTLS...${PLAIN}"
    install_shadowtls
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}一键安装完成！${PLAIN}"
    else
        echo -e "${RED}安装过程中出现错误${PLAIN}"
    fi
    
    pause_and_continue
}


# 完全卸载
uninstall_all() {
    # 检查安装状态
    local ss_installed=false
    local stls_installed=false
    
    if check_ssrust_installed; then
        ss_installed=true
    fi
    
    if check_shadowtls_installed; then
        stls_installed=true
    fi
    
    # 如果都未安装，提示并返回
    if ! $ss_installed && ! $stls_installed; then
        echo -e "${YELLOW}未检测到已安装的 Shadowsocks 或 ShadowTLS 服务${PLAIN}"
        pause_and_continue
        return 0
    fi
    
    # 显示当前安装状态
    echo -e "${CYAN}检测到以下已安装的服务：${PLAIN}"
    if $ss_installed; then
        echo -e "  ${GREEN}● Shadowsocks${PLAIN}"
    fi
    if $stls_installed; then
        echo -e "  ${GREEN}● ShadowTLS${PLAIN}"
    fi
    echo
    
    echo -e "${RED}警告：此操作将完全卸载上述服务及其配置文件${PLAIN}"
    read -rp "确认继续？(y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}正在卸载服务...${PLAIN}"
        
        # 卸载 ShadowTLS
        if $stls_installed; then
            echo -e "${YELLOW}正在卸载 ShadowTLS...${PLAIN}"
            uninstall_shadowtls
        fi
        
        # 卸载 Shadowsocks
        if $ss_installed; then
            echo -e "${YELLOW}正在卸载 Shadowsocks...${PLAIN}"
            uninstall_ssrust
        fi
        
        echo -e "${GREEN}所有服务已完全卸载${PLAIN}"
    else
        echo -e "${YELLOW}操作已取消${PLAIN}"
    fi
    
    pause_and_continue
}
# =============================================================================
# 主菜单模块
# =============================================================================

# 显示脚本信息
show_banner() {
    clear
    echo -e "${CYAN}==============================================================================${PLAIN}"
    echo -e "${WHITE} stls.sh - ShadowTLS V3 管理脚本${PLAIN}"
    echo -e "${WHITE} Version: $SCRIPT_VERSION${PLAIN}"
    echo -e "${CYAN}==============================================================================${PLAIN}"
    echo -e "${GREEN} 支持一键安装、升级和卸载 SS2022 + ShadowTLS ${PLAIN}"
    echo -e "${CYAN}==============================================================================${PLAIN}"
    echo
}

# 主菜单
main_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}请选择操作:${PLAIN}"
        echo -e "  ${GREEN}1)${PLAIN} Shadowsocks 管理"
        echo -e "  ${GREEN}2)${PLAIN} ShadowTLS 管理"
        echo -e "  ${GREEN}3)${PLAIN} 一键安装 (Shadowsocks + ShadowTLS)"
        echo -e "  ${GREEN}4)${PLAIN} 生成客户端配置"
        echo -e "  ${GREEN}5)${PLAIN} 系统工具"
        echo -e "  ${GREEN}9)${PLAIN} 完全卸载"
        echo -e "  ${GREEN}0)${PLAIN} 退出脚本"
        echo -e "${CYAN}==============================================================================${PLAIN}"
        
        local choice
        read -p "请输入选项 [0-9]: " choice
        
        case $choice in
            1) shadowsocks_menu ;;
            2) shadowtls_menu ;;
            3) install_all ;;
            4) generate_client_config ;;
            5) system_tools_menu ;;
            9) uninstall_all ;;
            0) exit 0 ;;
            *) 
                echo -e "${RED}无效选项，请重新选择${PLAIN}"
                sleep 2
                ;;
        esac
    done
}

# Shadowsocks子菜单
shadowsocks_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}=== Shadowsocks 服务管理 ===${PLAIN}"
        
        # 显示服务版本和状态信息
        if check_ssrust_installed; then
            local current_version=$(get_ssrust_version)
            echo -e "${CYAN}当前版本：${PLAIN}${GREEN}$current_version${PLAIN}"
            
            if systemctl is-active --quiet shadowsocks; then
                echo -e "${CYAN}服务状态：${PLAIN}${GREEN}● 正在运行${PLAIN}"
            else
                echo -e "${CYAN}服务状态：${PLAIN}${RED}● 未运行${PLAIN}"
            fi
        else
            echo -e "${CYAN}安装状态：${PLAIN}${YELLOW}● 未安装${PLAIN}"
        fi
        echo -e "${CYAN}==============================================================================${PLAIN}"
        
        echo -e "  ${GREEN}1)${PLAIN} 安装 Shadowsocks"
        echo -e "  ${GREEN}2)${PLAIN} 升级 Shadowsocks"
        echo -e "  ${GREEN}3)${PLAIN} 查看配置信息"
        echo -e "  ${GREEN}4)${PLAIN} 修改配置"
        echo -e "  ${GREEN}5)${PLAIN} 查看服务状态"
        echo -e "  ${GREEN}6)${PLAIN} 启动服务"
        echo -e "  ${GREEN}7)${PLAIN} 停止服务"
        echo -e "  ${GREEN}8)${PLAIN} 重启服务"
        echo -e "  ${GREEN}9)${PLAIN} 卸载 Shadowsocks"
        echo -e "  ${GREEN}0)${PLAIN} 返回主菜单"
        echo -e "${CYAN}==============================================================================${PLAIN}"
        
        local choice
        read -p "请输入选项 [0-9]: " choice
        
        case $choice in
            1) 
                install_ssrust
                pause_and_continue
                ;;
            2) 
                upgrade_ssrust
                pause_and_continue
                ;;
            3) 
                if [ -f "$SS_CONFIG_PATH" ]; then
                    echo -e "${CYAN}=== Shadowsocks 配置信息 ===${PLAIN}"
                    jq '.' "$SS_CONFIG_PATH" 2>/dev/null || cat "$SS_CONFIG_PATH"
                else
                    echo -e "${RED}Shadowsocks 未配置${PLAIN}"
                fi
                pause_and_continue
                ;;
            4) 
                modify_ssrust_config
                pause_and_continue
                ;;
            5) 
                service_control "shadowsocks" "status"
                pause_and_continue
                ;;
            6) 
                service_control "shadowsocks" "start"
                pause_and_continue
                ;;
            7) 
                service_control "shadowsocks" "stop"
                pause_and_continue
                ;;
            8) 
                service_control "shadowsocks" "restart"
                pause_and_continue
                ;;
            9) 
                uninstall_ssrust
                pause_and_continue
                ;;
            0) return ;;
            *) 
                echo -e "${RED}无效选项${PLAIN}"
                sleep 2
                ;;
        esac
    done
}


# ShadowTLS子菜单
shadowtls_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}=== ShadowTLS 服务管理 ===${PLAIN}"
        
        # 显示服务版本和状态信息
        if check_shadowtls_installed; then
            local current_version=$(get_shadowtls_version)
            echo -e "${CYAN}当前版本：${PLAIN}${GREEN}$current_version${PLAIN}"
            
            if systemctl is-active --quiet shadow-tls; then
                echo -e "${CYAN}服务状态：${PLAIN}${GREEN}● 正在运行${PLAIN}"
            else
                echo -e "${CYAN}服务状态：${PLAIN}${RED}● 未运行${PLAIN}"
            fi
        else
            echo -e "${CYAN}安装状态：${PLAIN}${YELLOW}● 未安装${PLAIN}"
        fi
        echo -e "${CYAN}==============================================================================${PLAIN}"
        
        echo -e "  ${GREEN}1)${PLAIN} 安装 ShadowTLS"
        echo -e "  ${GREEN}2)${PLAIN} 升级 ShadowTLS"
        echo -e "  ${GREEN}3)${PLAIN} 查看配置信息"
        echo -e "  ${GREEN}4)${PLAIN} 修改配置"
        echo -e "  ${GREEN}5)${PLAIN} 查看服务状态"
        echo -e "  ${GREEN}6)${PLAIN} 启动服务"
        echo -e "  ${GREEN}7)${PLAIN} 停止服务"
        echo -e "  ${GREEN}8)${PLAIN} 重启服务"
        echo -e "  ${GREEN}9)${PLAIN} 卸载 ShadowTLS"
        echo -e "  ${GREEN}0)${PLAIN} 返回主菜单"
        echo -e "${CYAN}==============================================================================${PLAIN}"
        
        local choice
        read -p "请输入选项 [0-9]: " choice
        
        case $choice in
            1) 
                install_shadowtls
                pause_and_continue
                ;;
            2) 
                upgrade_shadowtls
                pause_and_continue
                ;;
            3) 
                if [ ! -f "$STLS_SERVICE_PATH" ]; then
                    echo -e "${RED}ShadowTLS 未配置${PLAIN}"
                else
                    # 从服务文件中获取配置信息
                    local stls_port=$(get_shadowtls_config "port")
                    local stls_password=$(get_shadowtls_config "password")
                    local tls_domain=$(get_shadowtls_config "domain")
                    local ss_port=$(get_shadowtls_config "ss_port")
                    
                    # 显示 ShadowTLS 配置
                    echo -e "${CYAN}=== ShadowTLS 配置信息 ===${PLAIN}"
                    echo -e "  监听端口：${GREEN}$stls_port${PLAIN}"
                    echo -e "  连接密码：${GREEN}$stls_password${PLAIN}"
                    echo -e "  TLS 域名：${GREEN}$tls_domain${PLAIN}"
                    echo -e "  后端端口：${GREEN}$ss_port${PLAIN}"
                fi
                pause_and_continue
                ;;
            4) 
                modify_shadowtls_config
                ;;
            5) 
                service_control "shadow-tls" "status"
                pause_and_continue
                ;;
            6) 
                service_control "shadow-tls" "start"
                pause_and_continue
                ;;
            7) 
                service_control "shadow-tls" "stop"
                pause_and_continue
                ;;
            8) 
                service_control "shadow-tls" "restart"
                pause_and_continue
                ;;
            9) 
                uninstall_shadowtls
                pause_and_continue
                ;;
            0) return ;;
            *) 
                echo -e "${RED}无效选项${PLAIN}"
                sleep 2
                ;;
        esac
    done
}

# 系统工具菜单
system_tools_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}=== 系统工具 ===${PLAIN}"
        echo -e "  ${GREEN}1)${PLAIN} 查看系统信息"
        echo -e "  ${GREEN}2)${PLAIN} 查看网络状态"
        echo -e "  ${GREEN}3)${PLAIN} 查看服务日志"
        echo -e "  ${GREEN}4)${PLAIN} 防火墙管理"
        echo -e "  ${GREEN}5)${PLAIN} 系统优化"
        echo -e "  ${GREEN}0)${PLAIN} 返回主菜单"
        echo -e "${CYAN}==============================================================================${PLAIN}"
        
        local choice
        read -p "请输入选项 [0-5]: " choice
        
        case $choice in
            1) 
                show_system_info
                pause_and_continue
                ;;
            2) 
                show_network_status
                pause_and_continue
                ;;
            3) 
                show_service_logs
                pause_and_continue
                ;;
            4) 
                firewall_management
                pause_and_continue
                ;;
            5) 
                system_optimization
                pause_and_continue
                ;;
            0) return ;;
            *) 
                echo -e "${RED}无效选项${PLAIN}"
                sleep 2
                ;;
        esac
    done
}

# 暂停并继续
pause_and_continue() {
    echo
    read -n 1 -s -r -p "按任意键继续..."
}

# =============================================================================
# 脚本入口
# =============================================================================

# 主函数
main() {
    # 检查root权限
    check_root
    
    # 检测系统环境
    check_os

    # 检查包管理器
    check_package_manager
    
    # 安装依赖
    install_dependencies
    
    # 启动主菜单
    main_menu
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi