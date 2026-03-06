# Orange Pi 5 Max Wi-Fi 启用设计文档

**日期**：2026-03-06
**目标**：在 Fedora CoreOS 主线内核 6.19 上为 Orange Pi 5 Max（RK3588）启用 Wi-Fi（AP6611S / SYN43711），同时修复蓝牙固件缺失问题。

---

## 背景

### 硬件

- **板卡**：Orange Pi 5 Max（RK3588 SoC）
- **Wi-Fi / 蓝牙芯片**：AP6611S（Ampak 模块，内部为 Synaptics SYN43711）
- **Wi-Fi 接口**：SDIO（mmc2/sdio 控制器）
- **蓝牙接口**：UART7

### 现状诊断

dmesg 分析：

```
[15.356687] Bluetooth: hci0: BCM: firmware Patch file not found, tried:
[15.357298] Bluetooth: hci0: BCM: 'brcm/BCM.xunlong,orangepi-5-max.hcd'
[15.357882] Bluetooth: hci0: BCM: 'brcm/BCM.hcd'
```

| 问题层面 | 状态 | 说明 |
|---|---|---|
| 蓝牙 UART7 DTS 节点 | ✓ 已在内核中 | 蓝牙设备被识别，DT 节点存在 |
| 蓝牙固件 | ✗ 缺失 | `SYN43711A0.hcd` 未在 linux-firmware 中 |
| Wi-Fi SDIO DTS 节点 | ✗ 缺失 | dmesg 无任何 brcmfmac 输出，SDIO 节点未进入上游 |
| Wi-Fi 固件 | ✗ 缺失 | brcmfmac43711 固件不在 linux-firmware 中 |

### 上游状态参考

