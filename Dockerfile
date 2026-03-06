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
    && FIRMWARE_BASE="https://raw.githubusercontent.com/orangepi-xunlong/firmware/refs/heads/master" \
    && mkdir -p /usr/lib/firmware/brcm \
    && curl -fL "${FIRMWARE_BASE}/SYN43711A0.hcd" \
         -o /usr/lib/firmware/brcm/SYN43711A0.hcd \
    && ln -sf SYN43711A0.hcd /usr/lib/firmware/brcm/BCM.xunlong,orangepi-5-max.hcd \
    && curl -fL "${FIRMWARE_BASE}/fw_syn43711a0_sdio.bin" \
         -o /usr/lib/firmware/brcm/brcmfmac43711-sdio.bin \
    && curl -fL "${FIRMWARE_BASE}/clm_syn43711a0.blob" \
         -o /usr/lib/firmware/brcm/brcmfmac43711-sdio.clm_blob \
    && curl -fL "${FIRMWARE_BASE}/nvram_ap6611s.txt" \
         -o "/usr/lib/firmware/brcm/brcmfmac43711-sdio.xunlong,orangepi-5-max.txt" \
    && ostree container commit 
