#!/bin/bash

# 构建自定义CoreOS镜像
# 使用方法: ./scripts/build.sh [TAG]

set -e

# 默认标签
TAG=${1:-"custom-coreos:latest"}

# 判断是否使用podman还是docker
CONTAINER_ENGINE="docker"
if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
    echo "检测到podman，将使用podman构建镜像"
else
    echo "未检测到podman，将使用docker构建镜像"
fi

echo "开始构建自定义CoreOS镜像: $TAG"
$CONTAINER_ENGINE build -t $TAG .

echo "构建完成。您可以使用以下命令运行容器:"
echo "$CONTAINER_ENGINE run -it $TAG"