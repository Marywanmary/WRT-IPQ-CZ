#!/bin/bash
# OpenWrt 构建脚本
# 严格错误退出机制
set -e

# 打印开始信息
echo "=== OpenWrt 构建开始 ==="
echo "芯片架构: $CHIP_ARCH"
echo "配置文件: $CONFIG_PROFILE"
echo "分支名称: $BRANCH_NAME"
echo "基础版本: $BASE_VERSION"
echo "当前时间: $(date)"

# 检查必要的环境变量
if [ -z "$CHIP_ARCH" ] || [ -z "$CONFIG_PROFILE" ] || [ -z "$BRANCH_NAME" ]; then
    echo "错误: 缺少必要的环境变量"
    exit 1
fi

# 设置ccache
export CCACHE_DIR=/ccache
export CCACHE_MAXSIZE=5G
ccache -s

# 显示磁盘使用情况
df -h

# 根据分支设置仓库信息
case "$BRANCH_NAME" in
    "openwrt")
        REPO_URL="https://github.com/laipeng668/openwrt.git"
        REPO_BRANCH="master"
        REPO_SHORT="openwrt"
        BRANCH_CONFIG="op_base.config"
        ;;
    "immortalwrt")
        REPO_URL="https://github.com/laipeng668/immortalwrt.git"
        REPO_BRANCH="master"
        REPO_SHORT="immwrt"
        BRANCH_CONFIG="imm_base.config"
        ;;
    "libwrt")
        REPO_URL="https://github.com/laipeng668/openwrt-6.x.git"
        REPO_BRANCH="k6.12-nss"
        REPO_SHORT="libwrt"
        BRANCH_CONFIG="lib_base.config"
        ;;
    *)
        echo "错误: 不支持的分支 $BRANCH_NAME"
        exit 1
        ;;
esac

# 克隆仓库
echo "=== 克隆仓库 $REPO_URL ==="
git clone --depth=1 -b $REPO_BRANCH $REPO_URL openwrt-src
cd openwrt-src

# 执行自定义脚本
echo "=== 执行自定义脚本 ==="
chmod +x ../scripts/scripts.sh
../scripts/scripts.sh

# 合并配置文件
echo "=== 合并配置文件 ==="
CONFIG_FILE=".config"
CHIP_CONFIG="../configs/${CHIP_ARCH}_base.config"
PROFILE_CONFIG="../configs/${CONFIG_PROFILE}.config"

# 检查配置文件是否存在
if [ ! -f "$CHIP_CONFIG" ]; then
    echo "错误: 芯片配置文件不存在 $CHIP_CONFIG"
    exit 1
fi

if [ ! -f "$PROFILE_CONFIG" ]; then
    echo "错误: 配置文件不存在 $PROFILE_CONFIG"
    exit 1
fi

# 合并配置文件 (按照优先级: 芯片配置 < 分支配置 < 软件包配置)
cat "$CHIP_CONFIG" > "$CONFIG_FILE"
if [ -f "../configs/$BRANCH_CONFIG" ]; then
    cat "../configs/$BRANCH_CONFIG" >> "$CONFIG_FILE"
fi
cat "$PROFILE_CONFIG" >> "$CONFIG_FILE"

# 应用配置
echo "=== 应用配置 ==="
make defconfig

# 分层编译
echo "=== 分层编译开始 ==="

# 1. 工具链编译 (如果缓存不存在)
if [ ! -d "staging_dir" ]; then
    echo "=== 编译工具链 ==="
    make toolchain/install -j$(nproc) || {
        echo "错误: 工具链编译失败"
        exit 1
    }
else
    echo "=== 使用缓存的工具链 ==="
fi

# 2. 依赖包下载
echo "=== 下载依赖包 ==="
make download -j$(nproc) || {
    echo "错误: 依赖包下载失败"
    exit 1
}

# 3. 内核编译 (如果缓存不存在)
if [ ! -d "build_dir/target-*/linux-*/" ]; then
    echo "=== 编译内核 ==="
    make target/linux/compile -j$(nproc) || {
        echo "错误: 内核编译失败"
        exit 1
    }
else
    echo "=== 使用缓存的内核 ==="
fi

# 4. 基础系统编译 (如果缓存不存在)
if [ ! -d "build_dir/target-*/root-*/" ]; then
    echo "=== 编译基础系统 ==="
    make target/compile -j$(nproc) || {
        echo "错误: 基础系统编译失败"
        exit 1
    }
else
    echo "=== 使用缓存的基础系统 ==="
fi

# 5. 软件包编译
echo "=== 编译软件包 ==="
make package/compile -j$(nproc) || {
    echo "错误: 软件包编译失败"
    exit 1
}

# 6. 固件打包
echo "=== 打包固件 ==="
make target/install -j1 || {
    echo "错误: 固件打包失败"
    exit 1
}

# 清理中间文件
echo "=== 清理中间文件 ==="
make clean
rm -rf build_dir/target-*/linux-*/.{tmp,modorder}
find build_dir -name ".pkgdir" -type d -exec rm -rf {} +
find dl -type f -name "*.tar.*" -mtime +7 -delete
ccache -C

# 显示磁盘使用情况
df -h

# 显示ccache统计
ccache -s

echo "=== OpenWrt 构建完成 ==="
