#!/bin/bash
# OpenWrt固件编译脚本
# 作者: Mary
# 功能: 根据配置文件编译OpenWrt固件，支持分层编译

# 严格错误退出机制 - 任何命令返回非零状态码都会立即退出脚本
set -euo pipefail

# 检查参数
if [ $# -eq 0 ]; then
    echo "错误: 未指定配置类型"
    echo "用法: $0 <配置类型>"
    echo "配置类型: Ultra, Max, Pro"
    exit 1
fi

# 获取参数
CONFIG_TYPE="$1"
ARCH="${ARCH:-ipq60xx}"
BRANCH="${BRANCH:-openwrt}"
BRANCH_SHORT="${BRANCH_SHORT:-openwrt}"
WORKSPACE="${WORKSPACE:-$(pwd)}"
COMPILE_STAGE="${COMPILE_STAGE:-full}"

# 检查配置类型是否有效
if [[ ! "$CONFIG_TYPE" =~ ^(Ultra|Max|Pro)$ ]]; then
    echo "错误: 无效的配置类型 '$CONFIG_TYPE'"
    echo "有效配置类型: Ultra, Max, Pro"
    exit 1
fi

# 检查编译阶段是否有效
if [[ ! "$COMPILE_STAGE" =~ ^(full|toolchain|kernel|base|packages)$ ]]; then
    echo "错误: 无效的编译阶段 '$COMPILE_STAGE'"
    echo "有效编译阶段: full, toolchain, kernel, base, packages"
    exit 1
fi

# 设置日志文件
LOG_FILE="build.log"
ERROR_LOG_FILE="build-error.log"

# 初始化日志文件
echo "===== 编译日志 - $(date) =====" > "$LOG_FILE"
echo "===== 错误日志 - $(date) =====" > "$ERROR_LOG_FILE"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1" | tee -a "$LOG_FILE" "$ERROR_LOG_FILE"
}

# 错误处理函数
handle_error() {
    local exit_code=$?
    local line_number=$1
    error_log "脚本在第 $line_number 行退出，退出代码: $exit_code"
    
    # 显示磁盘使用情况
    log "磁盘使用情况:"
    df -h | tee -a "$LOG_FILE"
    
    # 显示最后几行日志，帮助诊断问题
    log "最后50行日志:"
    tail -n 50 "$LOG_FILE" | tee -a "$ERROR_LOG_FILE"
    
    # 检查是否有编译错误日志
    if [ -d "logs" ]; then
        log "编译错误日志:"
        find logs -name "*.log" -exec echo "=== {} ===" \; -exec tail -n 20 {} \;
    fi
    
    exit $exit_code
}

# 设置错误陷阱 - 当脚本出错时调用handle_error函数
trap 'handle_error $LINENO' ERR

# 开始编译
log "开始编译 $BRANCH_SHORT/$ARCH/$CONFIG_TYPE (阶段: $COMPILE_STAGE)"

# 检查工作目录
if [ ! -f "Makefile" ]; then
    error_log "当前目录不是OpenWrt根目录"
    exit 1
fi

# 显示磁盘使用情况
log "初始磁盘使用情况:"
df -h | tee -a "$LOG_FILE"

# 显示系统信息
log "系统信息:"
uname -a | tee -a "$LOG_FILE"
log "CPU信息:"
lscpu | grep "^Model name" | tee -a "$LOG_FILE"
log "内存信息:"
free -h | tee -a "$LOG_FILE"

# 检查必要的工具
log "检查必要的工具:"
which make gcc g++ python3 git wget | tee -a "$LOG_FILE"

# 合并配置文件
log "合并配置文件"

# 确保configs目录存在
mkdir -p configs

# 检查配置文件是否存在
CHIP_CONFIG="$WORKSPACE/openwrt-build/configs/${ARCH}_base.config"
BRANCH_CONFIG="$WORKSPACE/openwrt-build/configs/${BRANCH_SHORT}_base.config"
PACKAGE_CONFIG="$WORKSPACE/openwrt-build/configs/${CONFIG_TYPE}.config"

if [ ! -f "$CHIP_CONFIG" ]; then
    error_log "芯片配置文件不存在: $CHIP_CONFIG"
    exit 1
fi

if [ ! -f "$BRANCH_CONFIG" ]; then
    error_log "分支配置文件不存在: $BRANCH_CONFIG"
    exit 1
fi

if [ ! -f "$PACKAGE_CONFIG" ]; then
    error_log "软件包配置文件不存在: $PACKAGE_CONFIG"
    exit 1
fi

