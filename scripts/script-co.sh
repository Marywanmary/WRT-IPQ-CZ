#!/bin/bash
# OpenWrt 自定义脚本
# 严格错误退出机制
set -euo pipefail

# 确保脚本有执行权限
chmod +x "$0"

echo "=== 执行自定义脚本 ==="

# 定义常用路径变量
PACKAGE_DIR="package"
FEEDS_DIR="feeds"
SMALL8_DIR="${PACKAGE_DIR}/small8"

# 设置git配置，避免认证问题
setup_git() {
    echo "正在配置git..."
    git config --global http.sslverify false
    git config --global url."https://github.com/".insteadOf "git@github.com:"
    git config --global http.postBuffer 524288000
    git config --global core.compression 0
    echo "Git配置完成"
}

# 获取仓库的默认分支
get_default_branch() {
    local repo_url=$1
    local default_branch=""
    
    # 尝试获取默认分支
    if command -v git &> /dev/null; then
        default_branch=$(git ls-remote --symref "$repo_url" HEAD | grep -o 'refs/heads/[^\t]*' | sed 's|refs/heads/||' | head -n1)
    fi
    
    # 如果无法获取默认分支，则尝试常见分支名
    if [ -z "$default_branch" ]; then
        for branch in main master openwrt-21.02 openwrt-22.03; do
            if git ls-remote --heads "$repo_url" "refs/heads/$branch" | grep -q "refs/heads/$branch"; then
                default_branch=$branch
                break
            fi
        done
    fi
    
    echo "$default_branch"
}

# 改进的git克隆函数
git_clone_with_retry() {
    local url=$1
    local dir=$2
    local branch=${3:-}
    local retries=3
    local count=0
    local last_error=0
    
    echo "正在克隆: $url -> $dir"
    
    # 如果没有指定分支，尝试获取默认分支
    if [ -z "$branch" ]; then
        branch=$(get_default_branch "$url")
        echo "检测到默认分支: $branch"
    fi
    
    while [ $count -lt $retries ]; do
        if [ -n "$branch" ]; then
            if git clone --depth=1 -b "$branch" "$url" "$dir" 2>/dev/null; then
                echo "克隆成功: $url (分支: $branch)"
                return 0
            fi
        else
            # 如果没有指定分支且无法获取默认分支，尝试不指定分支克隆
            if git clone --depth=1 "$url" "$dir" 2>/dev/null; then
                echo "克隆成功: $url (默认分支)"
                return 0
            fi
        fi
        
        last_error=$?
        count=$((count+1))
        echo "克隆失败 (退出码: $last_error), 重试 $count/$retries..."
        sleep 2
    done
    
    echo "错误: 克隆失败，已重试 $retries 次"
    return $last_error
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

# 移除要替换的包
echo "正在移除要替换的包..."
rm -rf "${FEEDS_DIR}/luci/applications/luci-app-appfilter"
rm -rf "${FEEDS_DIR}/luci/applications/luci-app-frpc"
rm -rf "${FEEDS_DIR}/luci/applications/luci-app-frps"
rm -rf "${FEEDS_DIR}/packages/net/open-app-filter"
rm -rf "${FEEDS_DIR}/packages/net/adguardhome"
rm -rf "${FEEDS_DIR}/packages/net/ariang"
rm -rf "${FEEDS_DIR}/packages/net/frp"
rm -rf "${FEEDS_DIR}/packages/lang/golang"
rm -rf "${FEEDS_DIR}/packages/net/speedtest-cli"
echo "包移除完成"

# 设置git配置
setup_git

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
    local branch="$1"
    local repourl="$2"
    shift 2
    local repodir=$(basename "$repourl")
    
    echo "正在稀疏克隆: $repourl (分支: $branch)"
    if ! git_clone_with_retry "$repourl" "$repodir" "$branch"; then
        echo "错误: 稀疏克隆失败"
        return 1
    fi
    
    cd "$repodir" || { echo "错误: 无法进入目录 $repodir"; return 1; }
    echo "正在设置稀疏检出: $@"
    if ! git sparse-checkout set "$@" 2>/dev/null; then
        echo "错误: 稀疏检出设置失败"
        cd ..
        return 1
    fi
    
    echo "正在移动文件到 ${PACKAGE_DIR}"
    if ! mv -f "$@" "../${PACKAGE_DIR}" 2>/dev/null; then
        echo "错误: 文件移动失败"
        cd ..
        return 1
    fi
    
    cd .. || { echo "错误: 无法返回上级目录"; return 1; }
    rm -rf "$repodir"
    echo "稀疏克隆完成: $repourl"
}

