#!/usr/bin/env bash
set -e

# 获取脚本所在目录
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
# 获取仓库根目录（脚本目录的上一级）
BASE_PATH=$(cd "$SCRIPT_DIR/.." && pwd)

# 获取运行脚本时传入的第一个参数（设备名称）
Dev=$1
# 获取运行脚本时传入的第二个参数（构建模式）
Build_Mod=$2

# 定义配置文件的完整路径
CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
# 定义INI配置文件的完整路径
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

# 创建日志目录
LOG_DIR="$BASE_PATH/temp_firmware/$Dev/logs"
mkdir -p "$LOG_DIR"

# 定义日志文件路径
FULL_LOG="$LOG_DIR/build_full.log"
ERROR_LOG="$LOG_DIR/build_errors.log"
WARNING_LOG="$LOG_DIR/build_warnings.log"

# 创建空日志文件
touch "$FULL_LOG" "$ERROR_LOG" "$WARNING_LOG"

# 记录开始时间
echo "Build started at $(date)" | tee "$FULL_LOG"

# 检查配置文件是否存在
if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE" | tee -a "$FULL_LOG" "$ERROR_LOG"
    exit 1
fi

# 检查INI文件是否存在
if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE" | tee -a "$FULL_LOG" "$ERROR_LOG"
    exit 1
fi

# 定义从INI文件中读取指定键值的函数
read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

# 定义移除uhttpd依赖的函数
remove_uhttpd_dependency() {
    local config_path="$BASE_PATH/$BUILD_DIR/.config"
    local luci_makefile_path="$BASE_PATH/$BUILD_DIR/feeds/luci/collections/luci/Makefile"
    # 检查是否启用了quickfile插件
    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            # 删除包含luci-light的行
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled." | tee -a "$FULL_LOG"
        fi
    fi
}

# 定义应用基础配置的函数
apply_base_config() {
    local base_config="$BASE_PATH/base_config/.config"
    if [ -f "$base_config" ]; then
        \cp -f "$base_config" "$BASE_PATH/$BUILD_DIR/.config"
        echo "Applied base config" | tee -a "$FULL_LOG"
    fi
}

# 定义应用特定配置的函数
apply_specific_config() {
    local specific_config="$CONFIG_FILE"
    
    # 提取特定配置中的差异项
    grep -v "^#" "$specific_config" | grep -v "^$" | while read line; do
        # 检查是否是配置项
        if [[ $line =~ ^CONFIG_ ]]; then
            # 提取配置项名称
            config_name=$(echo "$line" | cut -d'=' -f1)
            # 在基础配置中更新该配置项
            sed -i "s/^$config_name=.*/$line/" "$BASE_PATH/$BUILD_DIR/.config"
        fi
    done
    
    echo "Applied specific config for $Dev" | tee -a "$FULL_LOG"
}

# 定义并行下载依赖的函数
download_dependencies() {
    echo "Downloading dependencies in parallel..." | tee -a "$FULL_LOG"
    
    # 使用并行下载
    make download -j$(($(nproc) * 2)) 2>&1 | tee -a "$FULL_LOG"
    
    # 检查下载是否成功
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "Parallel download failed, trying sequential download..." | tee -a "$FULL_LOG"
        make download 2>&1 | tee -a "$FULL_LOG"
    fi
}

# 定义分阶段构建的函数
staged_build() {
    echo "Starting staged build..." | tee -a "$FULL_LOG"
    
    # 第一阶段：编译基础包
    echo "Stage 1: Building base packages..." | tee -a "$FULL_LOG"
    make -j$(($(nproc) + 1)) package/compile 2>&1 | tee -a "$FULL_LOG"
    
    # 第二阶段：编译内核模块
    echo "Stage 2: Building kernel modules..." | tee -a "$FULL_LOG"
    make -j$(($(nproc) + 1)) target/compile 2>&1 | tee -a "$FULL_LOG"
    
    # 第三阶段：生成固件
    echo "Stage 3: Generating firmware..." | tee -a "$FULL_LOG"
    make -j$(($(nproc) + 1)) target/install 2>&1 | tee -a "$FULL_LOG"
    
    # 检查构建是否成功
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "Staged build failed, trying with verbose output..." | tee -a "$FULL_LOG"
        make -j1 V=s 2>&1 | tee -a "$FULL_LOG"
        exit 1
    fi
}

# 从INI文件中读取仓库地址
REPO_URL=$(read_ini_by_key "REPO_URL")
# 从INI文件中读取仓库分支
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
# 如果分支为空则设置为默认值main
REPO_BRANCH=${REPO_BRANCH:-main}
# 从INI文件中读取构建目录
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
# 从INI文件中读取提交哈希值
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
# 如果哈希值为空则设置为默认值none
COMMIT_HASH=${COMMIT_HASH:-none}

