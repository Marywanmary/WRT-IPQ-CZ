#!/bin/bash
# OpenWrt 自定义脚本
# 严格错误退出机制
set -e

# 确保脚本有执行权限
chmod +x "$0"

echo "=== 执行自定义脚本 ==="

# 修改默认IP & 固件名称 & 编译署名
sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ Built by Mary')/g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 修改管理员密码和无线密码为空
sed -i 's/root:::0:0:99999:7:::/root:$1$0Vl0Zg1r$5mFVj5z8bV7J6X8Y9Z0a1:::0:0:99999:7:::/g' package/base-files/files/etc/shadow
sed -i 's/option password.*/option password ""/' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 移除要替换的包
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# Go & OpenList & ariang & frp & AdGuardHome & WolPlus & Lucky & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist
git_sparse_clone master https://github.com/laipeng668/packages net/ariang
git_sparse_clone master https://github.com/laipeng668/packages net/frp
mv -f package/frp feeds/packages/net/frp
git_sparse_clone master https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

# ====== Mary定制包 ======
git clone --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest package/netspeedtest
git clone --depth=1 https://github.com/sirpdboy/luci-app-partexp package/luci-app-partexp
git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan package/luci-app-taskplan
git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-timewol
git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus
git clone --depth=1 https://github.com/tailscale/tailscale package/tailscale
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-momo package/luci-app-momo
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki package/nikki
git clone --depth=1 https://github.com/vernesong/OpenClash package/OpenClash

# ====== 添加kenzok8软件源并且让它的优先级最低 ======
git clone --depth=1 https://github.com/kenzok8/small-package package/small8

# 更新feeds
echo "=== 更新feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

echo "=== 自定义脚本执行完成 ==="
