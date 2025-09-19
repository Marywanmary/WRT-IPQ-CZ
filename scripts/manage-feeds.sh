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

# 2. 创建临时文件
TEMP_FEEDS=$(mktemp)

# 3. 逐行添加源配置（避免heredoc可能引入的问题）
echo "src-link packages" > "$TEMP_FEEDS"
echo "src-link luci" >> "$TEMP_FEEDS"
# echo "# Go 语言支持（解决 golang/host 依赖问题）" >> "$TEMP_FEEDS"
# echo "src-git golang https://github.com/sbwml/packages_lang_golang;25.x" >> "$TEMP_FEEDS"
echo "src-git tailscale https://github.com/tailscale/tailscale" >> "$TEMP_FEEDS"
echo "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan" >> "$TEMP_FEEDS"
echo "src-git lucky https://github.com/gdy666/luci-app-lucky" >> "$TEMP_FEEDS"
echo "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo" >> "$TEMP_FEEDS"
echo "# 注意：small-package放在最后，优先级最低" >> "$TEMP_FEEDS"
echo "src-git small-package https://github.com/kenzok8/small-package" >> "$TEMP_FEEDS"

# 4. 验证临时文件内容
echo "验证临时文件内容..."
cat "$TEMP_FEEDS"
echo "======================="

# 5. 替换feeds.conf.default
cp "$TEMP_FEEDS" feeds.conf.default
echo "✓ 已更新feeds.conf.default"

# 6. 同步到feeds.conf
cp feeds.conf.default feeds.conf
echo "✓ 已同步feeds.conf"

# 7. 清理临时文件
rm -f "$TEMP_FEEDS"

# 8. 验证源配置
echo "验证源配置..."
echo "===== 当前feeds.conf内容 ====="
cat feeds.conf
echo "============================"

# 9. 检查语法错误
echo "检查feeds.conf语法..."
if ./scripts/feeds list >/dev/null 2>&1; then
    echo "✓ feeds.conf语法正确"
else
    echo "✗ feeds.conf语法错误，请检查内容"
    exit 1
fi

# 10. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 11. 按照作者建议删除冲突插件
echo "按照作者建议删除冲突插件..."
CONFLICT_PACKAGES="base-files dnsmasq firewall* fullconenat libnftnl nftables ppp opkg ucl upx vsftpd* miniupnpd-iptables wireless-regdb"

for pkg in $CONFLICT_PACKAGES; do
    if [ -d "feeds/small-package/$pkg" ]; then
        echo "删除冲突插件: feeds/small-package/$pkg"
        rm -rf "feeds/small-package/$pkg"
    fi
done

# 12. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 13. 安装软件源
echo "安装软件源..."
./scripts/feeds install -a

# # 14. 验证 Go 语言支持
# echo "验证 Go 语言支持..."
# if [ -d "feeds/packages.lang_golang" ]; then
#     echo "✓ Go 语言支持已正确添加"
# else
#     echo "⚠ Go 语言支持可能有问题，检查 feeds 更新结果"
# fi

# 15. 修复配置文件（如果存在）
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
