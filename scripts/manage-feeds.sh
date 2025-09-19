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

# 2. 添加第三方软件源（按优先级从高到低）
cat > feeds.conf << 'EOF'
src-link packages
src-link luci
# Go 语言支持（解决 golang/host 依赖问题）
src-git golang https://github.com/sbwml/packages_lang_golang;25.x
src-git tailscale https://github.com/tailscale/tailscale
src-git taskplan https://github.com/sirpdboy/luci-app-taskplan
src-git lucky https://github.com/gdy666/luci-app-lucky
src-git momo https://github.com/nikkinikki-org/OpenWrt-momo
# 注意：kenzok8/small-package 放在最后，优先级最低
src-git small https://github.com/kenzok8/small-package
EOF

echo "第三方软件源配置完成"

# 3. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 4. 定义需要跳过的软件包列表
echo "定义需要跳过的软件包列表..."
SKIP_PACKAGES="v2ray-core v2ray-geodata v2ray-plugin v2raya webdav2 xray-core xray-plugin"

# 添加需要跳过的luci包
LUCI_PACKAGES="luci-app-passwall luci-app-ddns-go luci-app-rclone luci-app-ssr-plus luci-app-vssr luci-app-daed luci-app-dae luci-app-alist luci-app-homeproxy luci-app-haproxy-tcp luci-app-openclash luci-app-mihomo luci-app-appfilter luci-app-msd_lite"

# 添加需要跳过的网络包
PACKAGES_NET="haproxy xray-core xray-plugin dns2socks alist hysteria mosdns adguardhome ddns-go naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-plugin tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev dae daed mihomo geoview tailscale open-app-filter msd_lite"

# 添加需要跳过的工具包
PACKAGES_UTILS="cups"

# 添加需要跳过的small8包
SMALL8_PACKAGES="ppp firewall dae daed daed-next libnftnl nftables dnsmasq luci-app-alist alist opkg smartdns luci-app-smartdns"

# 合并所有需要跳过的包
ALL_SKIP_PACKAGES="$SKIP_PACKAGES $LUCI_PACKAGES $PACKAGES_NET $PACKAGES_UTILS $SMALL8_PACKAGES"

# 5. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 6. 逐个安装软件包，跳过指定的包
echo "安装软件源（跳过指定包）..."
# 获取所有软件包列表
PACKAGES=$(./scripts/feeds list -a | cut -d' ' -f1)

# 安装软件包，跳过有问题的软件包
for package in $PACKAGES; do
    skip=0
    for skip_pkg in $ALL_SKIP_PACKAGES; do
        if [ "$package" = "$skip_pkg" ]; then
            echo "跳过软件包: $package"
            skip=1
            break
        fi
    done
    
    if [ $skip -eq 0 ]; then
        echo "安装软件包: $package"
        ./scripts/feeds install "$package"
    fi
done

# 7. 验证 Go 语言支持
echo "验证 Go 语言支持..."
if [ -d "feeds/packages.lang_golang" ]; then
    echo "✓ Go 语言支持已正确添加"
else
    echo "⚠ Go 语言支持可能有问题，检查 feeds 更新结果"
fi

# 8. 修复配置文件（如果存在）
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
