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

# 合并配置函数，按优先级合并芯片+分支+软件包
merge_config() {
  local device_cfg="$1"
  cat "${CONFIG_DIR}/${CHIP}_base.config" "${CONFIG_DIR}/${REPO_SHORT}_base.config" "${CONFIG_DIR}/${device_cfg}.config" > .config
}

# 提取设备名列表（支持多设备）
get_device_names() {
  grep -E 'CONFIG_TARGET_DEVICE_.*=y' .config | sed 's/.*DEVICE_\(.*\)=y/\1/' | sed 's/\"//g'
}

# 提取内核版本
get_kernel_version() {
  [ -f include/kernel-version.mk ] && grep "LINUX_VERSION-$(grep "^KERNEL_PATCHVER:=" include/kernel-version.mk | cut -d'=' -f2)-=" include/kernel-version.mk | head -n1 | awk '{print $3}' || echo "unknown"
}

# 提取luci app列表
get_luci_apps() {
  grep 'CONFIG_PACKAGE_luci-app-' .config | grep '=y' | cut -d'_' -f3- | cut -d'=' -f1 | sort | uniq | tr '\n' ' '
}

# 主循环：每种配置串行编译
for CFG in "${CONFIGS[@]}"; do
  echo "【${CFG}】配置合并并开始编译"
  merge_config "$CFG"
  cp .config "${TMP_DIR}/${REPO_SHORT}-${CHIP}-${CFG}.config"

  # 清理空间
  make dirclean > /dev/null 2>&1 || true

  # 生成默认配置
  yes "" | make defconfig

  # 编译并重定向日志
  LOG_FILE="${LOG_DIR}/${REPO_SHORT}-${CHIP}-${CFG}.log"
  ERR_FILE="${LOG_DIR}/${REPO_SHORT}-${CHIP}-${CFG}.err"
  {
    make -j$(nproc) V=s || { echo "编译失败" | tee -a "$ERR_FILE"; exit 1; }
  } 2>&1 | tee "$LOG_FILE" | grep -i 'error\|warn\|failed' > "$ERR_FILE" || true

  # 提取设备名、内核版本、luci-app
  DEVICES=$(get_device_names)
  KERNEL_VER=$(get_kernel_version)
  LUCI_APPS=$(get_luci_apps)

  # 固件产物处理
  for DEV in $DEVICES; do
    # factory/sysupgrade区分
    for TYPE in factory sysupgrade; do
      BIN=$(find ./bin/targets -type f -name "*${DEV}*${TYPE}*.bin" | head -n1)
      [ -f "$BIN" ] && cp "$BIN" "${OUTPUT_DIR}/${REPO_SHORT}-${DEV}-${TYPE}-${CFG}.bin"
    done
    # .manifest/.buildinfo/.config
    for EXT in manifest config buildinfo; do
      FILE=$(find ./bin/targets -type f -name "*${DEV}*.${EXT}" | head -n1)
      [ -f "$FILE" ] && cp "$FILE" "${OUTPUT_DIR}/${REPO_SHORT}-${DEV}-${CFG}.${EXT}"
    done
  done
  # 拷贝ipk包
  find ./bin/packages ./bin/targets -type f \( -name '*.ipk' -o -name '*.apk' \) -exec cp -f {} "$PKG_DIR" \;

done

# 产物打包
cd "$OUTPUT_DIR"
tar czf "${CHIP}-config.tar.gz" *.config *.manifest *.buildinfo || true
tar czf "${CHIP}-log.tar.gz" logs/*.log logs/*.err || true
tar czf "${CHIP}-app.tar.gz" ipk/*.ipk ipk/*.apk || true
cd -

# 输出版本、设备、luci-app信息（供Release body引用）
echo "内核版本: $KERNEL_VER"
echo "设备: $DEVICES"
echo "luci-app: $LUCI_APPS"
