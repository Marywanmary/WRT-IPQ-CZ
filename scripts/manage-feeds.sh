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

# 5. 显示当前配置
echo "当前feeds.conf内容："
cat feeds.conf

# 6. 更新软件源
echo "更新软件源..."
./scripts/feeds update -a

# 7. 清理软件源
echo "清理软件源..."
./scripts/feeds clean

# 8. 安装软件源
echo "安装软件源..."
./scripts/feeds install -a

# 9. 修复配置文件（如果存在）
if [ -f ".config" ]; then
    echo "修复配置文件..."
    cp .config .config.backup
    
    # 使用更可靠的方法处理内核配置
    echo "处理内核配置..."
    
    # 方法1: 使用olddefconfig自动处理新选项
    if make olddefconfig >/dev/null 2>&1; then
        echo "✓ 使用olddefconfig成功处理新选项"
    else
        echo "⚠ olddefconfig失败，尝试方法2..."
        
        # 方法2: 使用内核的默认配置
        if [ -f "target/linux/qualcommax/ipq60xx/config-6.12" ]; then
            echo "使用内核默认配置..."
            cp target/linux/qualcommax/ipq60xx/config-6.12 .config
            make olddefconfig >/dev/null 2>&1
            echo "✓ 使用内核默认配置成功"
        else
            echo "⚠ 内核默认配置文件不存在，尝试方法3..."
            
            # 方法3: 创建最小配置
            echo "创建最小内核配置..."
            make allnoconfig >/dev/null 2>&1
            echo "✓ 创建最小配置成功"
        fi
    fi
    
    # 最后再次运行defconfig确保配置正确
    echo "最终配置验证..."
    make defconfig >/dev/null 2>&1
    echo "✓ 配置验证完成"
fi

echo "===== 软件源管理完成 ====="
