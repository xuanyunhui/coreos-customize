FROM quay.io/fedora/fedora-coreos:stable

# 定义构建参数
ARG USE_PRIVILEGED=false

# 添加配置文件
ADD configs/overrides.yaml /etc/rpm-ostree/origin.d/overrides.yaml
ADD configs/sing-box.repo /etc/yum.repos.d/sing-box.repo

# 执行系统重建
RUN cat /etc/os-release \
    && rpm-ostree --version \
    && mkdir -p /var/lib/alternatives \
    && if [ "$USE_PRIVILEGED" = "true" ]; then \
         rpm-ostree ex rebuild --privileged; \
       else \
         rpm-ostree ex rebuild; \
       fi \
    && rm -rf /var/lib \
    && rpm-ostree cleanup -m \
    && systemctl preset-all \
    && ostree container commit 