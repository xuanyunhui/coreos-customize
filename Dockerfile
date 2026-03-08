FROM quay.io/fedora/fedora-coreos:44.20260301.92.1

# 添加配置文件
ADD configs/overrides.yaml /etc/rpm-ostree/origin.d/overrides.yaml
ADD configs/repos/sing-box.repo /etc/yum.repos.d/sing-box.repo
ADD configs/repos/yunhui-imagemagick-opencl.repo /etc/yum.repos.d/yunhui-imagemagick-opencl.repo
ADD configs/dtbo/patch-dtb-wifi.py /tmp/patch-dtb-wifi.py

# 执行系统重建
RUN cat /etc/os-release \
    && rpm-ostree --version \
    && mkdir -p /var/lib/alternatives \
    && dnf5 download \
         --destdir=/tmp/rpm-overrides \
         --arch=aarch64 --arch=noarch \
         libgcc libstdc++ dbus-libs \
    && rpm-ostree override replace /tmp/rpm-overrides/*.rpm \
    && rm -rf /var/cache/libdnf5 \
    && rpm-ostree ex rebuild \
    && rm -rf /tmp/rpm-overrides \
    && rm -rf /var/lib \
    && rpm-ostree cleanup -m \
    && systemctl preset-all \
    && FIRMWARE_BASE="https://raw.githubusercontent.com/orangepi-xunlong/firmware/refs/heads/master" \
    && mkdir -p /usr/lib/firmware/brcm \
    && curl -fL --max-time 60 "${FIRMWARE_BASE}/SYN43711A0.hcd" \
         -o /usr/lib/firmware/brcm/SYN43711A0.hcd \
    && ln -sf SYN43711A0.hcd /usr/lib/firmware/brcm/BCM.xunlong,orangepi-5-max.hcd \
    && curl -fL --max-time 60 "${FIRMWARE_BASE}/fw_syn43711a0_sdio.bin" \
         -o /usr/lib/firmware/brcm/brcmfmac43711-sdio.bin \
    && curl -fL --max-time 60 "${FIRMWARE_BASE}/clm_syn43711a0.blob" \
         -o /usr/lib/firmware/brcm/brcmfmac43711-sdio.clm_blob \
    && curl -fL --max-time 60 "${FIRMWARE_BASE}/nvram_ap6611s.txt" \
         -o "/usr/lib/firmware/brcm/brcmfmac43711-sdio.xunlong,orangepi-5-max.txt" \
    && for kdir in /usr/lib/modules/*/; do \
         dtb="${kdir}dtb/rockchip/rk3588-orangepi-5-max.dtb"; \
         if [ -f "${dtb}" ]; then \
           python3 /tmp/patch-dtb-wifi.py "${dtb}" "${dtb}.patched" \
             && mv "${dtb}.patched" "${dtb}" \
             && echo "Applied Wi-Fi patch to ${dtb}" \
             || exit 1; \
         fi; \
       done \
    && rm /tmp/patch-dtb-wifi.py \
    # Mali GPU OpenCL 驱动 (RK3588 / Mali-G610)
    && MALI_BASE="https://github.com/JeffyCN/mirrors/raw/libmali" \
    && curl -fL --max-time 120 \
         "${MALI_BASE}/lib/aarch64-linux-gnu/libmali-valhall-g610-g6p0-x11-wayland-gbm.so" \
         -o /usr/lib64/libmali-valhall-g610-g6p0-x11-wayland-gbm.so \
    && chmod 755 /usr/lib64/libmali-valhall-g610-g6p0-x11-wayland-gbm.so \
    && curl -fL --max-time 60 \
         "${MALI_BASE}/firmware/g610/mali_csffw.bin" \
         -o /usr/lib/firmware/mali_csffw.bin \
    && echo "/usr/lib64/libmali-valhall-g610-g6p0-x11-wayland-gbm.so" \
         > /etc/OpenCL/vendors/mali.icd \
    && ldconfig \
    && ostree container commit 
