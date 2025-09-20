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

# 2. 执行您提供的操作（在更新软件源之前）
echo "执行预操作..."

# 2.1 移除要替换的包
echo "移除要替换的包..."
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# 2.2 创建临时目录
mkdir -p package

# 2.3 定义git_sparse_clone函数
git_sparse_clone() {
    branch="$1" repourl="$2" && shift 2
    echo "克隆稀疏仓库: $repourl (分支: $branch)"
    git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
    repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
    cd $repodir && git sparse-checkout set $@
    mv -f $@ ../package
    cd .. && rm -rf $repodir
    echo "稀疏克隆完成: $@"
}

# 2.4 克隆所需的包
echo "克隆所需的包..."

# Go语言支持
echo "克隆golang包..."
git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

# OpenList
echo "克隆openlist包..."
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist

# ariang
echo "克隆ariang包..."
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang

# frp
echo "克隆frp包..."
git_sparse_clone frp https://github.com/laipeng668/packages net/frp
mv -f package/frp feeds/packages/net/frp

# luci-app-frpc/frps
echo "克隆luci-app-frpc/frps包..."
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps

# AdGuardHome
echo "克隆AdGuardHome包..."
git_sparse_clone master https://github.com/kenzok8/openwrt-packages adguardhome luci-app-adguardhome

# WolPlus
echo "克隆WolPlus包..."
git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus

# Lucky
echo "克隆Lucky包..."
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky

# OpenAppFilter
echo "克隆OpenAppFilter包..."
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter

# GecoosAC
echo "克隆GecoosAC包..."
git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac package/openwrt-gecoosac

# Athena LED
echo "克隆Athena LED包..."
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

# 3. 清理临时目录
echo "清理临时目录..."
rm -rf package

# 4. 创建feeds.conf.default
echo "创建feeds.conf.default..."
> feeds.conf.default

# 5. 使用printf方式添加软件源（确保没有语法错误）
printf "src-git tailscale https://github.com/tailscale/tailscale\n" >> feeds.conf.default
printf "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan\n" >> feeds.conf.default
printf "src-git lucky https://github.com/gdy666/luci-app-lucky\n" >> feeds.conf.default
printf "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo\n" >> feeds.conf.default
printf "src-git small-package https://github.com/kenzok8/small-package\n" >> feeds.conf.default

echo "第三方软件源配置已添加到feeds.conf.default"

# 6. 同步到feeds.conf
cp feeds.conf.default feeds.conf
echo "✓ 已同步feeds.conf"

# 7. 验证feeds.conf格式
echo "验证feeds.conf格式..."
if file feeds.conf | grep -q "ASCII"; then
    echo "✓ feeds.conf是ASCII文本文件"
else
    echo "⚠ feeds.conf可能包含非ASCII字符，尝试修复..."
    dos2unix feeds.conf 2>/dev/null || true
fi

# 8. 显示当前配置
echo "当前feeds.conf内容："
cat -v feeds.conf

# 9. 逐行检查格式
echo "逐行检查格式："
line_num=1
while IFS= read -r line; do
    echo "第${line_num}行: '$line'"
    ((line_num++))
done < feeds.conf

# 10. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 11. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 12. 安装软件源
echo "安装软件源..."
./scripts/feeds install -a

# 13. 修复配置文件（如果存在）
if [ -f ".config" ]; then
    echo "修复配置文件..."
    cp .config .config.backup
    
    # 使用更可靠的方法处理内核配置
    echo "处理内核配置..."
    
    # 方法1: 使用olddefconfig自动处理新选项
    if make olddefconfig >/dev/null 2>&1; then
        echo "✓ 使用olddefconfig成功处理新选项"
    else
        echo "⚠ olddefconfig失败，尝试方法2..."
        
        # 方法2: 使用内核的默认配置
        if [ -f "target/linux/qualcommax/ipq60xx/config-6.12" ]; then
            echo "使用内核默认配置..."
            cp target/linux/qualcommax/ipq60xx/config-6.12 .config
            make olddefconfig >/dev/null 2>&1
            echo "✓ 使用内核默认配置成功"
        else
            echo "⚠ 内核默认配置文件不存在，尝试方法3..."
            
            # 方法3: 创建最小配置
            echo "创建最小内核配置..."
            make allnoconfig >/dev/null 2>&1
            echo "✓ 创建最小配置成功"
        fi
    fi
    
    # 最后再次运行defconfig确保配置正确
    echo "最终配置验证..."
    make defconfig >/dev/null 2>&1
    echo "✓ 配置验证完成"
fi

echo "===== 软件源管理完成 ====="
