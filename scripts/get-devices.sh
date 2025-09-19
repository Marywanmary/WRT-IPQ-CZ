#!/bin/bash

# 从OpenWrt配置文件中提取设备名称列表
# 输出格式：JSON数组，例如：["jdcloud_re-ss-01","jdcloud_re-cs-02"]

CONFIG_FILE=$1

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file $CONFIG_FILE not found!"
    echo "[]"  # 输出空JSON数组
    exit 1
fi

# 从配置文件中提取设备名称
# 格式示例: CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y
# 我们需要提取 jdcloud_re-ss-01 部分
devices=$(grep "^CONFIG_TARGET_DEVICE_.*_DEVICE_.*=y$" "$CONFIG_FILE" | \
          sed -E 's/^CONFIG_TARGET_DEVICE_[^_]+_[^_]+_DEVICE_([^=]+)=y$/\1/' | \
          sort -u | tr '\n' ' ')

# 去除末尾空格
devices=$(echo "$devices" | sed 's/ *$//')

# 检查是否找到设备
if [ -z "$devices" ]; then
    echo "Warning: No devices found in config file $CONFIG_FILE"
    echo "[]"  # 输出空JSON数组
    exit 0
fi

# 将设备列表转换为JSON数组格式
# 使用printf确保没有多余的空格和换行
printf '["%s"]' $(echo "$devices" | sed 's/ /","/g')
