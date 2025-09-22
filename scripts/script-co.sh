#!/bin/bash
set -euo pipefail

# 定义常用路径变量
PACKAGE_DIR="package"
FEEDS_DIR="feeds"
SMALL8_DIR="${PACKAGE_DIR}/small8"

# 错误处理函数
handle_error() {
    local exit_code=$?
    echo "错误: 命令执行失败，退出码: $exit_code"
    exit $exit_code
}

# 改进的git clone函数
git_clone_with_retry() {
    local url=$1
    local dir=$2
    local branch=${3:-master}
    local retries=3
    local count=0
    
    while [ $count -lt $retries ]; do
        if git clone --depth=1 -b $branch "$url" "$dir"; then
            return 0
        fi
        count=$((count+1))
        echo "克隆失败，重试 $count/$retries..."
        sleep 2
    done
    
    handle_error
}

# 修改默认IP、主机名、编译署名
[ -f "${PACKAGE_DIR}/base-files/files/bin/config_generate" ] && \
    sed -i 's/192.168.1.1/192.168.111.1/g' "${PACKAGE_DIR}/base-files/files/bin/config_generate" || true
[ -f "${PACKAGE_DIR}/base-files/files/bin/config_generate" ] && \
    sed -i "s/hostname='.*'/hostname='WRT'/g" "${PACKAGE_DIR}/base-files/files/bin/config_generate" || true
[ -f "${FEEDS_DIR}/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js" ] && \
    sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ Built by Mary')/g" \
    "${FEEDS_DIR}/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js" || true

# 设空密码
[ -f "${PACKAGE_DIR}/base-files/files/etc/shadow" ] && \
    sed -i 's/root::0:0:99999:7:::/root::0:0:99999:7:::/g' "${PACKAGE_DIR}/base-files/files/etc/shadow" || true

# 清理冲突包
UNWANTED_PKGS=(luci-app-appfilter luci-app-frpc luci-app-frps open-app-filter adguardhome ariang frp golang)
for pkg in "${UNWANTED_PKGS[@]}"; do
  rm -rf "${PACKAGE_DIR}/small8/$pkg" "${FEEDS_DIR}/luci/applications/$pkg" "${FEEDS_DIR}/packages/net/$pkg" "${PACKAGE_DIR}/$pkg" || true
done

# 稀疏克隆函数
git_sparse_clone() {
    branch="$1" repourl="$2" && shift 2
    repodir=$(basename "$repourl")
    
    git_clone_with_retry "$repourl" "$repodir" "$branch"
    cd "$repodir" || handle_error
    git sparse-checkout set "$@"
    mv -f "$@" "../${PACKAGE_DIR}"
    cd .. || handle_error
    rm -rf "$repodir"
}

# 添加缺失的依赖包
echo "正在添加缺失的依赖包..."
git_clone_with_retry "https://github.com/shadowsocks/openwrt-shadowsocks-libev.git" "${PACKAGE_DIR}/shadowsocks-libev"
git_clone_with_retry "https://github.com/openwrt/packages.git" "${PACKAGE_DIR}/boost" "openwrt-21.02"
cd "${PACKAGE_DIR}/boost" && git sparse-checkout set libs/boost && cd ../..
git_clone_with_retry "https://github.com/destan19/urllogger.git" "${PACKAGE_DIR}/urllogger"
echo "依赖包添加完成"

# 克隆定制包
git_clone_with_retry "https://github.com/sbwml/packages_lang_golang" "${FEEDS_DIR}/packages/lang/golang" "24.x"
git_clone_with_retry "https://github.com/sbwml/luci-app-openlist2" "${PACKAGE_DIR}/openlist"
git_sparse_clone "frp" "https://github.com/laipeng668/packages" "net/frp"
mkdir -p "${FEEDS_DIR}/packages/net"
mv -f "${PACKAGE_DIR}/frp" "${FEEDS_DIR}/packages/net/frp"

git_sparse_clone "frp" "https://github.com/laipeng668/luci" "applications/luci-app-frpc" "applications/luci-app-frps"
mkdir -p "${FEEDS_DIR}/luci/applications"
mv -f "${PACKAGE_DIR}/luci-app-frpc" "${FEEDS_DIR}/luci/applications/luci-app-frpc"
mv -f "${PACKAGE_DIR}/luci-app-frps" "${FEEDS_DIR}/luci/applications/luci-app-frps"

git_clone_with_retry "https://github.com/NONGFAH/luci-app-athena-led" "${PACKAGE_DIR}/luci-app-athena-led"
chmod +x "${PACKAGE_DIR}/luci-app-athena-led/root/etc/init.d/athena_led" "${PACKAGE_DIR}/luci-app-athena-led/root/usr/sbin/athena-led"

# Mary定制包
git_clone_with_retry "https://github.com/sirpdboy/luci-app-netspeedtest" "${PACKAGE_DIR}/netspeedtest"
git_clone_with_retry "https://github.com/sirpdboy/luci-app-partexp" "${PACKAGE_DIR}/luci-app-partexp"
git_clone_with_retry "https://github.com/sirpdboy/luci-app-taskplan" "${PACKAGE_DIR}/luci-app-taskplan"
git_sparse_clone "main" "https://github.com/VIKINGYFY/packages" "luci-app-timewol"
git_sparse_clone "main" "https://github.com/VIKINGYFY/packages" "luci-app-wolplus"
git_clone_with_retry "https://github.com/tailscale/tailscale" "${PACKAGE_DIR}/tailscale"
git_clone_with_retry "https://github.com/gdy666/luci-app-lucky" "${PACKAGE_DIR}/luci-app-lucky"
git_clone_with_retry "https://github.com/nikkinikki-org/OpenWrt-momo" "${PACKAGE_DIR}/luci-app-momo"
git_clone_with_retry "https://github.com/nikkinikki-org/OpenWrt-nikki" "${PACKAGE_DIR}/nikki"
git_clone_with_retry "https://github.com/vernesong/OpenClash" "${PACKAGE_DIR}/OpenClash"
git_clone_with_retry "https://github.com/destan19/OpenAppFilter.git" "${PACKAGE_DIR}/OpenAppFilter"

# 添加kenzok8软件源并且让它的优先级最低
git_clone_with_retry "https://github.com/kenzok8/small-package" "${SMALL8_DIR}"

# 再次清理冲突包
UNWANTED_PKGS=(luci-app-torbp luci-app-alist luci-app-qbittorrent luci-app-nat6-helper ua2f natmap)
for pkg in "${UNWANTED_PKGS[@]}"; do
  rm -rf "${SMALL8_DIR}/$pkg" "${FEEDS_DIR}/luci/applications/$pkg" "${FEEDS_DIR}/packages/net/$pkg" "${PACKAGE_DIR}/$pkg" || true
done

# feeds更新与安装
echo "正在更新feeds..."
if [ -x ./scripts/feeds ]; then
    ./scripts/feeds update -a
    
    echo "正在安装feeds..."
    if ! ./scripts/feeds install -a; then
        echo "警告: feeds安装失败，尝试逐个安装..."
        
        # 获取所有feeds列表
        FEEDS_LIST=$(./scripts/feeds list | awk '{print $1}')
        
        # 逐个安装feeds
        for feed in $FEEDS_LIST; do
            echo "正在安装feed: $feed"
            ./scripts/feeds install "$feed" || echo "警告: 安装feed $feed 失败"
        done
    fi
else
    echo "错误: feeds脚本不存在"
    handle_error
fi

echo "Feeds更新与安装完成"
