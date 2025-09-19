#!/bin/bash

REPO_SHORT=$1
CONFIG_TYPE=$2
DEVICE=$3
CHIP=$4

# 创建临时目录
mkdir -p artifacts/${CHIP}-config
mkdir -p artifacts/${CHIP}-log
mkdir -p artifacts/${CHIP}-app
mkdir -p artifacts/firmware

# 固件重命名和复制
for file in openwrt/bin/targets/qualcommax/${CHIP}/*.bin; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # 提取固件类型（factory或sysupgrade）
        if [[ "$filename" == *"factory"* ]]; then
            fw_type="factory"
        elif [[ "$filename" == *"sysupgrade"* ]]; then
            fw_type="sysupgrade"
        else
            continue
        fi
        
        # 新文件名：分支缩写-芯片变量-设备名称-固件类型-设备配置.bin
        new_filename="${REPO_SHORT}-${CHIP}-${DEVICE}-${fw_type}-${CONFIG_TYPE}.bin"
        cp "$file" "artifacts/firmware/$new_filename"
    fi
done

# 配置文件重命名和复制
if [ -f "openwrt/.config" ]; then
    cp "openwrt/.config" "artifacts/${CHIP}-config/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}.config"
fi

if [ -f "openwrt/.config.manifest" ]; then
    cp "openwrt/.config.manifest" "artifacts/${CHIP}-config/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}.manifest"
fi

if [ -f "openwrt/.config.buildinfo" ]; then
    cp "openwrt/.config.buildinfo" "artifacts/${CHIP}-config/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}.config.buildinfo"
fi

# 日志文件复制
if [ -f "openwrt/build.log" ]; then
    cp "openwrt/build.log" "artifacts/${CHIP}-log/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}-build.log"
fi

if [ -f "build-error.log" ]; then
    cp "build-error.log" "artifacts/${CHIP}-log/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}-error.log"
fi

# 软件包复制
for pkg_dir in openwrt/bin/packages/*/ openwrt/bin/targets/qualcommax/${CHIP}/packages/; do
    if [ -d "$pkg_dir" ]; then
        find "$pkg_dir" -name "*.ipk" -exec cp {} artifacts/${CHIP}-app/ \;
    fi
done

echo "Artifacts prepared for $REPO_SHORT-$CONFIG_TYPE-$DEVICE ($CHIP)"
