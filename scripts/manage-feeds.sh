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

# 1. 检查OpenWrt核心结构
echo "检查OpenWrt核心结构..."

# 1.1 检查是否存在include目录
if [ ! -d "include" ]; then
    echo "错误: include目录不存在，可能不是有效的OpenWrt源码目录"
    echo "当前目录: $(pwd)"
    echo "目录内容:"
    ls -la
    exit 1
fi

# 1.2 检查是否存在关键文件
for file in include/rules.mk include/target.mk include/host.mk; do
    if [ ! -f "$file" ]; then
        echo "错误: $file不存在，可能不是有效的OpenWrt源码目录"
        echo "当前目录: $(pwd)"
        echo "include目录内容:"
        ls -la include/
        exit 1
    fi
done

echo "✓ OpenWrt核心结构检查通过"

# 2. 确保package目录存在并创建package/Makefile
echo "确保package目录存在并创建package/Makefile..."

# 2.1 创建package目录（如果不存在）
mkdir -p package

# 2.2 创建package/Makefile
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

echo "✓ 已创建package/Makefile"

# 3. 备份原始配置
if [ -f "feeds.conf.default" ]; then
    cp feeds.conf.default feeds.conf.default.bak
fi

# 4. 执行预操作（在更新软件源之前）
echo "执行预操作..."

# 4.1 移除要替换的包（只移除feeds目录中的，不移除package目录）
echo "移除要替换的包..."
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# 4.2 创建临时目录（在package目录之外）
mkdir -p /tmp/openwrt_packages

# 4.3 定义git_sparse_clone函数
git_sparse_clone() {
    branch="$1" repourl="$2" && shift 2
    echo "克隆稀疏仓库: $repourl (分支: $branch)"
    git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
    repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
    cd $repodir && git sparse-checkout set $@
    mv -f $@ /tmp/openwrt_packages
    cd .. && rm -rf $repodir
    echo "稀疏克隆完成: $@"
}

# 4.4 克隆所需的包到临时目录
echo "克隆所需的包..."

# Go语言支持 - 优先克隆
echo "克隆golang包..."
git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

# OpenList
echo "克隆openlist包..."
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 /tmp/openwrt_packages/openlist

# ariang
echo "克隆ariang包..."
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang

# frp
echo "克隆frp包..."
git_sparse_clone frp https://github.com/laipeng668/packages net/frp
mv -f /tmp/openwrt_packages/frp feeds/packages/net/frp

# luci-app-frpc/frps
echo "克隆luci-app-frpc/frps包..."
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mv -f /tmp/openwrt_packages/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f /tmp/openwrt_packages/luci-app-frps feeds/luci/applications/luci-app-frps

# AdGuardHome
echo "克隆AdGuardHome包..."
git_sparse_clone master https://github.com/kenzok8/openwrt-packages adguardhome luci-app-adguardhome

# WolPlus
echo "克隆WolPlus包..."
git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus

# Lucky
echo "克隆Lucky包..."
git clone --depth=1 https://github.com/gdy666/luci-app-lucky /tmp/openwrt_packages/luci-app-lucky

# OpenAppFilter
echo "克隆OpenAppFilter包..."
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git /tmp/openwrt_packages/OpenAppFilter

# GecoosAC
echo "克隆GecoosAC包..."
git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac /tmp/openwrt_packages/openwrt-gecoosac

# Athena LED
echo "克隆Athena LED包..."
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led /tmp/openwrt_packages/luci-app-athena-led
chmod +x /tmp/openwrt_packages/luci-app-athena-led/root/etc/init.d/athena_led /tmp/openwrt_packages/luci-app-athena-led/root/usr/sbin/athena-led

# 5. 将临时目录中的包移动到package目录
echo "将临时目录中的包移动到package目录..."
if [ -d "/tmp/openwrt_packages" ] && [ "$(ls -A /tmp/openwrt_packages)" ]; then
    mv /tmp/openwrt_packages/* package/
    echo "✓ 已移动所有包到package目录"
else
    echo "⚠ 临时目录为空，无需移动"
fi

# 6. 清理临时目录
echo "清理临时目录..."
rm -rf /tmp/openwrt_packages

# 7. 创建feeds.conf.default - 包含golang源
echo "创建feeds.conf.default..."

# 7.1 先删除现有的文件
rm -f feeds.conf.default feeds.conf

# 7.2 使用最简单的方法创建文件，包含golang源
cat > feeds.conf.default << 'ENDOFFILE'
src-git golang https://github.com/sbwml/packages_lang_golang;25.x
src-git tailscale https://github.com/tailscale/tailscale
src-git taskplan https://github.com/sirpdboy/luci-app-taskplan
src-git lucky https://github.com/gdy666/luci-app-lucky
src-git momo https://github.com/nikkinikki-org/OpenWrt-momo
src-git small-package https://github.com/kenzok8/small-package
ENDOFFILE

echo "✓ 已创建feeds.conf.default（包含golang源）"

# 8. 同步到feeds.conf
cp feeds.conf.default feeds.conf
echo "✓ 已同步feeds.conf"

# 9. 验证package/Makefile
echo "验证package/Makefile..."
if [ -f "package/Makefile" ]; then
    echo "✓ package/Makefile存在"
else
    echo "✗ package/Makefile不存在，重新创建..."
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

# 10. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 11. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 12. 安装软件源
echo "安装软件源..."
./scripts/feeds install -a

# 13. 验证Go语言支持
echo "验证Go语言支持..."
if [ -d "feeds/packages.lang_golang" ]; then
    echo "✓ Go 语言支持已正确添加"
else
    echo "⚠ Go 语言支持可能有问题，检查 feeds 更新结果"
fi

# 14. 再次验证package/Makefile
echo "再次验证package/Makefile..."
if [ -f "package/Makefile" ]; then
    echo "✓ package/Makefile存在"
    echo "package/Makefile内容预览："
    head -10 package/Makefile
else
    echo "✗ package/Makefile不存在，重新创建..."
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

# 15. 最终验证
echo "最终验证..."
echo "当前目录: $(pwd)"
echo "package/Makefile存在: $(test -f package/Makefile && echo '是' || echo '否')"
echo "feeds.conf存在: $(test -f feeds.conf && echo '是' || echo '否')"

echo "===== 软件源管理完成 ====="