# Go & OpenList & ariang & frp & AdGuardHome & WolPlus & Lucky & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
echo "正在克隆基础包..."
if ! git_clone_with_retry "https://github.com/sbwml/packages_lang_golang" "${FEEDS_DIR}/packages/lang/golang"; then
    echo "警告: golang语言包克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/sbwml/luci-app-openlist2" "${PACKAGE_DIR}/openlist"; then
    echo "警告: openlist克隆失败，跳过"
fi

if ! git_sparse_clone "ariang" "https://github.com/laipeng668/packages" "net/ariang"; then
    echo "警告: ariang稀疏克隆失败，跳过"
fi

# 修复frp包移动问题
echo "正在处理frp包..."
if ! git_sparse_clone "frp" "https://github.com/laipeng668/packages" "net/frp"; then
    echo "警告: frp包稀疏克隆失败，跳过"
else
    # 确保目标目录存在
    mkdir -p "${FEEDS_DIR}/packages/net"
    
    # 检查源目录是否存在
    if [ -d "${PACKAGE_DIR}/frp" ]; then
        mv -f "${PACKAGE_DIR}/frp" "${FEEDS_DIR}/packages/net/frp"
        echo "frp包移动完成"
    else
        echo "警告: frp目录不存在，跳过移动"
    fi
fi

# 修复frp luci应用移动问题
echo "正在处理frp luci应用..."
if ! git_sparse_clone "frp" "https://github.com/laipeng668/luci" "applications/luci-app-frpc" "applications/luci-app-frps"; then
    echo "警告: frp luci应用稀疏克隆失败，跳过"
else
    # 确保目标目录存在
    mkdir -p "${FEEDS_DIR}/luci/applications"
    
    # 检查并移动luci-app-frpc
    if [ -d "${PACKAGE_DIR}/luci-app-frpc" ]; then
        mv -f "${PACKAGE_DIR}/luci-app-frpc" "${FEEDS_DIR}/luci/applications/luci-app-frpc"
        echo "luci-app-frpc移动完成"
    else
        echo "警告: luci-app-frpc目录不存在，跳过移动"
    fi
    
    # 检查并移动luci-app-frps
    if [ -d "${PACKAGE_DIR}/luci-app-frps" ]; then
        mv -f "${PACKAGE_DIR}/luci-app-frps" "${FEEDS_DIR}/luci/applications/luci-app-frps"
        echo "luci-app-frps移动完成"
    else
        echo "警告: luci-app-frps目录不存在，跳过移动"
    fi
fi

if ! git_sparse_clone "main" "https://github.com/VIKINGYFY/packages" "luci-app-wolplus"; then
    echo "警告: wolplus稀疏克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/gdy666/luci-app-lucky" "${PACKAGE_DIR}/luci-app-lucky"; then
    echo "警告: lucky克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/destan19/OpenAppFilter.git" "${PACKAGE_DIR}/OpenAppFilter"; then
    echo "警告: OpenAppFilter克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/lwb1978/openwrt-gecoosac" "${PACKAGE_DIR}/openwrt-gecoosac"; then
    echo "警告: gecoosac克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/NONGFAH/luci-app-athena-led" "${PACKAGE_DIR}/luci-app-athena-led"; then
    echo "警告: athena-led克隆失败，跳过"
