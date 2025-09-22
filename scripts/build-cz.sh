#!/bin/bash
# OpenWrt 构建脚本
# 严格错误退出机制
set -e
set -o pipefail  # 添加管道错误检测

# 确保脚本有执行权限
chmod +x "$0"
chmod +x "$(dirname "$0")/script-cz.sh"

# 打印开始信息
echo "=== OpenWrt 构建开始 ==="
echo "芯片架构: $CHIP_ARCH"
echo "配置文件: $CONFIG_PROFILE"
echo "分支名称: $BRANCH_NAME"
echo "基础系统版本: $BASE_VERSION"
echo "当前时间: $(date)"

# 基础系统版本说明：
# 环境变量 BASE_VERSION 用于控制基础系统缓存
# "初始版本" - 表示使用初始的基础配置编译
# "更新版本" - 表示您已修改了基础配置文件，需要重新编译基础系统
# 
# 以下情况需要将 BASE_VERSION 改为"更新版本"：
# 1. 修改了芯片基础配置（configs/ipq60xx_base.config）
# 2. 修改了分支基础配置（configs/op_base.config, configs/imm_base.config, configs/lib_base.config）
# 
# 如果不修改为基础系统版本，系统会使用旧的缓存，导致您修改的配置不生效！

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

# 检查必要的工具
echo "=== 检查必要的工具 ==="
if ! command -v rsync &> /dev/null; then
    echo "错误: rsync 未安装"
    exit 1
fi

if ! python3 -c "import distutils" &> /dev/null; then
    echo "错误: python3-distutils 未安装"
    exit 1
fi

# 检查flex和bison
if ! command -v flex &> /dev/null; then
    echo "错误: flex 未安装"
    exit 1
fi

if ! command -v bison &> /dev/null; then
    echo "错误: bison 未安装"
    exit 1
fi

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
chmod +x ../scripts/script-cz.sh
../scripts/script-cz.sh

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

# 创建临时配置文件
cat "$CHIP_CONFIG" > "$CONFIG_FILE"
if [ -f "../configs/$BRANCH_CONFIG" ]; then
    cat "../configs/$BRANCH_CONFIG" >> "$CONFIG_FILE"
fi
cat "$PROFILE_CONFIG" >> "$CONFIG_FILE"

# 应用配置并解决冲突
echo "=== 应用配置并解决冲突 ==="
make defconfig

# 验证配置
echo "=== 验证配置 ==="
if ! ./scripts/diffconfig.sh > /dev/null; then
    echo "警告: 配置验证失败，尝试修复..."
    # 尝试修复配置
    make defconfig
    if ! ./scripts/diffconfig.sh > /dev/null; then
        echo "错误: 无法修复配置问题"
        exit 1
    fi
fi

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

# 设置工具链环境变量
export PATH="$(pwd)/staging_dir/host/bin:$PATH"
export STAGING_DIR_HOST="$(pwd)/staging_dir/host"
export STAGING_DIR_TARGET="$(pwd)/staging_dir/target-$(grep CONFIG_TARGET_ARCH .config | cut -d'"' -f2)_$(grep CONFIG_TARGET_SUFFIX .config | cut -d'"' -f2)"

# 验证工具链是否可用
if ! command -v aarch64-openwrt-linux-musl-gcc &> /dev/null; then
    echo "错误: 交叉编译器不可用"
    exit 1
fi

# 2. 依赖包下载 (添加重试机制)
echo "=== 下载依赖包 ==="
download_success=false
for i in {1..3}; do
    echo "第 $i 次尝试下载依赖包..."
    if make download -j$(nproc); then
        download_success=true
        break
    else
        echo "第 $i 次下载失败，清理后重试..."
        # 清理可能损坏的下载文件
        find dl -name "*.tar.*" -type f -exec rm -f {} \;
        # 等待一段时间再重试
        sleep 30
    fi
done

if [ "$download_success" = false ]; then
    echo "错误: 依赖包下载失败，已重试3次"
    exit 1
fi

