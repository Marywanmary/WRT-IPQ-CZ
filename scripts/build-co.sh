#!/bin/bash
set -euo pipefail

# ================ 中文注释：自动分支/配置合并编译脚本 ================
# 参数：$1 分支缩写 $2 芯片变量 $3 输出产物目录
# 用法: ./scripts/build.sh immwrt ipq60xx output/ipq60xx

REPO_SHORT="$1"
CHIP="$2"
OUTPUT_DIR="$3"
DATE=$(date +'%Y%m%d')
TIME=$(date +'%Y-%m-%d %H:%M:%S')
CONFIGS=("Ultra" "Max" "Pro")  # 按照 Ultra > Max > Pro 顺序
CONFIG_DIR="configs"
LOG_DIR="${OUTPUT_DIR}/logs"
PKG_DIR="${OUTPUT_DIR}/ipk"
TMP_DIR="${OUTPUT_DIR}/tmp"
mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$PKG_DIR" "$TMP_DIR"

# 错误处理函数
handle_error() {
    local exit_code=$?
    echo "错误: 命令执行失败，退出码: $exit_code"
    exit $exit_code
}

# 改进的配置合并函数，避免递归依赖
merge_config() {
    local device_cfg="$1"
    local temp_config=$(mktemp)
    
    # 检查配置文件是否存在
    local base_cfg="${CONFIG_DIR}/${CHIP}_base.config"
    local repo_cfg="${CONFIG_DIR}/${REPO_SHORT}_base.config"
    local device_cfg_file="${CONFIG_DIR}/${device_cfg}.config"
    
    for cfg in "$base_cfg" "$repo_cfg" "$device_cfg_file"; do
        if [ ! -f "$cfg" ]; then
            echo "错误: 配置文件 $cfg 不存在"
            handle_error
        fi
    done
    
    # 合并配置到临时文件
    cat "$base_cfg" "$repo_cfg" "$device_cfg_file" > "$temp_config"
    
    # 检查并移除已知的递归依赖
    echo "正在检查并移除递归依赖..."
    sed -i '/CONFIG_PACKAGE_aria2=y/d' "$temp_config"
    sed -i '/CONFIG_PACKAGE_luci-app-aria2=y/d' "$temp_config"
    sed -i '/CONFIG_PACKAGE_firewall4=y/d' "$temp_config"
    sed -i '/CONFIG_PACKAGE_luci-app-fchomo=y/d' "$temp_config"
    sed -i '/CONFIG_PACKAGE_nikki=y/d' "$temp_config"
    sed -i '/CONFIG_PACKAGE_strongswan-minimal=y/d' "$temp_config"
    sed -i '/CONFIG_PACKAGE_strongswan-mod-openssl=y/d' "$temp_config"
    sed -i '/CONFIG_PACKAGE_natmap=y/d' "$temp_config"
    sed -i '/CONFIG_PACKAGE_ua2f=y/d' "$temp_config"
    
    # 将处理后的配置复制到.config
    cp "$temp_config" .config
    rm "$temp_config"
    
    echo "配置合并完成（已移除递归依赖）"
}

# 提取设备名列表（支持多设备）
get_device_names() {
    grep -E 'CONFIG_TARGET_DEVICE_.*=y' .config | sed 's/.*DEVICE_\(.*\)=y/\1/' | sed 's/\"//g'
}

# 提取内核版本
get_kernel_version() {
    [ -f include/kernel-version.mk ] && \
    grep "LINUX_VERSION-$(grep "^KERNEL_PATCHVER:=" include/kernel-version.mk | cut -d'=' -f2)-=" include/kernel-version.mk | \
    head -n1 | awk '{print $3}' || echo "unknown"
}

# 提取luci app列表
get_luci_apps() {
    grep 'CONFIG_PACKAGE_luci-app-' .config | grep '=y' | cut -d'_' -f3- | cut -d'=' -f1 | sort | uniq | tr '\n' ' '
}

# 改进的编译函数
compile_firmware() {
    local log_file="$1"
    local err_file="$2"
    
    # 限制编译使用的CPU核心数，避免资源耗尽
    local jobs=$(( $(nproc) - 1 ))
    [ $jobs -lt 1 ] && jobs=1
    
    echo "开始编译，使用 $jobs 个核心..."
    
    # 编译并重定向日志
    if ! make -j$jobs V=s 2>&1 | tee "$log_file" | grep -i 'error\|warn\|failed' > "$err_file"; then
        echo "编译失败，详细错误请查看 $err_file"
        return 1
    fi
    
    echo "编译成功完成"
    return 0
}

