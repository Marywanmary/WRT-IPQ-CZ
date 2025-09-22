#!/bin/bash
# OpenWrt固件准备脚本
# 作者: Mary
# 功能: 准备OpenWrt编译环境，包括下载源码、添加自定义包等

# 严格错误退出机制 - 任何命令返回非零状态码都会立即退出脚本
set -euo pipefail

# 设置日志文件
LOG_FILE="prepare.log"
ERROR_LOG_FILE="prepare-error.log"

# 初始化日志文件
echo "===== 准备脚本日志 - $(date) =====" > "$LOG_FILE"
echo "===== 错误日志 - $(date) =====" > "$ERROR_LOG_FILE"

# 日志函数
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

error_log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $message" | tee -a "$LOG_FILE" "$ERROR_LOG_FILE"
}

# 错误处理函数
handle_error() {
    local exit_code=$?
    local line_number=$1
    error_log "脚本在第 $line_number 行退出，退出代码: $exit_code"
    exit $exit_code
}

# 设置错误陷阱 - 当脚本出错时调用handle_error函数
trap 'handle_error $LINENO' ERR

# 开始准备
log "开始准备OpenWrt编译环境"

# 修改默认IP & 固件名称 & 编译署名
log "修改默认配置"
sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate
# 禁用修改编译署名的sed命令
# sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ Built by Mary')/g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 修改管理员密码为空
log "修改管理员密码为空"
sed -i 's/root:::0:0:99999:7:::/root:$1$Vd3dV5bF$XxvYzJ7s8uK9kLpMnQoNj0:0:0:99999:7:::/g' package/base-files/files/etc/shadow

# 修改无线密码为空
log "修改无线密码为空"
# 查找无线配置文件并修改
WIFI_CONFIG_FILES=$(find . -name "*.sh" -path "*/mac80211/*" 2>/dev/null | head -1)
if [ -n "$WIFI_CONFIG_FILES" ]; then
    log "找到无线配置文件: $WIFI_CONFIG_FILES"
    sed -i 's/option encryption .psk2+ccmp./option encryption .none./g' "$WIFI_CONFIG_FILES"
else
    log "未找到无线配置文件，跳过修改无线密码"
fi

# 移除要替换的包
log "移除要替换的包"
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
    local branch="$1"
    local repourl="$2"
    shift 2
    local dirs=("$@")
    
    # 保存当前目录和日志文件路径
    local current_dir="$(pwd)"
    local log_file="$current_dir/$LOG_FILE"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 稀疏克隆: $repourl (分支: $branch, 目录: ${dirs[*]})" | tee -a "$log_file"
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 克隆仓库
    git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
    
    # 获取仓库名称
    local repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
    cd "$repodir"
    
    # 设置稀疏检出
    git sparse-checkout set "${dirs[@]}"
    
    # 返回原目录
    cd "$current_dir"
    
    # 移动文件到目标目录
    for dir in "${dirs[@]}"; do
        if [ -d "$temp_dir/$repodir/$dir" ]; then
            # 确保目标目录存在
            local target_dir="package/$dir"
            mkdir -p "$(dirname "$target_dir")"
            
            # 移动文件
            mv -f "$temp_dir/$repodir/$dir" "$target_dir"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已移动: $dir" | tee -a "$log_file"
        fi
    done
    
    # 清理临时目录
    rm -rf "$temp_dir"
}

# Go & OpenList & ariang & frp & AdGuardHome & WolPlus & Lucky & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
log "克隆自定义软件包"
git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang

# 克隆frp包并直接移动到feeds/packages/net
mkdir -p feeds/packages/net
git_sparse_clone frp https://github.com/laipeng668/packages net/frp
# 将package/net/frp移动到feeds/packages/net
if [ -d "package/net/frp" ]; then
    mv -f package/net/frp feeds/packages/net/
    log "已移动frp到feeds/packages/net/"
fi

# 确保目标目录存在
mkdir -p feeds/luci/applications
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
# 将luci-app-frpc和luci-app-frps移动到feeds/luci/applications
if [ -d "package/applications/luci-app-frpc" ]; then
    mv -f package/applications/luci-app-frpc feeds/luci/applications/
    log "已移动luci-app-frpc到feeds/luci/applications/"
fi
if [ -d "package/applications/luci-app-frps" ]; then
    mv -f package/applications/luci-app-frps feeds/luci/applications/
    log "已移动luci-app-frps到feeds/luci/applications/"
fi

git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac package/openwrt-gecoosac
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

# Mary定制包
log "克隆Mary定制软件包"
git clone --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest package/netspeedtest
git clone --depth=1 https://github.com/sirpdboy/luci-app-partexp package/luci-app-partexp
git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan package/luci-app-taskplan
git clone --depth=1 https://github.com/tailscale/tailscale package/tailscale
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-momo package/luci-app-momo
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki package/nikki
git clone --depth=1 https://github.com/vernesong/OpenClash package/OpenClash

# 添加kenzok8软件源并且让它的优先级最低
log "添加kenzok8软件源"
git clone small8 https://github.com/kenzok8/small-package

# 更新和安装feeds
log "更新和安装feeds"
./scripts/feeds update -a >> "$LOG_FILE" 2>&1
./scripts/feeds install -a >> "$LOG_FILE" 2>&1

log "OpenWrt编译环境准备完成"
