#!/usr/bin/env bash
# 设置严格模式：任何命令失败时脚本立即退出
set -e
set -o errexit
# 设置错误追踪：显示完整的错误调用链
set -o errtrace

# 获取脚本所在目录
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
# 获取仓库根目录（脚本目录的上一级）
BASE_PATH=$(cd "$SCRIPT_DIR/.." && pwd)

# 定义错误处理函数
error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

# 设置陷阱捕获ERR信号
trap 'error_handler' ERR

# 从命令行参数获取配置信息
REPO_URL=$1      # 代码仓库地址
REPO_BRANCH=$2   # 代码仓库分支
BUILD_DIR=$3     # 构建目录
COMMIT_HASH=$4   # 特定的代码提交版本号

# 定义一些固定的配置项
FEEDS_CONF="feeds.conf.default"    # 软件源配置文件名
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"  # Go语言包的仓库地址
GOLANG_BRANCH="25.x"              # Go语言包的分支版本
THEME_SET="argon"                  # 默认网页主题名称
LAN_ADDR="192.168.111.1"           # 路由器默认管理地址

# 定义克隆代码仓库的函数
clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        # 尝试克隆仓库
        if ! git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi
    fi
}

# 定义清理构建环境的函数
clean_up() {
    cd $BUILD_DIR
    
    # 删除旧的配置文件
    if [[ -f $BUILD_DIR/.config ]]; then
        \rm -f $BUILD_DIR/.config
    fi
    
    # 删除临时目录
    if [[ -d $BUILD_DIR/tmp ]]; then
        \rm -rf $BUILD_DIR/tmp
    fi
    
    # 清空日志目录
    if [[ -d $BUILD_DIR/logs ]]; then
        \rm -rf $BUILD_DIR/logs/*
    fi
    
    # 创建新的临时目录
    mkdir -p $BUILD_DIR/tmp
    # 创建构建标记文件
    echo "1" >$BUILD_DIR/tmp/.build
}

# 定义重置代码仓库状态的函数
reset_feeds_conf() {
    # 将代码重置到远程分支的最新状态
    git reset --hard origin/$REPO_BRANCH
    # 清理所有未被跟踪的文件和目录
    git clean -f -d
    # 从远程仓库拉取最新代码
    git pull
    
    # 如果指定了特定的提交版本
    if [[ $COMMIT_HASH != "none" ]]; then
        # 切换到那个特定的版本
        git checkout $COMMIT_HASH
    fi
}

# 定义更新软件源的函数
update_feeds() {
    # 删除配置文件中的注释行
    sed -i '/^#/d' "$BUILD_DIR/$FEEDS_CONF"
    
    # 添加新的软件源，OpenWrt 的构建系统会根据 feeds.conf.default 中 src-git 条目的顺序来决定使用哪个 feed 中的软件包，顺序靠前的 feed 优先。
    # 确保文件以换行符结尾
    [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
    echo "src-git tailscale https://github.com/tailscale/tailscale;main" >>"$BUILD_DIR/$FEEDS_CONF"
    echo "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan;master" >>"$BUILD_DIR/$FEEDS_CONF"
    echo "src-git lucky https://github.com/gdy666/luci-app-lucky" >>"$BUILD_DIR/$FEEDS_CONF"
    echo "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo.git;main" >>"$BUILD_DIR/$FEEDS_CONF"
    echo "src-git OpenAppFilter https://github.com/destan19/OpenAppFilter.git;master" >>"$BUILD_DIR/$FEEDS_CONF"
    
    # 检查并添加 small-package 源
    if ! grep -q "small-package" "$BUILD_DIR/$FEEDS_CONF"; then
        # 确保文件以换行符结尾
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git small8 https://github.com/kenzok8/small-package" >>"$BUILD_DIR/$FEEDS_CONF"
    fi
    
    # 添加bpf.mk文件解决更新报错
    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi
    
    # 更新所有软件源
    ./scripts/feeds clean
    ./scripts/feeds update -a
}

# 定义移除不需要的软件包的函数
remove_unwanted_packages() {
    # 定义要移除的LuCI应用列表
    local luci_packages=(
        "luci-app-passwall" "luci-app-ddns-go" "luci-app-rclone" "luci-app-ssr-plus"
        "luci-app-vssr" "luci-app-daed" "luci-app-dae" "luci-app-alist" "luci-app-homeproxy"
        "luci-app-haproxy-tcp" "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter"
        "luci-app-msd_lite"
    )
    
    # 定义要移除的网络工具包列表
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs" "shadowsocksr-libev" 
        "dae" "daed" "mihomo" "geoview" "tailscale" "open-app-filter" "msd_lite"
    )
    
    # 定义要移除的工具包列表
    local packages_utils=(
        "cups"
    )
    
    # 定义要移除的small8源软件包列表
    local small8_packages=(
        "ppp" "firewall" "dae" "daed" "daed-next" "libnftnl" "nftables" "dnsmasq" "luci-app-alist"
        "alist" "opkg" "smartdns" "luci-app-smartdns"
    )
    
    # 遍历并删除LuCI应用
    for pkg in "${luci_packages[@]}"; do
        if [[ -d ./feeds/luci/applications/$pkg ]]; then
            \rm -rf ./feeds/luci/applications/$pkg
        fi
        if [[ -d ./feeds/luci/themes/$pkg ]]; then
            \rm -rf ./feeds/luci/themes/$pkg
        fi
    done
    
    # 遍历并删除网络工具包
    for pkg in "${packages_net[@]}"; do
        if [[ -d ./feeds/packages/net/$pkg ]]; then
            \rm -rf ./feeds/packages/net/$pkg
        fi
    done
    
    # 遍历并删除工具包
    for pkg in "${packages_utils[@]}"; do
        if [[ -d ./feeds/packages/utils/$pkg ]]; then
            \rm -rf ./feeds/packages/utils/$pkg
        fi
    done
    
    # 遍历并删除small8源软件包
    for pkg in "${small8_packages[@]}"; do
        if [[ -d ./feeds/small8/$pkg ]]; then
            \rm -rf ./feeds/small8/$pkg
        fi
    done
    
    # 删除istore软件源
    if [[ -d ./package/istore ]]; then
        \rm -rf ./package/istore
    fi
    
    # 清理特定平台的初始化脚本
    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
}

# 定义更新Go语言支持包的函数
update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        echo "正在更新 golang 软件包..."
        \rm -rf ./feeds/packages/lang/golang
        
        # 克隆新的Go语言包
        if ! git clone --depth 1 -b $GOLANG_BRANCH $GOLANG_REPO ./feeds/packages/lang/golang; then
            echo "错误：克隆 golang 仓库 $GOLANG_REPO 失败" >&2
            exit 1
        fi
    fi
}

# 定义安装small8源软件包的函数
install_small8() {
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        luci-app-passwall v2dat mosdns luci-app-mosdns adguardhome luci-app-adguardhome ddns-go \
        luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd luci-app-store quickstart \
        luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest netdata luci-app-netdata \
        lucky luci-app-lucky luci-app-openclash luci-app-homeproxy luci-app-amlogic nikki luci-app-nikki \
        tailscale luci-app-tailscale oaf open-app-filter luci-app-oaf easytier luci-app-easytier \
        msd_lite luci-app-msd_lite cups luci-app-cupsd
}

# 定义安装FullCone NAT支持包的函数
install_fullconenat() {
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat-nft ]; then
        ./scripts/feeds install -p small8 -f fullconenat-nft
    fi
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat ]; then
        ./scripts/feeds install -p small8 -f fullconenat
    fi
}

# 定义安装所有软件源的函数
install_feeds() {
    ./scripts/feeds update -i
    
    # 遍历所有软件源目录
    for dir in $BUILD_DIR/feeds/*; do
        # 检查是否为目录并且不以 .tmp 结尾，并且不是软链接
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [ ! -L "$dir" ]; then
            if [[ $(basename "$dir") == "small8" ]]; then
                # 如果是small8源
                install_small8
                install_fullconenat
            else
                # 对于其他软件源
                ./scripts/feeds install -f -ap $(basename "$dir")
            fi
        fi
    done
}

# 定义修复默认设置的函数
fix_default_set() {
    # 修改默认主题
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi
    
    # 安装自定义设置脚本
    install -Dm755 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm755 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    
    # 修复温度显示脚本
    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

# 定义修复miniupnpd软件包的函数
fix_miniupnpd() {
    local miniupnpd_dir="$BUILD_DIR/feeds/packages/net/miniupnpd"
    local patch_file="999-chanage-default-leaseduration.patch"
    
    if [ -d "$miniupnpd_dir" ] && [ -f "$BASE_PATH/patches/$patch_file" ]; then
        install -Dm644 "$BASE_PATH/patches/$patch_file" "$miniupnpd_dir/patches/$patch_file"
    fi
}

# 定义将dnsmasq替换为dnsmasq-full的函数
change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
}

# 定义修复依赖关系的函数
fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' $BUILD_DIR/include/target.mk 2>/dev/null
    
    if [ -f $BUILD_DIR/target/linux/qualcommax/Makefile ]; then
        sed -i 's/wpad-openssl/wpad-mesh-openssl/g' $BUILD_DIR/target/linux/qualcommax/Makefile
    fi
}

# 定义添加WiFi默认设置的函数
add_wifi_default_set() {
    local qualcommax_uci_dir="$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults"
    local filogic_uci_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/etc/uci-defaults"
    
    # 为qualcommax平台添加WiFi设置脚本
    if [ -d "$qualcommax_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$qualcommax_uci_dir/992_set-wifi-uci.sh"
    fi
    
    # 为filogic平台添加WiFi设置脚本
    if [ -d "$filogic_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$filogic_uci_dir/992_set-wifi-uci.sh"
    fi
}

# 定义更新默认LAN地址的函数
update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f $CFG_PATH ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' $CFG_PATH
    fi
}

# 定义移除NSS相关内核模块的函数
remove_something_nss_kmod() {
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    local target_mks=("$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk" "$BUILD_DIR/target/linux/qualcommax/ipq807x/target.mk")
    
    # 处理特定平台的Makefile
    for target_mk in "${target_mks[@]}"; do
        if [ -f "$target_mk" ]; then
            sed -i 's/kmod-qca-nss-crypto//g' "$target_mk"
        fi
    done
    
    # 处理主Makefile
    if [ -f "$ipq_mk_path" ]; then
        # 移除一系列NSS驱动模块
        sed -i '/kmod-qca-nss-drv-eogremgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-gre/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-map-t/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-match/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-mirror/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-tun6rd/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-tunipip6/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-vxlanmgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-macsec/d' "$ipq_mk_path"
        
        # 移除一些特性
        sed -i 's/automount //g' "$ipq_mk_path"
        sed -i 's/cpufreq //g' "$ipq_mk_path"
    fi
}

# 定义更新CPU亲和性脚本的函数
update_affinity_script() {
    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"
    
    if [ -d "$affinity_script_dir" ]; then
        # 删除旧的脚本
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
        
        # 安装新的脚本
        install -Dm755 "$BASE_PATH/patches/smp_affinity" "$affinity_script_dir/base-files/etc/init.d/smp_affinity"
    fi
}

# 定义修正软件包哈希值的通用函数
fix_hash_value() {
    local makefile_path="$1"    # Makefile文件路径
    local old_hash="$2"        # 旧的哈希值
    local new_hash="$3"        # 新的哈希值
    local package_name="$4"    # 软件包名称
    
    if [ -f "$makefile_path" ]; then
        sed -i "s/$old_hash/$new_hash/g" "$makefile_path"
        echo "已修正 $package_name 的哈希值。"
    fi
}

# 定义应用所有哈希值修正的函数
apply_hash_fixes() {
    # 修正smartdns软件包的哈希值
    fix_hash_value \
        "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" \
        "a7edb052fea61418c91c7a052f7eb1478fe6d844aec5e3eda0f2fcf82de29a10" \
        "b11e175970e08115fe3b0d7a543fa8d3a6239d3c24eeecfd8cfd2fef3f52c6c9" \
        "smartdns"
    
    # 再次修正smartdns的另一个哈希值
    fix_hash_value \
        "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" \
        "a1c084dcc4fb7f87641d706b70168fc3c159f60f37d4b7eac6089ae68f0a18a1" \
        "ab7d303a538871ae4a70ead2e90d35e24fcc36bc20f5b6c5d963a3e283ea43b1" \
        "smartdns"    
}

# 定义更新ath11k固件的函数
update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    local new_mk="$BASE_PATH/patches/ath11k_fw.mk"
    local url="https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile"
    
    if [ -d "$(dirname "$makefile")" ]; then
        echo "正在更新 ath11k-firmware Makefile..."
        # 使用curl下载新的Makefile
        if ! curl -fsSL -o "$new_mk" "$url"; then
            echo "错误：从 $url 下载 ath11k-firmware Makefile 失败" >&2
            exit 1
        fi
        if [ ! -s "$new_mk" ]; then
            echo "错误：下载的 ath11k-firmware Makefile 为空文件" >&2
            exit 1
        fi
        mv -f "$new_mk" "$makefile"
    fi
}

# 定义修复软件包格式问题的函数
fix_mkpkg_format_invalid() {
    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        # 修复v2ray-geodata的Makefile
        if [ -f $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile
        fi
        
        # 修复luci-lib-taskd的Makefile
        if [ -f $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile
        fi
        
        # 修复luci-app-openclash的Makefile
        if [ -f $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile
        fi
        
        # 修复luci-app-quickstart的Makefile
        if [ -f $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
        fi
        
        # 修复luci-app-store的Makefile
        if [ -f $BUILD_DIR/feeds/small8/luci-app-store/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
        fi
    fi
}

# 定义添加AX6600 LED控制应用的函数
add_ax6600_led() {
    local athena_led_dir="$BUILD_DIR/package/emortal/luci-app-athena-led"
    local repo_url="https://github.com/NONGFAH/luci-app-athena-led.git"
    
    echo "正在添加 luci-app-athena-led..."
    rm -rf "$athena_led_dir" 2>/dev/null
    
    # 克隆新的仓库
    if ! git clone --depth=1 "$repo_url" "$athena_led_dir"; then
        echo "错误：从 $repo_url 克隆 luci-app-athena-led 仓库失败" >&2
        exit 1
    fi
    
    # 设置文件权限
    if [ -d "$athena_led_dir" ]; then
        chmod +x "$athena_led_dir/root/usr/sbin/athena-led"
        chmod +x "$athena_led_dir/root/etc/init.d/athena_led"
    else
        echo "错误：克隆操作后未找到目录 $athena_led_dir" >&2
        exit 1
    fi
}

# 定义修改CPU使用率显示方式的函数
change_cpuusage() {
    local luci_rpc_path="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    local qualcommax_sbin_dir="$BUILD_DIR/target/linux/qualcommax/base-files/sbin"
    local filogic_sbin_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/sbin"
    
    # 修改LuCI RPC脚本以使用自定义的cpuusage脚本
    if [ -f "$luci_rpc_path" ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" "$luci_rpc_path"
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' "$luci_rpc_path"
    fi
    
    # 删除旧脚本（如果存在）
    local old_script_path="$BUILD_DIR/package/base-files/files/sbin/cpuusage"
    if [ -f "$old_script_path" ]; then
        rm -f "$old_script_path"
    fi
    
    # 安装平台特定的cpuusage脚本
    install -Dm755 "$BASE_PATH/patches/cpuusage" "$qualcommax_sbin_dir/cpuusage"
    install -Dm755 "$BASE_PATH/patches/hnatusage" "$filogic_sbin_dir/cpuusage"
}

# 定义更新tcping工具的函数
update_tcping() {
    local tcping_path="$BUILD_DIR/feeds/small8/tcping/Makefile"
    local url="https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/refs/heads/main/tcping/Makefile"
    
    if [ -d "$(dirname "$tcping_path")" ]; then
        echo "正在更新 tcping Makefile..."
        # 下载新的Makefile
        if ! curl -fsSL -o "$tcping_path" "$url"; then
            echo "错误：从 $url 下载 tcping Makefile 失败" >&2
            exit 1
        fi
    fi
}

# 定义设置自定义任务的函数
set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    # 创建自定义任务脚本
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
# 设置启动优先级
START=99

boot() {
    # 重新添加缓存清理定时任务
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root
    
    # 删除现有的 wireguard_watchdog 任务
    sed -i '/wireguard_watchdog/d' /etc/crontabs/root
    
    # 应用新的 crontab 配置
    crontab /etc/crontabs/root
}
EOF
    chmod +x "$sh_dir/custom_task"
}

# 定义应用Passwall相关调整的函数
apply_passwall_tweaks() {
    # 清理 Passwall 的 chnlist 规则文件
    local chnlist_path="$BUILD_DIR/feeds/small8/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then
        > "$chnlist_path"
    fi
    
    # 调整 Xray 最大 RTT 和 保留记录数量
    local xray_util_path="$BUILD_DIR/feeds/small8/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
        sed -i 's/sampling = 3/sampling = 5/g' "$xray_util_path"
    fi
}

# 定义安装opkg软件源配置的函数
install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"
    
    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        # 创建软件源配置文件
        cat <<'EOF' >"$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF
        
        # 修改Makefile以包含配置文件
        sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile
        
        # 修改默认设置脚本
        sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
    fi
}

# 定义更新NSS pbuf性能设置的函数
update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f $pbuf_path ]; then
        sed -i "s/auto_scale '1'/auto_scale 'off'/g" $pbuf_path
        sed -i "s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" $pbuf_path
    fi
}

# 定义设置构建签名的函数
set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by ZqinKing')/g" "$file"
    fi
}

# 定义更新NSS诊断脚本的函数
update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        \rm -f "$file"
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
    fi
}

# 定义更新菜单位置的函数
update_menu_location() {
    # 修改samba4的菜单位置
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then
        sed -i 's/nas/services/g' "$samba4_path"
    fi
    
    # 修改tailscale的菜单位置
    local tailscale_path="$BUILD_DIR/feeds/small8/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi
}

# 定义修复coremark编译问题的函数
fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}

# 定义更新homeproxy的函数
update_homeproxy() {
    local repo_url="https://github.com/immortalwrt/homeproxy.git"
    local target_dir="$BUILD_DIR/feeds/small8/luci-app-homeproxy"
    
    if [ -d "$target_dir" ]; then
        echo "正在更新 homeproxy..."
        rm -rf "$target_dir"
        
        # 克隆新版本
        if ! git clone --depth 1 "$repo_url" "$target_dir"; then
            echo "错误：从 $repo_url 克隆 homeproxy 仓库失败" >&2
            exit 1
        fi
    fi
}

# 定义更新dnsmasq配置的函数
update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i '/dns_redirect/d' "$file"
    fi
}

# 定义更新软件包版本的通用函数
update_package() {
    local dir=$(find "$BUILD_DIR/package" \( -type d -o -type l \) -name "$1")
    # 查找指定软件包的目录
    
    if [ -z "$dir" ]; then
        return 0
        # 如果找不到目录，直接返回
    fi
    
    local branch="$2"
    if [ -z "$branch" ]; then
        branch="releases"
        # 默认使用releases分支
    fi
    
    local mk_path="$dir/Makefile"
    if [ -f "$mk_path" ]; then
        # 提取仓库信息
        local PKG_REPO=$(grep -oE "^PKG_GIT_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" "$mk_path" | awk -F"/" '{print $(NF - 1) "/" $NF}')
        if [ -z "$PKG_REPO" ]; then
            PKG_REPO=$(grep -oE "^PKG_SOURCE_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" "$mk_path" | awk -F"/" '{print $(NF - 1) "/" $NF}')
            if [ -z "$PKG_REPO" ]; then
                echo "错误：无法从 $mk_path 提取 PKG_REPO" >&2
                return 1
            fi
        fi
        
        # 获取版本信息
        local PKG_VER
        if ! PKG_VER=$(curl -fsSL "https://api.github.com/repos/$PKG_REPO/$branch" | jq -r '.[0] | .tag_name // .name'); then
            echo "错误：从 https://api.github.com/repos/$PKG_REPO/$branch 获取版本信息失败" >&2
            return 1
        fi
        
        if [ -n "$3" ]; then
            PKG_VER="$3"
            # 如果指定了版本，使用指定版本
        fi
        
        # 获取提交哈希
        local COMMIT_SHA
        if ! COMMIT_SHA=$(curl -fsSL "https://api.github.com/repos/$PKG_REPO/tags" | jq -r '.[] | select(.name=="'$PKG_VER'") | .commit.sha' | cut -c1-7); then
            echo "错误：从 https://api.github.com/repos/$PKG_REPO/tags 获取提交哈希失败" >&2
            return 1
        fi
        
        if [ -n "$COMMIT_SHA" ]; then
            sed -i 's/^PKG_GIT_SHORT_COMMIT:=.*/PKG_GIT_SHORT_COMMIT:='$COMMIT_SHA'/g' "$mk_path"
            # 更新提交哈希
        fi
        
        PKG_VER=$(echo "$PKG_VER" | grep -oE "[\.0-9]{1,}")
        # 提取版本号中的数字部分
        
        # 获取其他信息
        local PKG_NAME=$(awk -F"=" '/PKG_NAME:=/ {print $NF}' "$mk_path" | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_GIT_URL=$(awk -F"=" '/PKG_GIT_URL:=/ {print $NF}' "$mk_path")
        local PKG_GIT_REF=$(awk -F"=" '/PKG_GIT_REF:=/ {print $NF}' "$mk_path")
        
        # 替换变量
        PKG_GIT_URL=${PKG_GIT_URL//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_GIT_URL=${PKG_GIT_URL//\$\(PKG_VERSION\)/$PKG_VER}
        
        # 计算文件哈希
        local PKG_HASH
        if ! PKG_HASH=$(curl -fsSL "$PKG_GIT_URL""$PKG_NAME"-"$PKG_VER".tar.gz" | sha256sum | cut -b -64); then
            echo "错误：从 $PKG_GIT_URL$PKG_NAME-$PKG_VER.tar.gz 获取软件包哈希失败" >&2
            return 1
        fi
        
        # 更新Makefile
        sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:='$PKG_VER'/g' "$mk_path"
        sed -i 's/^PKG_HASH:=.*/PKG_HASH:='$PKG_HASH'/g' "$mk_path"
        
        echo "更新软件包 $1 到 $PKG_VER $PKG_HASH"
    fi
}

# 定义添加系统升级时的备份信息的函数
add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"
    
    if [ -f "$conf_path" ]; then
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
    fi
}

# 定义更新启动顺序的函数
update_script_priority() {
    # 更新qca-nss驱动的启动顺序
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then
        sed -i 's/START=.*/START=88/g' "$qca_drv_path"
    fi
    
    # 更新pbuf服务的启动顺序
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then
        sed -i 's/START=.*/START=89/g' "$pbuf_path"
    fi
    
    # 更新mosdns服务的启动顺序
    local mosdns_path="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}

# 定义更新mosdns默认配置的函数
update_mosdns_deconfig() {
    local mosdns_conf="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}

# 定义修复quickstart的函数
fix_quickstart() {
    local file_path="$BUILD_DIR/feeds/small8/luci-app-quickstart/luasrc/controller/istore_backend.lua"
    local url="https://gist.githubusercontent.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa/raw/istore_backend.lua"
    
    # 下载新的文件并覆盖
    if [ -f "$file_path" ]; then
        echo "正在修复 quickstart..."
        if ! curl -fsSL -o "$file_path" "$url"; then
            echo "错误：从 $url 下载 istore_backend.lua 失败" >&2
            exit 1
        fi
    fi
}

# 定义更新oaf配置的函数
update_oaf_deconfig() {
    local conf_path="$BUILD_DIR/feeds/small8/open-app-filter/files/appfilter.config"
    local uci_def="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0"
    local disable_path="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/99_disable_oaf"
    
    if [ -d "${conf_path%/*}" ] && [ -f "$conf_path" ]; then
        sed -i \
            -e "s/record_enable '1'/record_enable '0'/g" \
            -e "s/disable_hnat '1'/disable_hnat '0'/g" \
            -e "s/auto_load_engine '1'/auto_load_engine '0'/g" \
            "$conf_path"
    fi
    
    if [ -d "${uci_def%/*}" ] && [ -f "$uci_def" ]; then
        sed -i '/\(disable_hnat\|auto_load_engine\)/d' "$uci_def"
        
        # 创建禁用脚本
        cat >"$disable_path" <<-EOF
#!/bin/sh
[ "\$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
        chmod +x "$disable_path"
    fi
}

# 定义支持防火墙4的AdGuardHome的函数
support_fw4_adg() {
    local src_path="$BASE_PATH/patches/AdGuardHome"
    local dst_path="$BUILD_DIR/feeds/small8/luci-app-adguardhome/root/etc/init.d/AdGuardHome"
    
    if [ -f "$src_path" ] && [ -d "${dst_path%/*}" ] && [ -f "$dst_path" ]; then
        install -Dm 755 "$src_path" "$dst_path"
        echo "已更新AdGuardHome启动脚本"
    fi
}

# 定义添加时间控制应用的函数
add_timecontrol() {
    local timecontrol_dir="$BUILD_DIR/package/luci-app-timecontrol"
    local repo_url="https://github.com/sirpdboy/luci-app-timecontrol.git"
    
    rm -rf "$timecontrol_dir" 2>/dev/null
    echo "正在添加 luci-app-timecontrol..."
    
    if ! git clone --depth 1 "$repo_url" "$timecontrol_dir"; then
        echo "错误：从 $repo_url 克隆 luci-app-timecontrol 仓库失败" >&2
        exit 1
    fi
}

# 定义添加gecoosac应用的函数
add_gecoosac() {
    local gecoosac_dir="$BUILD_DIR/package/openwrt-gecoosac"
    local repo_url="https://github.com/lwb1978/openwrt-gecoosac.git"
    
    rm -rf "$gecoosac_dir" 2>/dev/null
    echo "正在添加 openwrt-gecoosac..."
    
    if ! git clone --depth 1 "$repo_url" "$gecoosac_dir"; then
        echo "错误：从 $repo_url 克隆 openwrt-gecoosac 仓库失败" >&2
        exit 1
    fi
}

# 定义修复easytier的函数
fix_easytier() {
    local easytier_path="$BUILD_DIR/feeds/small8/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -d "${easytier_path%/*}" ] && [ -f "$easytier_path" ]; then
        sed -i 's/util/xml/g' "$easytier_path"
    fi
}

# 定义更新geoip数据库的函数
update_geoip() {
    local geodata_path="$BUILD_DIR/feeds/small8/v2ray-geodata/Makefile"
    if [ -d "${geodata_path%/*}" ] && [ -f "$geodata_path" ]; then
        local GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' $geodata_path | grep -oE "[0-9]{1,}")
        if [ -n "$GEOIP_VER" ]; then
            local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
            # 下载校验和
            local old_SHA256
            if ! old_SHA256=$(wget -qO- "$base_url/geoip.dat.sha256sum" | awk '{print $1}'); then
                echo "错误：从 $base_url/geoip.dat.sha256sum 获取旧的 geoip.dat 校验和失败" >&2
                return 1
            fi
            local new_SHA256
            if ! new_SHA256=$(wget -qO- "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}'); then
                echo "错误：从 $base_url/geoip-only-cn-private.dat.sha256sum 获取新的 geoip-only-cn-private.dat 校验和失败" >&2
                return 1
            fi
            # 更新Makefile
            if [ -n "$old_SHA256" ] && [ -n "$new_SHA256" ]; then
                if grep -q "$old_SHA256" "$geodata_path"; then
                    sed -i "s|=geoip.dat|=geoip-only-cn-private.dat|g" "$geodata_path"
                    sed -i "s/$old_SHA256/$new_SHA256/g" "$geodata_path"
                fi
            fi
        fi
    fi
}

# 定义更新lucky工具的函数
update_lucky() {
    # 从补丁文件名中提取版本号
    local version
    version=$(find "$BASE_PATH/patches" -name "lucky_*.tar.gz" -printf "%f\n" | head -n 1 | sed -n 's/^lucky_\(.*\)_Linux.*$/\1/p')
    if [ -z "$version" ]; then
        echo "Warning: 未找到 lucky 补丁文件，跳过更新。" >&2
        return 1
    fi
    
    local makefile_path="$BUILD_DIR/feeds/small8/lucky/Makefile"
    if [ ! -f "$makefile_path" ]; then
        echo "Warning: lucky Makefile not found. Skipping." >&2
        return 1
    fi
    
    echo "正在更新 lucky Makefile..."
    # 使用本地补丁文件
    local patch_line="\\t[ -f \$(TOPDIR)/../patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz ] && install -Dm644 \$(TOPDIR)/../patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz \$(PKG_BUILD_DIR)/\$(PKG_NAME)_\$(PKG_VERSION)_Linux_\$(LUCKY_ARCH).tar.gz"
    
    if grep -q "Build/Prepare" "$makefile_path"; then
        sed -i "/Build\\/Prepare/a\\$patch_line" "$makefile_path"
        sed -i '/wget/d' "$makefile_path"
        echo "lucky Makefile 更新完成。"
    else
        echo "Warning: lucky Makefile 中未找到 'Build/Prepare'。跳过。" >&2
    fi
}

# 定义修复Rust编译错误的函数
fix_rust_compile_error() {
    if [ -f "$BUILD_DIR/feeds/packages/lang/rust/Makefile" ]; then
        sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$BUILD_DIR/feeds/packages/lang/rust/Makefile"
    fi
}

# 定义更新smartdns的函数
update_smartdns() {
    local SMARTDNS_REPO="https://github.com/pymumu/openwrt-smartdns.git"
    local SMARTDNS_DIR="$BUILD_DIR/feeds/packages/net/smartdns"
    local LUCI_APP_SMARTDNS_REPO="https://github.com/pymumu/luci-app-smartdns.git"
    local LUCI_APP_SMARTDNS_DIR="$BUILD_DIR/feeds/luci/applications/luci-app-smartdns"
    
    echo "正在更新 smartdns..."
    rm -rf "$SMARTDNS_DIR"
    if ! git clone --depth=1 "$SMARTDNS_REPO" "$SMARTDNS_DIR"; then
        echo "错误：从 $SMARTDNS_REPO 克隆 smartdns 仓库失败" >&2
        exit 1
    fi
    
    install -Dm644 "$BASE_PATH/patches/100-smartdns-optimize.patch" "$SMARTDNS_DIR/patches/100-smartdns-optimize.patch"
    sed -i '/define Build\/Compile\/smartdns-ui/,/endef/s/CC=\$(TARGET_CC)/CC="\$(TARGET_CC_NOCACHE)"/' "$SMARTDNS_DIR/Makefile"
    
    echo "正在更新 luci-app-smartdns..."
    rm -rf "$LUCI_APP_SMARTDNS_DIR"
    if ! git clone --depth=1 "$LUCI_APP_SMARTDNS_REPO" "$LUCI_APP_SMARTDNS_DIR"; then
        echo "错误：从 $LUCI_APP_SMARTDNS_REPO 克隆 luci-app-smartdns 仓库失败" >&2
        exit 1
    fi
}

# 定义更新diskman磁盘管理工具的函数
update_diskman() {
    local path="$BUILD_DIR/feeds/luci/applications/luci-app-diskman"
    local repo_url="https://github.com/lisaac/luci-app-diskman.git"
    if [ -d "$path" ]; then
        echo "正在更新 diskman..."
        cd "$BUILD_DIR/feeds/luci/applications" || return
        \rm -rf "luci-app-diskman"
        
        if ! git clone --filter=blob:none --no-checkout "$repo_url" diskman; then
            echo "错误：从 $repo_url 克隆 diskman 仓库失败" >&2
            exit 1
        fi
        cd diskman || return
        
        git sparse-checkout init --cone
        git sparse-checkout set applications/luci-app-diskman || return
        git checkout --quiet
        
        mv applications/luci-app-diskman ../luci-app-diskman || return
        cd .. || return
        \rm -rf diskman
        cd "$BUILD_DIR"
        
        sed -i 's/fs-ntfs /fs-ntfs3 /g' "$path/Makefile"
        sed -i '/ntfs-3g-utils /d' "$path/Makefile"
    fi
}

# 定义添加quickfile快速文件共享的函数
add_quickfile() {
    local repo_url="https://github.com/sbwml/luci-app-quickfile.git"
    local target_dir="$BUILD_DIR/package/emortal/quickfile"
    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
    fi
    echo "正在添加 luci-app-quickfile..."
    if ! git clone --depth 1 "$repo_url" "$target_dir"; then
        echo "错误：从 $repo_url 克隆 luci-app-quickfile 仓库失败" >&2
        exit 1
    fi
    
    local makefile_path="$target_dir/quickfile/Makefile"
    if [ -f "$makefile_path" ]; then
        sed -i '/\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-\$(ARCH_PACKAGES)/c\
\tif [ "\$(ARCH_PACKAGES)" = "x86_64" ]; then \\\
\t\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-x86_64 \$(1)\/usr\/bin\/quickfile; \\\
\telse \\\
\t\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-aarch64_generic \$(1)\/usr\/bin\/quickfile; \\\
\tfi' "$makefile_path"
    fi
}

# 定义设置Nginx默认配置的函数
set_nginx_default_config() {
    local nginx_config_path="$BUILD_DIR/feeds/packages/net/nginx-util/files/nginx.config"
    if [ -f "$nginx_config_path" ]; then
        cat > "$nginx_config_path" <<EOF
config main 'global'
        option uci_enable 'true'

config server '_lan'
        list listen '443 ssl default_server'
        list listen '[::]:443 ssl default_server'
        option server_name '_lan'
        list include 'restrict_locally'
        list include 'conf.d/*.locations'
        option uci_manage_ssl 'self-signed'
        option ssl_certificate '/etc/nginx/conf.d/_lan.crt'
        option ssl_certificate_key '/etc/nginx/conf.d/_lan.key'
        option ssl_session_cache 'shared:SSL:32k'
        option ssl_session_timeout '64m'
        option access_log 'off; # logd openwrt'

config server 'http_only'
        list listen '80'
        list listen '[::]:80'
        option server_name 'http_only'
        list include 'conf.d/*.locations'
        option access_log 'off; # logd openwrt'
EOF
    fi
    
    local nginx_template="$BUILD_DIR/feeds/packages/net/nginx-util/files/uci.conf.template"
    if [ -f "$nginx_template" ]; then
        if ! grep -q "client_body_in_file_only clean;" "$nginx_template"; then
            sed -i "/client_max_body_size 128M;/a\\
\tclient_body_in_file_only clean;\\
\tclient_body_temp_path /mnt/tmp;" "$nginx_template"
        fi
    fi
}

# 定义更新uwsgi内存限制的函数
update_uwsgi_limit_as() {
    local cgi_io_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-cgi_io.ini"
    local webui_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini"
    
    if [ -f "$cgi_io_ini" ]; then
        sed -i 's/^limit-as = .*/limit-as = 8192/g' "$cgi_io_ini"
    fi
    
    if [ -f "$webui_ini" ]; then
        sed -i 's/^limit-as = .*/limit-as = 8192/g' "$webui_ini"
    fi
}

# 定义移除调整过的软件包的函数
remove_tweaked_packages() {
    local target_mk="$BUILD_DIR/include/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "^DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)" "$target_mk"; then
            sed -i 's/DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/# DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/g' "$target_mk"
        fi
    fi
}

# 定义更新argon主题的函数
update_argon() {
    local repo_url="https://github.com/ZqinKing/luci-theme-argon.git"
    local dst_theme_path="$BUILD_DIR/feeds/luci/themes/luci-theme-argon"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    
    echo "正在更新 argon 主题..."
    
    if ! git clone --depth 1 "$repo_url" "$tmp_dir"; then
        echo "错误：从 $repo_url 克隆 argon 主题仓库失败" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    rm -rf "$dst_theme_path"
    rm -rf "$tmp_dir/.git"
    mv "$tmp_dir" "$dst_theme_path"
    
    echo "luci-theme-argon 更新完成"
}

# 定义主函数，执行所有构建前的准备工作
main() {
    clone_repo              # 克隆代码仓库
    clean_up                # 清理构建环境
    reset_feeds_conf        # 重置软件源配置
    update_feeds            # 更新软件源
    remove_unwanted_packages # 移除不需要的软件包
    remove_tweaked_packages # 移除调整过的软件包
    update_homeproxy        # 更新homeproxy代理工具
    fix_default_set         # 修复默认设置
    fix_miniupnpd           # 修复miniupnpd
    update_golang           # 更新Go语言支持
    change_dnsmasq2full     # 替换dnsmasq为full版本
    fix_mk_def_depends      # 修复依赖关系
    add_wifi_default_set    # 添加WiFi默认设置
    update_default_lan_addr # 更新默认LAN地址
    remove_something_nss_kmod # 移除NSS相关模块
    update_affinity_script  # 更新CPU亲和性脚本
    update_ath11k_fw       # 更新ath11k固件
    change_cpuusage         # 修改CPU使用率显示
    update_tcping           # 更新tcping工具
    add_ax6600_led          # 添加AX6600 LED控制
    set_custom_task         # 设置自定义任务
    apply_passwall_tweaks   # 应用Passwall调整
    install_opkg_distfeeds  # 安装软件源配置
    update_nss_pbuf_performance # 更新NSS性能设置
    set_build_signature     # 设置构建签名
    update_nss_diag         # 更新NSS诊断脚本
    update_menu_location    # 更新菜单位置
    fix_compile_coremark    # 修复coremark编译
    update_dnsmasq_conf     # 更新dnsmasq配置
    add_backup_info_to_sysupgrade # 添加备份信息
    update_mosdns_deconfig  # 更新mosdns配置
    fix_quickstart          # 修复quickstart
    update_oaf_deconfig     # 更新oaf配置
    add_timecontrol         # 添加时间控制
    add_gecoosac            # 添加gecoosac
    add_quickfile           # 添加quickfile
    update_lucky            # 更新lucky工具
    fix_rust_compile_error  # 修复Rust编译错误
    update_smartdns         # 更新smartdns
    update_diskman          # 更新diskman
    set_nginx_default_config # 设置Nginx默认配置
    update_uwsgi_limit_as   # 更新uwsgi内存限制
    update_argon            # 更新argon主题
    install_feeds           # 安装所有软件源
    support_fw4_adg         # 支持防火墙4的AdGuardHome
    update_script_priority  # 更新启动顺序
    fix_easytier            # 修复easytier
    update_geoip            # 更新geoip数据库
    #update_package "runc" "releases" "v1.2.6"  # 更新runc容器工具
    #update_package "containerd" "releases" "v1.7.27"  # 更新containerd
    #update_package "docker" "tags" "v28.2.2"  # 更新docker
    #update_package "dockerd" "releases" "v28.2.2"  # 更新dockerd
    apply_hash_fixes        # 应用哈希值修正
}

# 执行主函数
main "$@"