# 主循环：每种配置串行编译
for CFG in "${CONFIGS[@]}"; do
    echo "【${CFG}】配置合并并开始编译"
    merge_config "$CFG"
    cp .config "${TMP_DIR}/${REPO_SHORT}-${CHIP}-${CFG}.config"

    # 清理空间
    echo "正在清理构建空间..."
    make dirclean > /dev/null 2>&1 || true
    echo "构建空间清理完成"

    # 生成默认配置 - 修复Broken pipe问题
    echo "正在生成默认配置..."
    # 使用timeout命令避免yes命令无限运行
    if ! timeout 30 bash -c 'yes "" | make defconfig' > /dev/null 2>&1; then
        echo "警告: 默认配置生成失败，尝试使用旧配置"
        if [ -f "${TMP_DIR}/${REPO_SHORT}-${CHIP}-${CFG}.config" ]; then
            cp "${TMP_DIR}/${REPO_SHORT}-${CHIP}-${CFG}.config" .config
            echo "已恢复配置"
        else
            echo "错误: 无法恢复配置"
            handle_error
        fi
    fi
    echo "默认配置生成完成"

    # 编译并重定向日志
    LOG_FILE="${LOG_DIR}/${REPO_SHORT}-${CHIP}-${CFG}.log"
    ERR_FILE="${LOG_DIR}/${REPO_SHORT}-${CHIP}-${CFG}.err"
    
    if ! compile_firmware "$LOG_FILE" "$ERR_FILE"; then
        echo "编译失败: ${CFG}"
        continue
    fi

    # 提取设备名、内核版本、luci-app
    DEVICES=$(get_device_names)
    KERNEL_VER=$(get_kernel_version)
    LUCI_APPS=$(get_luci_apps)

    # 固件产物处理
    for DEV in $DEVICES; do
        # factory/sysupgrade区分
        for TYPE in factory sysupgrade; do
            BIN=$(find ./bin/targets -type f -name "*${DEV}*${TYPE}*.bin" | head -n1)
            if [ -f "$BIN" ]; then
                cp "$BIN" "${OUTPUT_DIR}/${REPO_SHORT}-${DEV}-${TYPE}-${CFG}.bin"
                echo "已复制固件: ${REPO_SHORT}-${DEV}-${TYPE}-${CFG}.bin"
            else
                echo "警告: 未找到 ${DEV} 的 ${TYPE} 固件"
            fi
        done
        # .manifest/.buildinfo/.config
        for EXT in manifest config buildinfo; do
            FILE=$(find ./bin/targets -type f -name "*${DEV}*.${EXT}" | head -n1)
            if [ -f "$FILE" ]; then
                cp "$FILE" "${OUTPUT_DIR}/${REPO_SHORT}-${DEV}-${CFG}.${EXT}"
                echo "已复制 ${EXT} 文件: ${REPO_SHORT}-${DEV}-${CFG}.${EXT}"
            else
                echo "警告: 未找到 ${DEV} 的 ${EXT} 文件"
            fi
        done
    done
    # 拷贝ipk包
    echo "正在收集IPK包..."
    find ./bin/packages ./bin/targets -type f \( -name '*.ipk' -o -name '*.apk' \) -exec cp -f {} "$PKG_DIR" \;
    echo "IPK包收集完成"

done

# 产物打包
echo "正在打包产物..."
cd "$OUTPUT_DIR"
tar czf "${CHIP}-config.tar.gz" *.config *.manifest *.buildinfo || echo "警告: 配置文件打包失败"
tar czf "${CHIP}-log.tar.gz" logs/*.log logs/*.err || echo "警告: 日志文件打包失败"
tar czf "${CHIP}-app.tar.gz" ipk/*.ipk ipk/*.apk || echo "警告: 应用包打包失败"
cd -
echo "产物打包完成"

# 输出版本、设备、luci-app信息（供Release body引用）
echo "内核版本: $KERNEL_VER"
echo "设备: $DEVICES"
echo "luci-app: $LUCI_APPS"
