#!/usr/bin/env bash
set -e

# 获取脚本所在目录
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
# 获取仓库根目录（脚本目录的上一级）
BASE_PATH=$(cd "$SCRIPT_DIR/.." && pwd)

# 获取运行脚本时传入的第一个参数（设备名称）
Dev=$1

# 定义配置文件的完整路径
CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
# 定义INI配置文件的完整路径
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

# 检查配置文件是否存在
if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

# 检查INI文件是否存在
if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

# 定义从INI文件中读取指定键值的函数
read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

# 从INI文件中读取仓库地址
REPO_URL=$(read_ini_by_key "REPO_URL")
# 从INI文件中读取仓库分支
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
# 如果分支为空则设置为默认值main
REPO_BRANCH=${REPO_BRANCH:-main}
# 定义构建目录路径
BUILD_DIR="$BASE_PATH/action_build"

# 定义共享构建目录路径
SHARED_BUILD_DIR="$BASE_PATH/shared_build"

# 确保共享目录存在
mkdir -p "$SHARED_BUILD_DIR"

# 创建符号链接到共享目录
if [ ! -L "$BUILD_DIR" ]; then
    ln -sf "$SHARED_BUILD_DIR" "$BUILD_DIR"
fi

# 显示仓库地址和分支
echo $REPO_URL $REPO_BRANCH
# 将仓库地址和分支信息写入标记文件
echo "$REPO_URL/$REPO_BRANCH" >"$BASE_PATH/repo_flag"

# 增量构建：检查仓库是否已存在
if [ -d "$BUILD_DIR" ]; then
    echo "Repository already exists, updating..."
    cd "$BUILD_DIR"
    git fetch origin
    git checkout $REPO_BRANCH
    git pull origin $REPO_BRANCH
    cd "$BASE_PATH"
else
    echo "Cloning repository..."
    git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR
fi

# 定义项目镜像源配置文件路径
PROJECT_MIRRORS_FILE="$BUILD_DIR/scripts/projectsmirrors.json"
# 检查镜像源配置文件是否存在
if [ -f "$PROJECT_MIRRORS_FILE" ]; then
    # 删除包含国内镜像源的行
    sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi

# 创建基础配置目录
mkdir -p "$BASE_PATH/base_config"

# 如果基础配置不存在，创建它
if [ ! -f "$BASE_PATH/base_config/.config" ]; then
    echo "Creating base config..."
    # 使用 Pro 配置作为基础配置
    cp "$BASE_PATH/deconfig/ipq60xx_immwrt_Pro.config" "$BASE_PATH/base_config/.config"
    # 移除特定于 Pro/Max/Ultra 的配置项
    sed -i '/CONFIG_PACKAGE_luci-app-quickfile/d' "$BASE_PATH/base_config/.config"
    sed -i '/CONFIG_PACKAGE_luci-app-timecontrol/d' "$BASE_PATH/base_config/.config"
    sed -i '/CONFIG_PACKAGE_luci-app-gecoosac/d' "$BASE_PATH/base_config/.config"
fi
