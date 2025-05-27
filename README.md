# CoreOS 自定义项目

这个项目用于创建自定义的Fedora CoreOS镜像，添加额外的软件包并移除不需要的组件。

## 项目结构

```
.
├── configs/                   # 配置文件目录
│   ├── overrides.yaml         # rpm-ostree覆盖配置
│   └── sing-box.repo          # sing-box软件源配置
├── scripts/                   # 脚本目录
│   └── build.sh               # 构建脚本
├── Dockerfile                 # 构建镜像的Dockerfile
└── README.md                  # 项目说明文档
```

## 配置说明

### overrides.yaml

此文件定义了要移除的包和要添加的包：

- **移除的包**：moby-engine, moby-filesystem, containerd, docker-cli, zincati, nano, nano-default-editor
- **添加的包**：container-selinux, pciutils, usbutils, vim-default-editor, screen, tree, mesa-vulkan-drivers, vulkan-loader, vulkan-tools, sing-box

### sing-box.repo

为sing-box添加的yum仓库配置。

## 使用方法

### 构建镜像

```bash
./scripts/build.sh [TAG]
```

默认标签为 `custom-coreos:latest`。

### 运行容器

```bash
docker run -it custom-coreos:latest
```

## 自定义说明

如需修改要添加或移除的软件包，请编辑 `configs/overrides.yaml` 文件。 