else
    chmod +x "${PACKAGE_DIR}/luci-app-athena-led/root/etc/init.d/athena_led" "${PACKAGE_DIR}/luci-app-athena-led/root/usr/sbin/athena-led"
fi

# 克隆Mary定制包（只选择与内核编译无关的包）
echo "=== 克隆Mary定制包 ==="
if ! git_clone_with_retry "https://github.com/sirpdboy/luci-app-netspeedtest" "${PACKAGE_DIR}/netspeedtest"; then
    echo "警告: netspeedtest克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/sirpdboy/luci-app-partexp" "${PACKAGE_DIR}/luci-app-partexp"; then
    echo "警告: partexp克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/sirpdboy/luci-app-taskplan" "${PACKAGE_DIR}/luci-app-taskplan"; then
    echo "警告: taskplan克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/tailscale/tailscale" "${PACKAGE_DIR}/tailscale"; then
    echo "警告: tailscale克隆失败，跳过"
fi

# 避免重复克隆lucky
if [ ! -d "${PACKAGE_DIR}/luci-app-lucky" ]; then
    if ! git_clone_with_retry "https://github.com/gdy666/luci-app-lucky" "${PACKAGE_DIR}/luci-app-lucky"; then
        echo "警告: lucky克隆失败，跳过"
    fi
fi

if ! git_clone_with_retry "https://github.com/nikkinikki-org/OpenWrt-momo" "${PACKAGE_DIR}/luci-app-momo"; then
    echo "警告: momo克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/nikkinikki-org/OpenWrt-nikki" "${PACKAGE_DIR}/nikki"; then
    echo "警告: nikki克隆失败，跳过"
fi

if ! git_clone_with_retry "https://github.com/vernesong/OpenClash" "${PACKAGE_DIR}/OpenClash"; then
    echo "警告: OpenClash克隆失败，跳过"
fi

# 避免重复克隆OpenAppFilter
if [ ! -d "${PACKAGE_DIR}/OpenAppFilter" ]; then
    if ! git_clone_with_retry "https://github.com/destan19/OpenAppFilter.git" "${PACKAGE_DIR}/OpenAppFilter"; then
        echo "警告: OpenAppFilter克隆失败，跳过"
    fi
fi

# ====== 添加kenzok8软件源并且让它的优先级最低 ======
echo "正在添加kenzok8软件源..."
if ! git_clone_with_retry "https://github.com/kenzok8/small-package" "${SMALL8_DIR}"; then
    echo "警告: kenzok8软件源克隆失败，跳过"
fi

# 清理冲突包
echo "正在清理冲突包..."
UNWANTED_PKGS=(luci-app-torbp luci-app-alist luci-app-qbittorrent luci-app-nat6-helper ua2f natmap)
for pkg in "${UNWANTED_PKGS[@]}"; do
  rm -rf "${SMALL8_DIR}/$pkg" "${FEEDS_DIR}/luci/applications/$pkg" "${FEEDS_DIR}/packages/net/$pkg" "${PACKAGE_DIR}/$pkg" || true
done
echo "冲突包清理完成"

# 更新feeds
echo "=== 更新feeds ==="
if [ -x ./scripts/feeds ]; then
    if ! ./scripts/feeds update -a; then
        echo "警告: feeds更新失败，尝试继续"
    fi
    
    echo "正在安装feeds..."
    if ! ./scripts/feeds install -a; then
        echo "警告: feeds安装失败，尝试逐个安装..."
        
        # 获取所有feeds列表
        FEEDS_LIST=$(./scripts/feeds list | awk '{print $1}')
        
        # 逐个安装feeds
        for feed in $FEEDS_LIST; do
            echo "正在安装feed: $feed"
            if ! ./scripts/feeds install "$feed"; then
                echo "警告: 安装feed $feed 失败"
            fi
        done
    fi
else
    echo "错误: feeds脚本不存在"
    exit 1
fi

echo "=== 自定义脚本执行完成 ==="
