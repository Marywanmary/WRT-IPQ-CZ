#!/bin/bash

# 生成发布说明
# 用法: ./generate-release-notes.sh <chip>

CHIP=$1

# 获取当前日期
CURRENT_DATE=$(date +%Y-%m-%d)

# 获取内核版本（从任意一个配置文件中提取）
KERNEL_VERSION=$(grep "CONFIG_LINUX_" openwrt/.config | head -1 | cut -d'=' -f2 | tr -d '"')

# 获取编译的luci-app列表
LUCI_APPS=$(grep "CONFIG_PACKAGE_luci-app-" openwrt/.config | grep "=y" | cut -d'=' -f1 | sed 's/CONFIG_PACKAGE_//' | sort)

# 生成发布说明
cat << EOF
# ${CHIP^^} 固件发布

## 基本信息
- **发布日期**: $CURRENT_DATE
- **内核版本**: $KERNEL_VERSION
- **作者**: Mary

## 默认配置
- **管理地址**: 192.168.111.1
- **用户名**: root
- **密码**: none
- **WIFI密码**: 12345678

## 支持设备
- 京东云亚瑟 (jdcloud_re-ss-01)
- 京东云雅典娜 (jdcloud_re-cs-02)

## 第三方软件源
- Tailscale: https://github.com/tailscale/tailscale
- TaskPlan: https://github.com/sirpdboy/luci-app-taskplan
- Lucky: https://github.com/gdy666/luci-app-lucky
- Momo: https://github.com/nikkinikki-org/OpenWrt-momo
- Small Package: https://github.com/kenzok8/small-package (优先级最低)

## 编译优化
- 编译顺序：Ultra -> Max -> Pro（优化缓存命中率）
- Ultra配置包含最多软件包，为后续编译提供完整缓存

## 编译的Luci应用
$(for app in $LUCI_APPS; do echo "- $app"; done)

## 文件说明
- **固件文件**: 
  - 命名规则: 分支缩写-${CHIP}-设备名称-固件类型-配置类型.bin
  - 示例: immwrt-${CHIP}-jdcloud_re-ss-01-sysupgrade-Pro.bin
- **配置文件包**: ${CHIP}-config.tar.gz
- **日志文件包**: ${CHIP}-log.tar.gz
- **软件包**: ${CHIP}-app.tar.gz

## 使用说明
1. 下载对应设备的固件文件
2. 通过设备管理界面或命令行刷入固件
3. 使用默认配置登录管理界面

## 注意事项
- 首次刷机建议使用factory固件
- 后续升级可使用sysupgrade固件
- 刷机前请备份重要配置
- 第三方软件包冲突时，kenzok8/small-package的包会被其他源替代
EOF
