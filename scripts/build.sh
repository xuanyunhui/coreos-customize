#!/bin/bash

# 构建自定义CoreOS镜像
# 使用方法: ./scripts/build.sh [TAG] [是否使用特权模式]
# 例如: ./scripts/build.sh custom-coreos:latest true

set -e

# 默认标签
TAG=${1:-"custom-coreos:latest"}

# 是否使用特权模式
USE_PRIVILEGED=${2:-"false"}

# 判断是否使用podman还是docker
CONTAINER_ENGINE="docker"
if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
    echo "检测到podman，将使用podman构建镜像"
else
    echo "未检测到podman，将使用docker构建镜像"
fi

# 构建参数
BUILD_ARGS=""
if [ "$USE_PRIVILEGED" = "true" ]; then
    BUILD_ARGS="--build-arg USE_PRIVILEGED=true --privileged"
    echo "将使用特权模式构建"
fi

echo "开始构建自定义CoreOS镜像: $TAG"
$CONTAINER_ENGINE build $BUILD_ARGS -t $TAG .

echo "构建完成。您可以使用以下命令运行容器:"
echo "$CONTAINER_ENGINE run -it $TAG"