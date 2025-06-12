FROM quay.io/fedora/fedora-coreos:stable

# 添加配置文件
ADD configs/overrides.yaml /etc/rpm-ostree/origin.d/overrides.yaml
ADD configs/repos/sing-box.repo /etc/yum.repos.d/sing-box.repo
ADD configs/repos/yunhui-kernel-nanopi-r5-fedora-42.repo /etc/yum.repos.d/yunhui-kernel-nanopi-r5-fedora-42.repo

# 执行系统重建
RUN cat /etc/os-release \
    && rpm-ostree --version \
    && mkdir -p /var/lib/alternatives \
    && rpm-ostree ex rebuild \
    && rm -rf /var/lib \
    && rpm-ostree cleanup -m \
    && systemctl preset-all \
    && ostree container commit 
