#!/bin/bash

# 合并OpenWrt配置文件
# 合并优先级：软件包配置 > 分支配置 > 芯片配置
# 用法: ./scripts/merge-configs.sh <repo_short> <config_type> <device> <chip>

REPO_SHORT=$1
CONFIG_TYPE=$2
DEVICE=$3
CHIP=$4

# 使用绝对路径设置配置文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_CONFIG="$SCRIPT_DIR/../configs/${CHIP}_base.config"
BRANCH_CONFIG="$SCRIPT_DIR/../configs/${REPO_SHORT}_base.config"
PKG_CONFIG="$SCRIPT_DIR/../configs/${CONFIG_TYPE}.config"
OUTPUT_CONFIG="$SCRIPT_DIR/../.config"

echo "正在合并配置文件: $CHIP $REPO_SHORT $CONFIG_TYPE"

# 检查基础配置文件是否存在
if [ ! -f "$BASE_CONFIG" ]; then
    echo "Error: Base config file $BASE_CONFIG not found!"
    exit 1
fi

# 合并配置文件（优先级：软件包配置 > 分支配置 > 芯片配置）
cat "$BASE_CONFIG" > "$OUTPUT_CONFIG"

if [ -f "$BRANCH_CONFIG" ]; then
    cat "$BRANCH_CONFIG" >> "$OUTPUT_CONFIG"
    echo "已添加分支配置: $BRANCH_CONFIG"
else
    echo "警告: 分支配置文件不存在: $BRANCH_CONFIG"
fi

if [ -f "$PKG_CONFIG" ]; then
    cat "$PKG_CONFIG" >> "$OUTPUT_CONFIG"
    echo "已添加软件包配置: $PKG_CONFIG"
else
    echo "警告: 软件包配置文件不存在: $PKG_CONFIG"
fi

# 根据设备设置特定配置
case $DEVICE in
    "jdcloud_re-ss-01")
        echo "CONFIG_TARGET_DEVICE_qualcommax_${CHIP}_DEVICE_jdcloud_re-ss-01=y" >> "$OUTPUT_CONFIG"
        echo "# CONFIG_TARGET_DEVICE_PACKAGES_qualcommax_${CHIP}_DEVICE_jdcloud_re-ss_01=\"\"" >> "$OUTPUT_CONFIG"
        ;;
    "jdcloud_re-cs-02")
        echo "CONFIG_TARGET_DEVICE_qualcommax_${CHIP}_DEVICE_jdcloud_re-cs-02=y" >> "$OUTPUT_CONFIG"
        echo "CONFIG_TARGET_DEVICE_PACKAGES_qualcommax_${CHIP}_DEVICE_jdcloud_re-cs-02=\"luci-app-athena-led luci-i18n-athena-led-zh-cn\"" >> "$OUTPUT_CONFIG"
        ;;
    *)
        echo "Error: Unknown device $DEVICE"
        exit 1
        ;;
esac

echo "Configuration merged for $REPO_SHORT-$CONFIG_TYPE-$DEVICE ($CHIP)"