# 检查是否存在action_build目录，存在则强制使用该目录作为构建目录
if [[ -d $BASE_PATH/action_build ]]; then
    BUILD_DIR="action_build"
fi

echo "Using repository: $REPO_URL" | tee -a "$FULL_LOG"
echo "Using branch: $REPO_BRANCH" | tee -a "$FULL_LOG"
echo "Using build directory: $BUILD_DIR" | tee -a "$FULL_LOG"
echo "Using commit hash: $COMMIT_HASH" | tee -a "$FULL_LOG"

# 执行更新脚本，传入仓库地址、分支、构建目录和提交哈希值
echo "Running update script..." | tee -a "$FULL_LOG"
"$SCRIPT_DIR/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH/$BUILD_DIR" "$COMMIT_HASH" 2>&1 | tee -a "$FULL_LOG"

# 应用基础配置
apply_base_config

# 应用特定配置
apply_specific_config

# 移除uhttpd依赖
remove_uhttpd_dependency

# 切换到构建目录
cd "$BASE_PATH/$BUILD_DIR"

# 执行make defconfig命令生成默认配置
echo "Running make defconfig..." | tee -a "$FULL_LOG"
make defconfig 2>&1 | tee -a "$FULL_LOG"

# 检查是否是x86_64平台
if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    # 定义软件源配置文件路径
    DISTFEEDS_PATH="$BASE_PATH/$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    # 检查软件源配置文件是否存在
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        # 替换架构名称从ARM到x86_64
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
        echo "Updated architecture to x86_64 in distfeeds.conf" | tee -a "$FULL_LOG"
    fi
fi

# 如果是调试模式则直接退出
if [[ $Build_Mod == "debug" ]]; then
    echo "Debug mode enabled, exiting..." | tee -a "$FULL_LOG"
    exit 0
fi

# 定义目标文件目录路径
TARGET_DIR="$BASE_PATH/$BUILD_DIR/bin/targets"

# 如果目标目录存在，则删除旧的编译产物
if [[ -d $TARGET_DIR ]]; then
    echo "Cleaning old build artifacts..." | tee -a "$FULL_LOG"
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" -o -name ".config" -o -name "config.buildinfo" -o -name "Packages.manifest" \) -exec rm -f {} +
fi

# 增量构建：检查是否已经构建过依赖
if [ -d "$BASE_PATH/$BUILD_DIR/staging_dir" ] && [ -d "$BASE_PATH/$BUILD_DIR/build_dir" ]; then
    echo "Dependencies already built, skipping download..." | tee -a "$FULL_LOG"
else
    # 下载编译所需的源代码包
    download_dependencies
fi

# 开始编译固件
echo "Starting firmware build..." | tee -a "$FULL_LOG"
staged_build

# 创建临时目录用于存放所有产出物
TEMP_DIR="$BASE_PATH/temp_firmware"
\rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 创建总的ipk和apk目录
mkdir -p "$TEMP_DIR/ipk"
mkdir -p "$TEMP_DIR/apk"

# 创建设备专属目录
DEVICE_TEMP_DIR="$TEMP_DIR/$Dev"
mkdir -p "$DEVICE_TEMP_DIR"

# 创建日志目录（确保存在）
mkdir -p "$LOG_DIR"

# 复制.config文件
if [[ -f "$BASE_PATH/$BUILD_DIR/.config" ]]; then
    \cp -f "$BASE_PATH/$BUILD_DIR/.config" "$DEVICE_TEMP_DIR/"
    echo "Copied .config file" | tee -a "$FULL_LOG"
fi

# 复制编译产物文件
echo "Copying build artifacts..." | tee -a "$FULL_LOG"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" -o -name ".config" -o -name "config.buildinfo" -o -name "Packages.manifest" \) -exec cp -f {} "$DEVICE_TEMP_DIR/" \;

# 复制ipk文件
IPK_DIR="$BASE_PATH/$BUILD_DIR/bin/packages"
if [[ -d "$IPK_DIR" ]]; then
    find "$IPK_DIR" -name "*.ipk" -type f -exec cp -f {} "$TEMP_DIR/ipk/" 2>/dev/null || true
    echo "Copied ipk files for $Dev" | tee -a "$FULL_LOG"
fi

# 复制apk文件
APK_DIR="$BASE_PATH/$BUILD_DIR/bin/package"
if [[ -d "$APK_DIR" ]]; then
    find "$APK_DIR" -name "*.apk" -type f -exec cp -f {} "$TEMP_DIR/apk/" 2>/dev/null || true
    echo "Copied apk files for $Dev" | tee -a "$FULL_LOG"
