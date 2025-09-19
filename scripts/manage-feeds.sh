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

# 2. 添加第三方软件源到feeds.conf.default（按优先级从高到低）
cat > feeds.conf.default << 'EOF'
src-link packages
src-link luci
# # Go 语言支持（解决 golang/host 依赖问题）
# src-git golang https://github.com/sbwml/packages_lang_golang;25.x
src-git tailscale https://github.com/tailscale/tailscale
src-git taskplan https://github.com/sirpdboy/luci-app-taskplan
src-git lucky https://github.com/gdy666/luci-app-lucky
src-git momo https://github.com/nikkinikki-org/OpenWrt-momo
# 注意：small-package放在最后，优先级最低
src-git small-package https://github.com/kenzok8/small-package
EOF

echo "第三方软件源配置已添加到feeds.conf.default"

# 3. 同步到feeds.conf
echo "同步feeds.conf..."
cp feeds.conf.default feeds.conf
echo "✓ 已同步feeds.conf"

# 4. 验证源配置
echo "验证源配置..."
echo "===== 当前源配置 ====="
cat feeds.conf
echo "======================="

# 5. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 6. 按照作者建议删除冲突插件
echo "按照作者建议删除冲突插件..."
CONFLICT_PACKAGES="base-files dnsmasq firewall* fullconenat libnftnl nftables ppp opkg ucl upx vsftpd* miniupnpd-iptables wireless-regdb"

for pkg in $CONFLICT_PACKAGES; do
    if [ -d "feeds/small-package/$pkg" ]; then
        echo "删除冲突插件: feeds/small-package/$pkg"
        rm -rf "feeds/small-package/$pkg"
    fi
done

# 7. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 8. 安装软件源
echo "安装软件源..."
./scripts/feeds install -a

# # 9. 验证 Go 语言支持
# echo "验证 Go 语言支持..."
# if [ -d "feeds/packages.lang_golang" ]; then
#     echo "✓ Go 语言支持已正确添加"
# else
#     echo "⚠ Go 语言支持可能有问题，检查 feeds 更新结果"
# fi

# 10. 修复配置文件（如果存在）
if [ -f ".config" ]; then
    echo "修复配置文件..."
    cp .config .config.backup
    
    # 重新生成配置
    make defconfig
    
    # 检查是否有语法错误
    if ! make defconfig >/dev/null 2>&1; then
        echo "⚠ 配置文件可能有语法错误，尝试修复..."
        # 如果仍有问题，可以在这里添加特定的修复逻辑
    fi
fi

echo "===== 软件源管理完成 ====="
