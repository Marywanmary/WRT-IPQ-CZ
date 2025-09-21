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

# 移除要替换的包
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# ========== 1. 递归依赖检测与移除 ==========
CONFIG_FILE="openwrt/.config"
PKG_IN="tmp/.config-package.in"
PROBLEM_PKGS=()
SELF_DEP_PKGS=()
LOOP_DEP_PKGS=()

echo "===== [递归依赖包自动检测&移除] ====="

# 1.1 检测已知递归依赖包（可手动维护补充）
KNOWN_PROBLEM_PKGS=(luci-app-torbp luci-app-alist luci-app-qbittorrent luci-app-nat6-helper ua2f natmap)
for pkg in "${KNOWN_PROBLEM_PKGS[@]}"; do
  if grep -q "CONFIG_PACKAGE_${pkg}=y" "$CONFIG_FILE" 2>/dev/null; then
    PROBLEM_PKGS+=("$pkg")
    sed -i "/CONFIG_PACKAGE_${pkg}=y/d" "$CONFIG_FILE"
  fi
done

# 1.2 自动检测自依赖（PACKAGE_xxx depends/selects PACKAGE_xxx）
if [[ -f "$PKG_IN" ]]; then
  while read -r sym; do
    pkg="${sym#PACKAGE_}"
    if grep -Pzo "config $sym\n(.|\n)*depends on $sym" "$PKG_IN"; then
      SELF_DEP_PKGS+=("$pkg")
      sed -i "/CONFIG_${sym}=y/d" "$CONFIG_FILE"
    fi
  done < <(grep -Po '^config PACKAGE_[^\s]+' "$PKG_IN" | cut -d' ' -f2)
fi

# 1.3 自动检测互相select导致的环依赖（A select B, B select A）
if [[ -f "$PKG_IN" ]]; then
  # 提取所有 select 关系
  awk '/^config PACKAGE_/ {pkg=$2} /select PACKAGE_/ {print pkg, $2}' "$PKG_IN" | while read a b; do
    # b 格式是PACKAGE_xxx
    # 检查 b 是否也 select a
    if grep -Pzo "config $b\n(.|\n)*select $a" "$PKG_IN"; then
      pkg1="${a#PACKAGE_}"
      pkg2="${b#PACKAGE_}"
      LOOP_DEP_PKGS+=("${pkg1}<->${pkg2}")
      sed -i "/CONFIG_${a}=y/d" "$CONFIG_FILE"
      sed -i "/CONFIG_${b}=y/d" "$CONFIG_FILE"
    fi
  done
fi

# 1.4 输出递归依赖清单
if [[ ${#PROBLEM_PKGS[@]} -eq 0 && ${#SELF_DEP_PKGS[@]} -eq 0 && ${#LOOP_DEP_PKGS[@]} -eq 0 ]]; then
  echo "未检测到递归依赖包，无需处理。"
else
  echo "已自动移除以下递归依赖包，避免编译失败："
  for pkg in "${PROBLEM_PKGS[@]}"; do
    echo "  - $pkg (已知问题包)"
  done
  for pkg in "${SELF_DEP_PKGS[@]}"; do
    echo "  - $pkg (自依赖包)"
  done
  for loop in "${LOOP_DEP_PKGS[@]}"; do
    echo "  - $loop (互相select导致的环依赖)"
  done
fi
echo "===== [递归依赖包检测&修正完成] ====="

# ========== 2. 包优先级自动调整 ==========
# 只保留主feeds和small8同名包时优先主feeds
echo "===== [包优先级自动调整] ====="
if [ -d package/small8 ]; then
  for spkg in package/small8/*; do
    [ -d "$spkg" ] || continue
    pname=$(basename "$spkg")
    # 主feeds有同名包则移除small8的
    if [ -d "feeds/packages/$pname" ] || [ -d "feeds/luci/applications/$pname" ]; then
      echo "检测到 $pname 主feeds和small8均有，保留主feeds，移除small8/$pname"
      rm -rf "package/small8/$pname"
    fi
  done
fi
echo "===== [优先级调整完成] ====="

# ========== 3. 缺失依赖包自动移除 ==========
echo "===== [缺失依赖包自动批量移除] ====="
# 检查所有Makefile依赖的包是否存在，不存在则移除上层包
MISSING_DEP_PKGS=()
find package/small8 -type f -name 'Makefile' | while read mkfile; do
  # 搜索 DEPENDS或者select PACKAGE_ 依赖的包名
  grep -E 'DEPENDS|select PACKAGE_' "$mkfile" | grep -oE '[a-zA-Z0-9_-]+' | while read dep; do
    # 判断是否主feeds或small8有该包，否则缺失
    if [[ "$dep" =~ ^(luci-app-|lib|kmod-|shadowsocks|v2ray|trojan|boost|nginx|openclash|etc)$ ]]; then continue; fi
    if ! find feeds/ package/small8/ -type d -name "$dep" | grep -q .; then
      parentdir=$(dirname "$mkfile")
      if [[ ! " ${MISSING_DEP_PKGS[*]} " =~ " $parentdir " ]]; then
        MISSING_DEP_PKGS+=("$parentdir")
        echo "检测到 $parentdir 依赖缺失包: $dep，已移除"
        rm -rf "$parentdir"
      fi
    fi
  done
done
echo "===== [缺失依赖包处理完成] ====="

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# 创建必要的目录结构
mkdir -p feeds/packages/net
mkdir -p feeds/packages/lang
mkdir -p feeds/luci/applications

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

# 修改管理员密码和无线密码为空
sed -i 's/root:::0:0:99999:7:::/root:$1$0Vl0Zg1r$5mFVj5z8bV7J6X8Y9Z0a1:::0:0:99999:7:::/g' package/base-files/files/etc/shadow

# 修改无线密码（检查文件是否存在）
echo "=== 修改无线密码 ==="
if [ -f "package/kernel/mac80211/files/lib/wifi/mac80211.sh" ]; then
    sed -i 's/option password.*/option password ""/' package/kernel/mac80211/files/lib/wifi/mac80211.sh
else
    echo "警告: 找不到 mac80211.sh 文件，跳过修改无线密码"
fi

# 修改编译署名（在feeds安装后执行）
echo "=== 修改编译署名 ==="
if [ -f "feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js" ]; then
    sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ Built by Mary')/g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
else
    echo "警告: 找不到 luci-mod-status 文件，跳过修改编译署名"
fi

# 处理依赖问题
echo "=== 处理依赖问题 ==="
# 创建boost-system包的虚拟包
mkdir -p package/boost-system
cat > package/boost-system/Makefile << 'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=boost-system
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/boost-system
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Boost.System (virtual package)
  DEPENDS:=+boost
endef

define Package/boost-system/description
 This is a virtual package for boost-system.
endef

define Build/Compile
endef

define Package/boost-system/install
endef

$(eval $(call BuildPackage,boost-system))
EOF

# 创建libpcre包的虚拟包
mkdir -p package/libpcre
cat > package/libpcre/Makefile << 'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=libpcre
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/libpcre
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=PCRE (virtual package)
  DEPENDS:=+libpcre2
endef

define Package/libpcre/description
 This is a virtual package for libpcre.
endef

define Build/Compile
endef

define Package/libpcre/install
endef

$(eval $(call BuildPackage,libpcre))
EOF

echo "=== 自定义脚本执行完成 ==="