fi

# 固件重命名部分
# 解析设备名称，检查是否符合三段式结构
if [[ $Dev =~ ^([^_]+)_([^_]+)_([^_]+)$ ]]; then
    CHIP="${BASH_REMATCH[1]}"      # 芯片部分
    BRANCH_ABBR="${BASH_REMATCH[2]}" # 分支缩写
    CONFIG="${BASH_REMATCH[3]}"     # 配置部分
    
    echo "Device name parsed: CHIP=$CHIP, BRANCH_ABBR=$BRANCH_ABBR, CONFIG=$CONFIG" | tee -a "$FULL_LOG"
    
    # 重命名固件文件
    for firmware in "$DEVICE_TEMP_DIR"/*.bin; do
        # 获取文件名（不含路径）
        filename=$(basename "$firmware")
        
        # 检查是否是目标固件文件，从芯片变量开始提取设备名称
        if [[ $filename =~ -$CHIP-(.+)-squashfs-(factory|sysupgrade)\.bin ]]; then
            MODEL="${BASH_REMATCH[1]}"   # 固件型号
            MODE="${BASH_REMATCH[2]}"    # 固件模式
            
            # 根据分支缩写构建新文件名
            if [[ "$BRANCH_ABBR" == "immwrt" ]]; then
                new_filename="immwrt-${MODEL}-${MODE}-${CONFIG}.bin"
            elif [[ "$BRANCH_ABBR" == "libwrt" ]]; then
                new_filename="libwrt-${MODEL}-${MODE}-${CONFIG}.bin"
            else
                # 默认格式
                new_filename="${BRANCH_ABBR}-${MODEL}-${MODE}-${CONFIG}.bin"
            fi
            
            # 重命名文件
            mv "$firmware" "$DEVICE_TEMP_DIR/$new_filename"
            echo "Renamed $filename to $new_filename" | tee -a "$FULL_LOG"
        else
            echo "Skipping $filename - does not match expected pattern for chip $CHIP" | tee -a "$FULL_LOG"
        fi
    done
    
    # 重命名manifest文件
    for manifest_file in "$DEVICE_TEMP_DIR"/*.manifest; do
        if [[ -f "$manifest_file" ]]; then
            # 获取文件名（不含路径）
            filename=$(basename "$manifest_file")
            # 构建新文件名
            new_filename="${Dev}.manifest"
            # 重命名文件
            mv "$manifest_file" "$DEVICE_TEMP_DIR/$new_filename"
            echo "Renamed manifest file $filename to $new_filename" | tee -a "$FULL_LOG"
        fi
    done
    
    # 重命名配置文件
    config_files=(".config" "config.buildinfo" "Packages.manifest")
    for file in "${config_files[@]}"; do
        if [[ -f "$DEVICE_TEMP_DIR/$file" ]]; then
            # 构建新文件名
            if [[ "$file" == .* ]]; then
                # 对于以点开头的文件，直接追加
                new_file="${Dev}${file}"
            else
                # 对于其他文件，添加点号
                new_file="${Dev}.${file}"
            fi
            
            # 重命名文件
            mv "$DEVICE_TEMP_DIR/$file" "$DEVICE_TEMP_DIR/$new_file"
            echo "Renamed $file to $new_file" | tee -a "$FULL_LOG"
        else
            echo "Warning: Config file not found in device temp directory: $file" | tee -a "$FULL_LOG" "$WARNING_LOG"
        fi
    done
else
    echo "Device name '$Dev' does not follow the three-part structure, skipping renaming." | tee -a "$FULL_LOG" "$WARNING_LOG"
fi

# 如果存在action_build目录，则执行清理命令
if [[ -d $BASE_PATH/action_build ]]; then
    echo "Cleaning build directory..." | tee -a "$FULL_LOG"
    make clean 2>&1 | tee -a "$FULL_LOG"
fi

# 从完整日志中提取错误信息
echo "=== 错误日志 ===" > "$ERROR_LOG"
grep -i "error\|failed\|failure" "$FULL_LOG" | grep -v "make.*error.*required" >> "$ERROR_LOG" || echo "未发现错误信息" >> "$ERROR_LOG"

# 从完整日志中提取警告信息
echo "=== 警告日志 ===" > "$WARNING_LOG"
grep -i "warning\|warn" "$FULL_LOG" >> "$WARNING_LOG" || echo "未发现警告信息" >> "$WARNING_LOG"

# 记录完成时间
echo "Build completed at $(date)" | tee -a "$FULL_LOG"

echo "Build completed for $Dev. All artifacts are in $DEVICE_TEMP_DIR" | tee -a "$FULL_LOG"
