#!/bin/bash

# 统一管理第三方软件源
# 用法: ./scripts/manage-feeds.sh <openwrt_dir>

OPENWRT_DIR=$1

# 检查OpenWrt目录是否存在
if [ ! -d "$OPENWRT_DIR" ]; then
    echo "Error: OpenWrt directory $OPENWRT_DIR not found!"
    exit 1
fi

cd "$OPENWRT_DIR"

echo "===== 管理第三方软件源 ====="

# 1. 备份原始配置
if [ -f "feeds.conf.default" ]; then
    cp feeds.conf.default feeds.conf.default.bak
fi

# 2. 清空并创建新的feeds.conf.default
> feeds.conf.default

# 3. 使用printf方式添加软件源（更可靠）
printf "src-git tailscale https://github.com/tailscale/tailscale\n" >> feeds.conf.default
printf "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan\n" >> feeds.conf.default
printf "src-git lucky https://github.com/gdy666/luci-app-lucky\n" >> feeds.conf.default
printf "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo\n" >> feeds.conf.default
printf "src-git small-package https://github.com/kenzok8/small-package\n" >> feeds.conf.default

echo "第三方软件源配置已添加到feeds.conf.default"

# 4. 同步到feeds.conf
cp feeds.conf.default feeds.conf
echo "✓ 已同步feeds.conf"

# 5. 显示当前配置（使用cat -A显示所有字符）
echo "当前feeds.conf内容（显示所有字符）："
cat -A feeds.conf

# 6. 逐行检查格式
echo "逐行检查格式："
line_num=1
while IFS= read -r line; do
    echo "第${line_num}行: '$line'"
    ((line_num++))
done < feeds.conf

# 7. 尝试逐行添加并测试
echo "尝试逐行添加并测试..."

# 创建临时测试文件
> test_feeds.conf

# 逐行添加并测试
sources=(
    "src-git tailscale https://github.com/tailscale/tailscale"
    "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan"
    "src-git lucky https://github.com/gdy666/luci-app-lucky"
    "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo"
    "src-git small-package https://github.com/kenzok8/small-package"
)

valid_sources=()
for source in "${sources[@]}"; do
    echo "测试源: $source"
    
    # 添加到测试文件
    echo "$source" >> test_feeds.conf
    
    # 复制到feeds.conf进行测试
    cp test_feeds.conf feeds.conf
    
    # 测试语法
    if ./scripts/feeds list >/dev/null 2>&1; then
        echo "✓ 源格式正确"
        valid_sources+=("$source")
    else
        echo "✗ 源格式错误，跳过"
        # 回滚
        sed -i '$d' test_feeds.conf
    fi
done

# 8. 使用有效的源重新创建feeds.conf
echo "使用有效的源重新创建feeds.conf..."
> feeds.conf.default
for source in "${valid_sources[@]}"; do
    echo "$source" >> feeds.conf.default
done

cp feeds.conf.default feeds.conf

# 9. 显示最终配置
echo "最终feeds.conf内容："
cat feeds.conf

# 10. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 11. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 12. 安装软件源
echo "安装软件源..."
./scripts/feeds install -a

# 13. 修复配置文件（如果存在）
if [ -f ".config" ]; then
    echo "修复配置文件..."
    cp .config .config.backup
    
    # 重新生成配置
    make defconfig
fi

echo "===== 软件源管理完成 ====="
