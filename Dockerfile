FROM quay.io/fedora/fedora-coreos:44.20260419.1.1

# 添加配置文件
ADD configs/overrides.yaml /etc/rpm-ostree/origin.d/overrides.yaml
ADD configs/repos/sing-box.repo /etc/yum.repos.d/sing-box.repo

ADD configs/repos/gh-cli.repo /etc/yum.repos.d/gh-cli.repo

# 执行系统重建
RUN cat /etc/os-release \
    && rpm-ostree --version \
    && mkdir -p /var/lib/alternatives \
    && rpm-ostree ex rebuild \
    && find /usr/lib/modules/*/dtb -mindepth 1 -maxdepth 1 -type d ! -name rockchip -exec rm -rf {} + \
    && rm -rf /var/lib \
    && rpm-ostree cleanup -m \
    && systemctl preset-all \
    && ostree container commit
