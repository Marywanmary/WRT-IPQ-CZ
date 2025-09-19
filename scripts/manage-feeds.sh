#!/bin/bash

# 统一管理第三方软件源
# 用法: ./scripts/manage-feeds.sh <openwrt_dir>

OPENWRT_DIR=$1

# 检查OpenWrt目录是否存在
if [ ! -d "$OPENWRT_DIR" ]; then
    echo "Error: OpenWrt directory $OPENWRT_DIR not found!"
    exit 1
fi

cd "$OPENWRT_DIR"

echo "===== 管理第三方软件源 ====="

# 1. 备份原始配置
if [ -f "feeds.conf.default" ]; then
    cp feeds.conf.default feeds.conf.default.bak
fi

# 2. 清空并创建新的feeds.conf.default
> feeds.conf.default

# 3. 使用echo方式添加软件源
echo "src-git tailscale https://github.com/tailscale/tailscale" >> feeds.conf.default
echo "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan" >> feeds.conf.default
echo "src-git lucky https://github.com/gdy666/luci-app-lucky" >> feeds.conf.default
echo "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo" >> feeds.conf.default
echo "src-git small-package https://github.com/kenzok8/small-package" >> feeds.conf.default

echo "第三方软件源配置已添加到feeds.conf.default"

# 4. 同步到feeds.conf
cp feeds.conf.default feeds.conf
echo "✓ 已同步feeds.conf"

# 5. 显示当前配置
echo "当前feeds.conf内容："
cat feeds.conf

# 6. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 7. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 8. 安装软件源
echo "安装软件源..."
./scripts/feeds install -a

# 9. 修复配置文件（如果存在）
if [ -f ".config" ]; then
    echo "修复配置文件..."
    cp .config .config.backup
    
    # 重新生成配置
    make defconfig
fi

echo "===== 软件源管理完成 ====="
