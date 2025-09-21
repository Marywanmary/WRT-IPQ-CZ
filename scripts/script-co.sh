#!/bin/bash
set -euo pipefail

# 修改默认IP、主机名、编译署名
[ -f package/base-files/files/bin/config_generate ] && sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate || true
[ -f package/base-files/files/bin/config_generate ] && sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate || true
[ -f feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js ] && \
    sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ Built by Mary')/g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js || true

# 设空密码
[ -f package/base-files/files/etc/shadow ] && \
    sed -i 's/root::0:0:99999:7:::/root::0:0:99999:7:::/g' package/base-files/files/etc/shadow || true

# 清理冲突包
UNWANTED_PKGS=(luci-app-appfilter luci-app-frpc luci-app-frps open-app-filter adguardhome ariang frp golang)
for pkg in "${UNWANTED_PKGS[@]}"; do
  rm -rf package/small8/$pkg feeds/luci/applications/$pkg feeds/packages/net/$pkg package/$pkg || true
done

# 稀疏克隆函数
git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# 克隆定制包
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist
git_sparse_clone frp https://github.com/laipeng668/packages net/frp
mkdir -p feeds/packages/net
mv -f package/frp feeds/packages/net/frp

git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mkdir -p feeds/luci/applications
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps

git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

# Mary定制包
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

# 再次清理冲突包
UNWANTED_PKGS=(luci-app-torbp luci-app-alist luci-app-qbittorrent luci-app-nat6-helper ua2f natmap)
for pkg in "${UNWANTED_PKGS[@]}"; do
  rm -rf package/small8/$pkg feeds/luci/applications/$pkg feeds/packages/net/$pkg package/$pkg || true
done

# feeds更新与安装
[ -x ./scripts/feeds ] && ./scripts/feeds update -a && ./scripts/feeds install -a
