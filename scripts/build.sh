#!/bin/bash

# 构建自定义CoreOS镜像
# 使用方法: ./scripts/build.sh [TAG]

set -e

# 默认标签
TAG=${1:-"custom-coreos:latest"}

echo "开始构建自定义CoreOS镜像: $TAG"
docker build -t $TAG .

echo "构建完成。您可以使用以下命令运行容器:"
echo "docker run -it $TAG" 