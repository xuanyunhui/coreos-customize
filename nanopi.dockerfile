FROM quay.io/fedora/fedora-coreos:stable

ADD overrides.yaml /etc/rpm-ostree/origin.d/overrides.yaml
ADD sing-box.repo /etc/yum.repos.d/sing-box.repo
RUN cat /etc/os-release \
    && rpm-ostree --version \
    && mkdir -p /var/lib/alternatives \
    && rpm-ostree ex rebuild \
    && rm -rf /var/lib \
    && rpm-ostree cleanup -m \
    && systemctl preset-all \
    && ostree container commitcd