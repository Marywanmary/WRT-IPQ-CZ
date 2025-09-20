# Dockerfile for OpenWrt building
ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION}

ARG CHIP_ARCH=ipq60xx

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV CCACHE_DIR=/ccache
ENV CCACHE_MAXSIZE=5G

# 安装编译依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    ccache \
    file \
    gawk \
    gettext \
    git \
    libncurses5-dev \
    libssl-dev \
    python3 \
    unzip \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR /openwrt

# 创建缓存目录
RUN mkdir -p /ccache /dl /staging_dir

# 复制构建脚本
COPY scripts/build.sh /openwrt/scripts/build.sh
RUN chmod +x /openwrt/scripts/build.sh

# 设置入口点
ENTRYPOINT ["/openwrt/scripts/build.sh"]
