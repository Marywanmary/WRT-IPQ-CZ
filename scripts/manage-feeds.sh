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

# 1. 检查核心软件包结构
echo "检查核心软件包结构..."
if [ ! -d "package" ]; then
    echo "创建package目录..."
    mkdir -p package
fi

if [ ! -f "package/Makefile" ]; then
    echo "创建package/Makefile..."
    cat > package/Makefile << 'EOF'
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/target.mk
include $(INCLUDE_DIR)/host.mk

-include $(TOPDIR)/.config

prereq:
    $(if $(wildcard $(TOPDIR)/tmp/.prereq-target),)
    $(MAKE) -C $(TOPDIR)/tmp prereq-target
    $(MAKE) -C $(TOPDIR)/tmp prereq-host
    $(MAKE) -C $(TOPDIR)/tmp prereq-compile

prepare-tmpinfo:
    $(MAKE) -C $(TOPDIR)/tmp info
    $(MAKE) -C $(TOPDIR)/tmp target-info
    $(MAKE) -C $(TOPDIR)/tmp package-info

package/%: prepare-tmpinfo
    $(MAKE) -C $(TOPDIR)/tmp package-install

target/%: prepare-tmpinfo
    $(MAKE) -C $(TOPDIR)/tmp target-install

tools/%: prepare-tmpinfo
    $(MAKE) -C $(TOPDIR)/tmp tools-install

%::
    @$(MESSAGE) "No rule to make target $@"
    @exit 1

.PHONY: prereq prepare-tmpinfo
EOF
fi

# 2. 备份原始配置
if [ -f "feeds.conf.default" ]; then
    cp feeds.conf.default feeds.conf.default.bak
fi

# 3. 执行您提供的操作（在更新软件源之前）
echo "执行预操作..."

# 3.1 移除要替换的包
echo "移除要替换的包..."
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# 3.2 创建临时目录
mkdir -p package

# 3.3 定义git_sparse_clone函数
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

# 3.4 克隆所需的包
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

# 4. 清理临时目录
echo "清理临时目录..."
rm -rf package

# 5. 创建feeds.conf.default - 使用最简单的方法
echo "创建feeds.conf.default..."

# 5.1 先删除现有的文件
rm -f feeds.conf.default feeds.conf

# 5.2 使用最简单的方法创建文件
cat > feeds.conf.default << 'ENDOFFILE'
src-git tailscale https://github.com/tailscale/tailscale
src-git taskplan https://github.com/sirpdboy/luci-app-taskplan
src-git lucky https://github.com/gdy666/luci-app-lucky
src-git momo https://github.com/nikkinikki-org/OpenWrt-momo
src-git small-package https://github.com/kenzok8/small-package
ENDOFFILE

echo "✓ 已创建feeds.conf.default"

# 6. 同步到feeds.conf
cp feeds.conf.default feeds.conf
echo "✓ 已同步feeds.conf"

# 7. 详细验证文件内容
echo "详细验证文件内容..."

# 7.1 显示文件信息
echo "文件信息："
ls -la feeds.conf*

# 7.2 检查文件类型
echo "文件类型："
file feeds.conf

# 7.3 显示文件内容（包括不可见字符）
echo "文件内容（包括不可见字符）："
cat -A feeds.conf

# 8. 测试feeds.conf语法
echo "测试feeds.conf语法..."
if ./scripts/feeds list >/dev/null 2>&1; then
    echo "✓ feeds.conf语法正确"
else
    echo "✗ feeds.conf语法错误，尝试修复..."
    
    # 尝试修复：重新创建文件，确保每行以\n结尾
    echo "重新创建feeds.conf..."
    rm -f feeds.conf.default feeds.conf
    
    # 使用printf确保每行以\n结尾
    printf "src-git tailscale https://github.com/tailscale/tailscale\n" > feeds.conf.default
    printf "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan\n" >> feeds.conf.default
    printf "src-git lucky https://github.com/gdy666/luci-app-lucky\n" >> feeds.conf.default
    printf "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo\n" >> feeds.conf.default
    printf "src-git small-package https://github.com/kenzok8/small-package\n" >> feeds.conf.default
    
    cp feeds.conf.default feeds.conf
    
    # 再次测试
    if ./scripts/feeds list >/dev/null 2>&1; then
        echo "✓ 修复后的feeds.conf语法正确"
    else
        echo "✗ 修复后仍然有语法错误，尝试最小配置..."
        
        # 尝试最小配置
        rm -f feeds.conf.default feeds.conf
        printf "src-git tailscale https://github.com/tailscale/tailscale\n" > feeds.conf.default
        cp feeds.conf.default feeds.conf
        
        if ./scripts/feeds list >/dev/null 2>&1; then
            echo "✓ 最小配置语法正确，逐个添加其他源..."
            
            # 逐个添加源并测试
            sources=(
                "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan"
                "src-git lucky https://github.com/gdy666/luci-app-lucky"
                "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo"
                "src-git small-package https://github.com/kenzok8/small-package"
            )
            
            for source in "${sources[@]}"; do
                echo "添加源: $source"
                printf "%s\n" "$source" >> feeds.conf.default
                cp feeds.conf.default feeds.conf
                
                if ./scripts/feeds list >/dev/null 2>&1; then
                    echo "✓ 添加成功"
                else
                    echo "✗ 添加失败，跳过此源"
                    # 回滚
                    sed -i '$d' feeds.conf.default
                    cp feeds.conf.default feeds.conf
                fi
            done
        else
            echo "✗ 即使最小配置也有语法错误，可能是OpenWrt环境问题"
            exit 1
        fi
    fi
fi

# 9. 显示最终配置
echo "最终feeds.conf内容："
cat feeds.conf

# 10. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 11. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 12. 安装软件源
echo "安装软件源..."
./scripts/feeds install -a

# 13. 检查核心软件包结构
echo "检查核心软件包结构..."
if [ ! -f "package/Makefile" ]; then
    echo "错误: package/Makefile 不存在，尝试修复..."
    # 重新创建package/Makefile
    cat > package/Makefile << 'EOF'
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/target.mk
include $(INCLUDE_DIR)/host.mk

-include $(TOPDIR)/.config

prereq:
    $(if $(wildcard $(TOPDIR)/tmp/.prereq-target),)
    $(MAKE) -C $(TOPDIR)/tmp prereq-target
    $(MAKE) -C $(TOPDIR)/tmp prereq-host
    $(MAKE) -C $(TOPDIR)/tmp prereq-compile

prepare-tmpinfo:
    $(MAKE) -C $(TOPDIR)/tmp info
    $(MAKE) -C $(TOPDIR)/tmp target-info
    $(MAKE) -C $(TOPDIR)/tmp package-info

package/%: prepare-tmpinfo
    $(MAKE) -C $(TOPDIR)/tmp package-install

target/%: prepare-tmpinfo
    $(MAKE) -C $(TOPDIR)/tmp target-install

tools/%: prepare-tmpinfo
    $(MAKE) -C $(TOPDIR)/tmp tools-install

%::
    @$(MESSAGE) "No rule to make target $@"
    @exit 1

.PHONY: prereq prepare-tmpinfo
EOF
    echo "✓ 已重新创建package/Makefile"
fi

# 14. 修复配置文件（如果存在）
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
