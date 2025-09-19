#!/bin/bash

# 设置默认配置脚本
# 用法: ./scripts/set-default-config.sh <openwrt_dir>

OPENWRT_DIR=$1

# 检查OpenWrt目录是否存在
if [ ! -d "$OPENWRT_DIR" ]; then
    echo "Error: OpenWrt directory $OPENWRT_DIR not found!"
    exit 1
fi

# 设置默认LAN地址
echo "设置默认管理地址为: 192.168.111.1"
sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.111.1/g' "$OPENWRT_DIR/package/base-files/files/bin/config_generate"

# 设置默认主机名
echo "设置默认主机名为: WRT"
sed -i "s/hostname='.*'/hostname='WRT'/g" "$OPENWRT_DIR/package/base-files/files/bin/config_generate"

# 设置无线密码为空
echo "设置无线密码为空"
if [ -f "$OPENWRT_DIR/package/kernel/mac80211/files/lib/wifi/mac80211.sh" ]; then
    sed -i 's/encryption=psk.*/encryption=none/g' "$OPENWRT_DIR/package/kernel/mac80211/files/lib/wifi/mac80211.sh"
fi

# # 设置默认无线SSID
# echo "设置默认无线SSID为: OpenWrt"
# if [ -f "$OPENWRT_DIR/package/kernel/mac80211/files/lib/wifi/mac80211.sh" ]; then
#     sed -i 's/ssid=.*/ssid=OpenWrt/g' "$OPENWRT_DIR/package/kernel/mac80211/files/lib/wifi/mac80211.sh"
# fi

echo "默认配置设置完成"
