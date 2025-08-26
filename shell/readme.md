# stls.sh - ShadowTLS V3 管理脚本

## 📋 脚本概述

`stls.sh` 是一个功能强大的 ShadowTLS V3 管理脚本，专为简化 Shadowsocks 2022 + ShadowTLS 的部署和管理而设计。该脚本提供了一键式解决方案，支持自动化安装、升级、配置管理和系统优化，让用户能够轻松搭建高性能的代理服务。

## 🎯 核心功能

### 🚀 一键部署
- **自动化安装**: 自动检测系统环境，安装所需依赖
- **智能配置**: 根据系统环境自动生成最优配置
- **版本管理**: 支持最新版本检测和自动升级

### 📦 软件管理
- **Shadowsocks Rust**: 完整的管理生命周期（安装/升级/卸载）
- **ShadowTLS**: 专业的 TLS 混淆服务管理
- **服务控制**: 启动/停止/重启/状态查看

### 📱 客户端配置
- **多平台支持**: Shadowrocket/Surge/Loon/Clash/Sing-box 等
- **二维码生成**: 自动生成配置二维码
- **链接生成**: 一键生成 SS + ShadowTLS 合并链接
- **配置导出**: 支持多种客户端配置格式

## 快速开始

```bash
# 下载并运行脚本
bash <(curl -sL https://raw.githubusercontent.com/oopsunix/script/main/shell/stls.sh)
```

---

**免责声明**: 本脚本仅供学习和研究使用，请遵守当地法律法规。使用者需自行承担使用风险。