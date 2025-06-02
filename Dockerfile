FROM quay.io/fedora/fedora-coreos:stable

# 添加配置文件
ADD configs/overrides.yaml /etc/rpm-ostree/origin.d/overrides.yaml
ADD configs/repos/rpmfusion-free.repo /etc/yum.repos.d/rpmfusion-free.repo
ADD configs/repos/rpmfusion-free-updates.repo /etc/yum.repos.d/rpmfusion-free-updates.repo
ADD configs/repos/rpmfusion-nonfree.repo /etc/yum.repos.d/rpmfusion-nonfree.repo
ADD configs/repos/rpmfusion-nonfree-updates.repo /etc/yum.repos.d/rpmfusion-nonfree-updates.repo
ADD configs/repos/sing-box.repo /etc/yum.repos.d/sing-box.repo

# 执行系统重建
RUN cat /etc/os-release \
    && rpm-ostree --version \
    && mkdir -p /var/lib/alternatives \
    && rpm-ostree ex rebuild \
    && rm -rf /var/lib \
    && rpm-ostree cleanup -m \
    && systemctl preset-all \
    && ostree container commit 
