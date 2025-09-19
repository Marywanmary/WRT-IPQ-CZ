#!/bin/bash

OPENWRT_DIR=$1

# 检查OpenWrt目录是否存在
if [ ! -d "$OPENWRT_DIR" ]; then
    echo "Error: OpenWrt directory $OPENWRT_DIR not found!"
    exit 1
fi

# 备份原始feeds.conf
cp "$OPENWRT_DIR/feeds.conf.default" "$OPENWRT_DIR/feeds.conf.default.bak"

# 添加第三方软件源（按优先级从高到低）
cat >> "$OPENWRT_DIR/feeds.conf" << EOF
# 第三方软件源（优先级从高到低）
src-git tailscale https://github.com/tailscale/tailscale
src-git taskplan https://github.com/sirpdboy/luci-app-taskplan
src-git lucky https://github.com/gdy666/luci-app-lucky
src-git momo https://github.com/nikkinikki-org/OpenWrt-momo
src-git small https://github.com/kenzok8/small-package
EOF

echo "Custom feeds added to $OPENWRT_DIR/feeds.conf"
