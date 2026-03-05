FROM quay.io/fedora/fedora-coreos:44.20260301.92.1

# 添加配置文件
ADD configs/overrides.yaml /etc/rpm-ostree/origin.d/overrides.yaml
ADD configs/repos/sing-box.repo /etc/yum.repos.d/sing-box.repo

# 执行系统重建
RUN cat /etc/os-release \
    && rpm-ostree --version \
    && mkdir -p /var/lib/alternatives \
    && rpm-ostree ex rebuild \
    && rm -rf /var/lib \
    && rpm-ostree cleanup -m \
    && systemctl preset-all \
    && for kdir in /usr/lib/modules/*/; do \
         dtbdir="${kdir}dtb"; \
         if [ -f "${dtbdir}/rockchip/rk3588-orangepi-5-max.dtb" ]; then \
           ln -sf rockchip/rk3588-orangepi-5-max.dtb "${dtbdir}/xunlong,orangepi-5-max--rockchip,rk3588.dtb"; \
         fi; \
         if [ -f "${dtbdir}/rockchip/rk3588-orangepi-5-plus.dtb" ]; then \
           ln -sf rockchip/rk3588-orangepi-5-plus.dtb "${dtbdir}/xunlong,orangepi-5-plus--rockchip,rk3588.dtb"; \
         fi; \
         if [ -f "${dtbdir}/rockchip/rk3588-orangepi-5-ultra.dtb" ]; then \
           ln -sf rockchip/rk3588-orangepi-5-ultra.dtb "${dtbdir}/xunlong,orangepi-5-ultra--rockchip,rk3588.dtb"; \
         fi; \
       done \
    && ostree container commit 