# 3. 内核编译 (添加详细日志和错误处理)
if [ ! -d "build_dir/target-*/linux-*/" ]; then
    echo "=== 编译内核 ==="
    
    # 创建日志目录
    mkdir -p logs
    
    # 确保环境变量正确设置
    export PATH="$(pwd)/staging_dir/host/bin:$PATH"
    export STAGING_DIR_HOST="$(pwd)/staging_dir/host"
    
    # 验证工具链
    if ! command -v aarch64-openwrt-linux-musl-gcc &> /dev/null; then
        echo "错误: 内核编译前交叉编译器不可用"
        exit 1
    fi
    
    # 验证flex和bison
    if ! command -v flex &> /dev/null; then
        echo "错误: flex不可用"
        exit 1
    fi
    
    if ! command -v bison &> /dev/null; then
        echo "错误: bison不可用"
        exit 1
    fi
    
    # 先尝试单线程编译，以便查看详细错误
    echo "=== 第一次尝试：单线程编译内核 ==="
    if make target/linux/compile -j1 V=s 2>&1 | tee logs/kernel_compile_1.log; then
        echo "=== 内核编译成功 ==="
    else
        echo "错误: 内核编译失败，尝试使用不同的编译选项..."
        
        # 保存错误日志
        cp logs/kernel_compile_1.log logs/kernel_compile_error.log
        
        # 分析错误日志
        echo "=== 分析错误日志 ==="
        if grep -q "Could not find compiler" logs/kernel_compile_error.log; then
            echo "检测到编译器问题，重新安装工具链..."
            rm -rf staging_dir
            make toolchain/install -j$(nproc)
            # 重新设置环境变量
            export PATH="$(pwd)/staging_dir/host/bin:$PATH"
            export STAGING_DIR_HOST="$(pwd)/staging_dir/host"
        fi
        
        if grep -q "flex: not found" logs/kernel_compile_error.log; then
            echo "检测到flex缺失问题"
            exit 1
        fi
        
        # 清理内核编译目录
        echo "=== 清理内核编译目录 ==="
        rm -rf build_dir/target-*/linux-*/
        
        # 禁用可能有问题的包
        echo "=== 禁用可能有问题的包 ==="
        echo "# CONFIG_PACKAGE_kmod-qca-nss-crypto is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-qca-nss-drv is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-qca-nss-clients is not set" >> .config
        echo "# CONFIG_PACKAGE_nss-firmware is not set" >> .config
        
        # 禁用OpenAppFilter相关包
        echo "# CONFIG_PACKAGE_kmod-open-app-filter is not set" >> .config
        echo "# CONFIG_PACKAGE_open-app-filter is not set" >> .config
        
        # 禁用其他可能与内核冲突的包
        echo "# CONFIG_PACKAGE_kmod-tailscale is not set" >> .config
        
        # 重新应用配置
        make defconfig
        
        # 再次尝试编译内核
        echo "=== 第二次尝试：编译内核（禁用问题包后）==="
        if make target/linux/compile -j$(nproc) 2>&1 | tee logs/kernel_compile_2.log; then
            echo "=== 内核编译成功 ==="
        else
            echo "错误: 内核编译失败，即使禁用了问题包"
            
            # 保存错误日志
            cp logs/kernel_compile_2.log logs/kernel_compile_error_2.log
            
            # 尝试使用最小配置
            echo "=== 第三次尝试：使用最小配置编译内核 ==="
            
            # 备份当前配置
            cp .config .config.backup
            
            # 创建最小配置
            echo "=== 创建最小配置 ==="
            make defconfig
            
            # 只保留最基本的配置
            echo "=== 清理非必要配置 ==="
            ./scripts/diffconfig.sh | grep -v "^#" | grep -v "^$" > .config.minimal
            mv .config.minimal .config
            
            # 重新应用配置
            make defconfig
            
            # 尝试编译内核
            if make target/linux/compile -j$(nproc) 2>&1 | tee logs/kernel_compile_3.log; then
                echo "=== 内核编译成功（使用最小配置）==="
                
                # 恢复原始配置
                mv .config.backup .config
                make defconfig
            else
                echo "错误: 内核编译失败，即使使用最小配置"
                
                # 保存错误日志
                cp logs/kernel_compile_3.log logs/kernel_compile_error_3.log
                
                # 恢复原始配置
                mv .config.backup .config
                make defconfig
                
                # 退出并返回错误
                exit 1
            fi
        fi
    fi
else
    echo "=== 使用缓存的内核 ==="
fi

# 4. 基础系统编译 (根据基础系统版本决定)
# 重要说明：
# 当 BASE_VERSION 为"初始版本"时，如果存在基础系统缓存则使用缓存
# 当 BASE_VERSION 为"更新版本"时，强制重新编译基础系统（忽略缓存）
if [ "$BASE_VERSION" = "更新版本" ]; then
    echo "=== 检测到基础系统版本为'更新版本'，强制重新编译基础系统 ==="
    rm -rf build_dir/target-*/root-*/
    rm -rf staging_dir/target-*/
    make target/compile -j$(nproc) || {
        echo "错误: 基础系统编译失败"
        exit 1
    }
elif [ ! -d "build_dir/target-*/root-*/" ]; then
    echo "=== 编译基础系统 ==="
    make target/compile -j$(nproc) || {
        echo "错误: 基础系统编译失败"
        exit 1
    }
else
    echo "=== 使用缓存的基础系统 ==="
fi

# 5. 软件包编译 (添加错误处理)
echo "=== 编译软件包 ==="
# 先尝试编译所有软件包，如果有问题再处理
if ! make package/compile -j$(nproc); then
    echo "错误: 软件包编译失败，尝试跳过有问题的包..."
    # 记录编译失败的包
    make package/compile -j1 V=s 2> compile_errors.log || true
    # 分析错误日志，找出有问题的包
    grep "ERROR:" compile_errors.log | grep -o "package/[^/]*" | sort | uniq > problem_packages.txt
    echo "以下包编译失败，将被禁用:"
    cat problem_packages.txt
    
    # 禁用有问题的包
    while read -r pkg; do
        pkg_name=$(echo "$pkg" | sed 's/package\///')
        echo "禁用包: $pkg_name"
        echo "# CONFIG_PACKAGE_$pkg_name is not set" >> .config
    done < problem_packages.txt
    
    # 重新应用配置
    make defconfig
    # 再次尝试编译软件包
    make package/compile -j$(nproc) || {
        echo "错误: 软件包编译失败，即使禁用了问题包"
        exit 1
    }
fi

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