# 合并配置文件（按照优先级顺序：芯片配置 < 分支配置 < 软件包配置）
log "合并配置文件: $CHIP_CONFIG + $BRANCH_CONFIG + $PACKAGE_CONFIG"
cat "$CHIP_CONFIG" > .config
cat "$BRANCH_CONFIG" >> .config
cat "$PACKAGE_CONFIG" >> .config

# 保存合并后的配置文件
cp .config ".config.$CONFIG_TYPE"
log "配置文件已合并并保存为 .config.$CONFIG_TYPE"

# 更新配置
log "更新配置"
make defconfig >> "$LOG_FILE" 2>&1

# 分层编译
case "$COMPILE_STAGE" in
    full)
        log "执行完整编译流程"
        
        # 下载依赖
        log "下载依赖"
        make download -j$(nproc) >> "$LOG_FILE" 2>&1
        
        # 编译工具链
        log "编译工具链"
        make toolchain/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译内核
        log "编译内核"
        make target/linux/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译基础系统
        log "编译基础系统"
        make target/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译软件包
        log "编译软件包"
        make package/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 安装软件包
        log "安装软件包"
        make package/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译目标
        log "编译目标"
        make target/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 生成固件
        log "生成固件"
        make image -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        ;;
        
    toolchain)
        log "从工具链阶段开始编译"
        
        # 下载依赖
        log "下载依赖"
        make download -j$(nproc) >> "$LOG_FILE" 2>&1
        
        # 编译工具链
        log "编译工具链"
        make toolchain/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译内核
        log "编译内核"
        make target/linux/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译基础系统
        log "编译基础系统"
        make target/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译软件包
        log "编译软件包"
        make package/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 安装软件包
        log "安装软件包"
        make package/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译目标
        log "编译目标"
        make target/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 生成固件
        log "生成固件"
        make image -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        ;;
        
    kernel)
        log "从内核阶段开始编译"
        
        # 编译内核
        log "编译内核"
        make target/linux/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译基础系统
        log "编译基础系统"
        make target/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译软件包
        log "编译软件包"
        make package/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 安装软件包
        log "安装软件包"
        make package/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译目标
        log "编译目标"
        make target/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 生成固件
        log "生成固件"
        make image -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        ;;
        
    base)
        log "从基础系统阶段开始编译"
        
        # 编译基础系统
        log "编译基础系统"
        make target/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译软件包
        log "编译软件包"
        make package/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 安装软件包
        log "安装软件包"
        make package/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译目标
        log "编译目标"
        make target/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 生成固件
        log "生成固件"
        make image -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        ;;
        
    packages)
        log "从软件包阶段开始编译（包含固件生成）"
        
        # 编译软件包
        log "编译软件包"
        make package/compile -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 安装软件包
        log "安装软件包"
        make package/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 编译目标
        log "编译目标"
        make target/install -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        
        # 生成固件
        log "生成固件"
        make image -j$(nproc) V=s >> "$LOG_FILE" 2>&1
        ;;
        
    *)
        error_log "未知的编译阶段: $COMPILE_STAGE"
        exit 1
        ;;
esac

# 生成清单文件
if [ -f ".config" ]; then
    log "生成清单文件"
    ./scripts/diffconfig.sh > ".config.$CONFIG_TYPE.buildinfo"
    
    # 生成软件包清单
    if [ -d "bin/targets" ]; then
        find bin/targets -name "*.manifest" -exec cp {} ".config.$CONFIG_TYPE.manifest" \;
    fi
fi

# 重命名固件文件
log "重命名固件文件"
if [ -d "bin/targets" ]; then
    # 查找所有固件文件
    find bin/targets -name "*.bin" -type f | while read firmware; do
        # 获取文件名
        filename=$(basename "$firmware")
        
        # 提取设备名称和固件类型
        device_name=$(echo "$filename" | sed -n 's/.*-\(jdcloud_re-[cs][sp]-[0-9][0-9]\)-.*/\1/p')
        firmware_type=$(echo "$filename" | sed -n 's/.*-\(factory\|sysupgrade\)\.bin/\1/p')
        
        # 重命名固件
        if [ -n "$device_name" ] && [ -n "$firmware_type" ]; then
            new_filename="${BRANCH_SHORT}-${device_name}-${firmware_type}-${CONFIG_TYPE}.bin"
            mv "$firmware" "$(dirname "$firmware")/$new_filename"
            log "固件已重命名: $filename -> $new_filename"
        fi
    done
fi

# 收集软件包
log "收集软件包"
mkdir -p packages
if [ -d "bin/targets" ]; then
    find bin/targets -name "*.ipk" -exec cp {} packages/ \;
fi

log "编译完成: $BRANCH_SHORT/$ARCH/$CONFIG_TYPE (阶段: $COMPILE_STAGE)"