- DTS 来源：[jimmyhon/linux PR #3](https://github.com/jimmyhon/linux/pull/3)（蓝牙）、[PR #4](https://github.com/jimmyhon/linux/pull/4)（Wi-Fi，draft）
- 固件来源：[orangepi-xunlong/firmware](https://github.com/orangepi-xunlong/firmware)
- Wi-Fi 主线驱动状态：SYN43711 chip ID 补丁（brcmfmac）为实验性，Layer 3 网络可能存在问题

---

## 方案选择

选定**方案一：固件供应 + DTB Overlay**（构建时修补）。

理由：
- 蓝牙立即可用（固件简单）
- DTB 修补方法与项目已有 NPU DTB symlink 机制一致
- `dtc` 和 `fdtoverlay` 工具已在项目中可用
- 即使 Wi-Fi Layer 3 存在上游未解问题，基础设施就绪后随内核更新可自动受益

---

## 架构设计

### 总览

```
构建时 (Dockerfile)
├── 1. 固件下载
│   └── curl from orangepi-xunlong/firmware → /usr/lib/firmware/brcm/
├── 2. DTS Overlay 编译
│   └── configs/dtbo/rk3588-orangepi-5-max-wifi.dts
│       → dtc -@ -I dts -O dtb → /tmp/wifi.dtbo
└── 3. DTB 修补（每个内核版本）
    └── fdtoverlay -i rk3588-orangepi-5-max.dtb -o ... wifi.dtbo

运行时
└── GRUB 通过已有 symlink 加载修补后的 DTB
    └── brcmfmac 探测 &sdio 节点 → 加载固件 → wlan0
```

---

## 详细设计

### 1. 固件供应

**来源**：`https://raw.githubusercontent.com/orangepi-xunlong/firmware/refs/heads/master/`

| 下载文件 | 目标路径 | 作用 |
|---|---|---|
| `SYN43711A0.hcd` | `/usr/lib/firmware/brcm/BCM.xunlong,orangepi-5-max.hcd`（符号链接） | 蓝牙固件 |
| `fw_syn43711a0_sdio.bin` | `/usr/lib/firmware/brcm/brcmfmac43711-sdio.bin` | Wi-Fi 驱动固件 |
| `clm_syn43711a0.blob` | `/usr/lib/firmware/brcm/brcmfmac43711-sdio.clm_blob` | Wi-Fi CLM 数据 |
| `nvram_ap6611s.txt` | `/usr/lib/firmware/brcm/brcmfmac43711-sdio.xunlong,orangepi-5-max.txt` | Wi-Fi 板级 NVRAM |

文件命名遵循 brcmfmac 标准：`brcmfmac<chip>-sdio.<dt-compatible>.txt`，DT compatible string `xunlong,orangepi-5-max` 已由 dmesg 蓝牙输出确认。

### 2. DTS Overlay

新建文件：`configs/dtbo/rk3588-orangepi-5-max-wifi.dts`

新增节点：

| 节点 | 类型 | 作用 |
|---|---|---|
| `sdio_pwrseq` | `mmc-pwrseq-simple` | 控制 WL_REG_ON（GPIO2 PC5），Wi-Fi 上电时序 |
| `pinctrl > wifi` | pinctrl | `wifi_enable_h`（GPIO2 PC5）、`wifi_host_wake_irq`（GPIO0 PB0）|
| `&sdio` 扩展 | mmc controller | 启用 SDIO 控制器，绑定 brcmf，最大频率 150MHz，SDR104 |
| `brcmf: wifi@1` | `brcm,bcm4329-fmac` | Wi-Fi 设备节点 |

关键引用：
- `sdio_pwrseq` 引用基础 DTB 中的 `&hym8563`（RTC，提供外部时钟）
- `&sdio` 引用基础 DTB 中的 `&sdiom0_pins`、`&vcc_3v3_s3`、`&vcc_1v8_s3`
- 不处理旧的 `rfkill-pcie-wlan` 节点（GPIO0 PC4 在 OPi 5 Max 上悬空，无影响）

### 3. Dockerfile 变更

**步骤 A：固件下载**（在 `rpm-ostree ex rebuild` 之后）

```dockerfile
RUN FIRMWARE_BASE="https://raw.githubusercontent.com/orangepi-xunlong/firmware/refs/heads/master" \
    && mkdir -p /usr/lib/firmware/brcm \
    && curl -fL "${FIRMWARE_BASE}/SYN43711A0.hcd" \
         -o /usr/lib/firmware/brcm/SYN43711A0.hcd \
    && ln -sf SYN43711A0.hcd /usr/lib/firmware/brcm/BCM.xunlong,orangepi-5-max.hcd \
    && curl -fL "${FIRMWARE_BASE}/fw_syn43711a0_sdio.bin" \
         -o /usr/lib/firmware/brcm/brcmfmac43711-sdio.bin \
    && curl -fL "${FIRMWARE_BASE}/clm_syn43711a0.blob" \
         -o /usr/lib/firmware/brcm/brcmfmac43711-sdio.clm_blob \
    && curl -fL "${FIRMWARE_BASE}/nvram_ap6611s.txt" \
         -o "/usr/lib/firmware/brcm/brcmfmac43711-sdio.xunlong,orangepi-5-max.txt"
```

**步骤 B：DTB Overlay 编译与应用**（在 DTB symlink 循环之后）

```dockerfile
ADD configs/dtbo/rk3588-orangepi-5-max-wifi.dts /tmp/rk3588-orangepi-5-max-wifi.dts

RUN dtc -@ -I dts -O dtb -o /tmp/rk3588-orangepi-5-max-wifi.dtbo \
        /tmp/rk3588-orangepi-5-max-wifi.dts \
    && for kdir in /usr/lib/modules/*/; do \
         dtb="${kdir}dtb/rockchip/rk3588-orangepi-5-max.dtb"; \
         if [ -f "${dtb}" ]; then \
           fdtoverlay -i "${dtb}" -o "${dtb}" \
                      /tmp/rk3588-orangepi-5-max-wifi.dtbo && \
             echo "Applied Wi-Fi overlay to ${dtb}"; \
         fi; \
       done \
    && rm /tmp/rk3588-orangepi-5-max-wifi.dts \
          /tmp/rk3588-orangepi-5-max-wifi.dtbo
```

---

## 文件变更摘要

| 操作 | 文件 |
|---|---|
| 新增 | `configs/dtbo/rk3588-orangepi-5-max-wifi.dts` |
| 修改 | `Dockerfile` |
| 不变 | `configs/overrides.yaml`、`configs/repos/`、`scripts/` |

---

## 风险与注意事项

1. **brcmfmac SYN43711 chip ID**：若 Fedora CoreOS 内核 6.19 的 brcmfmac 模块未含 SYN43711 chip ID，Wi-Fi 设备不会被探测。蓝牙不受影响。
2. **Wi-Fi Layer 3**：即使接口出现，上游实验性补丁存在 IP 层无法工作的问题（jimmyhon PR #4 确认）。
3. **Fedora CoreOS DTB __symbols__**：若 DTB 不含 `__symbols__` 节，`fdtoverlay` 会失败。需在构建时先重建带符号的 DTB，构建步骤需相应调整。
4. **固件来源**：固件来自 Orange Pi 官方 GitHub，非 linux-firmware 上游，需在网络可访问的环境下构建。
