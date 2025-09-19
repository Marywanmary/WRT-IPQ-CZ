#!/bin/bash

CONFIG_FILE=$1

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file $CONFIG_FILE not found!"
    exit 1
fi

# 从配置文件中提取设备名称
# 格式示例: CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y
# 我们需要提取 jdcloud_re-ss-01 部分
devices=$(grep "^CONFIG_TARGET_DEVICE_.*_DEVICE_.*=y$" "$CONFIG_FILE" | \
          sed -E 's/^CONFIG_TARGET_DEVICE_[^_]+_[^_]+_DEVICE_([^=]+)=y$/\1/' | \
          sort -u)

# 输出设备列表，用空格分隔
echo "$devices"
