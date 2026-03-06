# Orange Pi 5 Max Wi-Fi 启用实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 Fedora CoreOS 主线内核 6.19 镜像中，通过 DTB Overlay 和固件供应，为 Orange Pi 5 Max 启用 AP6611S Wi-Fi，并修复蓝牙固件缺失。

**Architecture:** 构建时在 Dockerfile 中执行两步：（1）从 orangepi-xunlong/firmware 下载蓝牙和 Wi-Fi 固件放入 `/usr/lib/firmware/brcm/`；（2）编译 DTS Overlay 并用 `fdtoverlay` 修补每个内核版本的 rk3588-orangepi-5-max.dtb，注入 SDIO Wi-Fi 节点。GRUB 通过现有 DTB symlink 自动加载修补后的 DTB。

**Tech Stack:** Dockerfile (rpm-ostree/CoreOS)、dtc（设备树编译器）、fdtoverlay（设备树 overlay 合并工具）、curl（固件下载）

---

### Task 1：创建 DTS Overlay 源文件

**Files:**
- Create: `configs/dtbo/rk3588-orangepi-5-max-wifi.dts`

**Step 1: 创建目录**

```bash
mkdir -p configs/dtbo
```

**Step 2: 创建 DTS Overlay 文件**

内容基于 jimmyhon 已验证的补丁（[PR #4](https://github.com/jimmyhon/linux/pull/4) commit 8eeedc8）。
使用数字常量避免依赖 dt-bindings 头文件：

- GPIO_ACTIVE_LOW = 1
- GPIO_ACTIVE_HIGH = 0
- IRQ_TYPE_LEVEL_HIGH = 4
- RK_PB0 = 8, RK_PC5 = 21, RK_FUNC_GPIO = 0

```dts
/dts-v1/;
/plugin/;

/ {
	compatible = "xunlong,orangepi-5-max", "rockchip,rk3588";

	fragment@0 {
		target = <&pinctrl>;
		__overlay__ {
			wifi {
				wifi_enable_h: wifi-enable-h {
					rockchip,pins = <2 21 0 &pcfg_pull_up>;
				};

				wifi_host_wake_irq: wifi-host-wake-irq {
					rockchip,pins = <0 8 0 &pcfg_pull_down>;
				};
			};
		};
	};

	fragment@1 {
		target-path = "/";
		__overlay__ {
			sdio_pwrseq: sdio-pwrseq {
				compatible = "mmc-pwrseq-simple";
				clock-names = "ext_clock";
				clocks = <&hym8563>;
				pinctrl-0 = <&wifi_enable_h>;
				pinctrl-names = "default";
				post-power-on-delay-ms = <200>;
				power-off-delay-us = <5000000>;
				reset-gpios = <&gpio2 21 1>;
			};
		};
	};

	fragment@2 {
		target = <&sdio>;
		__overlay__ {
			#address-cells = <1>;
			bus-width = <4>;
			cap-sd-highspeed;
			cap-sdio-irq;
			disable-wp;
			keep-power-in-suspend;
			max-frequency = <150000000>;
			mmc-pwrseq = <&sdio_pwrseq>;
			non-removable;
			no-mmc;
			no-sd;
			pinctrl-names = "default";
			pinctrl-0 = <&sdiom0_pins>;
			sd-uhs-sdr104;
			#size-cells = <0>;
			vmmc-supply = <&vcc_3v3_s3>;
			vqmmc-supply = <&vcc_1v8_s3>;
			status = "okay";

			brcmf: wifi@1 {
				compatible = "brcm,bcm4329-fmac";
				reg = <1>;
				interrupt-parent = <&gpio0>;
				interrupts = <8 4>;
				interrupt-names = "host-wake";
				pinctrl-0 = <&wifi_host_wake_irq>;
				pinctrl-names = "default";
			};
		};
	};
};
```

**Step 3: 验证文件可被 dtc 解析（本地验证，如有 dtc 可用）**

```bash
# 在本地测试编译（可选，构建时会再次验证）
dtc -@ -I dts -O dtb -o /tmp/test.dtbo configs/dtbo/rk3588-orangepi-5-max-wifi.dts
echo "Exit code: $?"
```

期望：exit code 0，无错误。若提示警告（如 missing labels），可忽略。

**Step 4: Commit**

```bash
git add configs/dtbo/rk3588-orangepi-5-max-wifi.dts
git commit -m "Add DTS overlay for AP6611S Wi-Fi on Orange Pi 5 Max"
```

---

### Task 2：修改 Dockerfile —— 固件下载

**Files:**
- Modify: `Dockerfile`

当前 Dockerfile 最后一行是 `&& ostree container commit`，在此之前是 `done \`。

**Step 1: 读取当前 Dockerfile**

读取 `Dockerfile` 确认结构，找到 `ostree container commit` 所在的 RUN 块结尾。

**Step 2: 在 `ostree container commit` 之前插入固件下载步骤**

在 `done \` 行和 `&& ostree container commit` 之间追加：

```dockerfile
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
```

**Step 3: Commit**

```bash
git add Dockerfile
git commit -m "Add AP6611S Bluetooth and Wi-Fi firmware provisioning"
```

---

### Task 3：修改 Dockerfile —— DTB Overlay 编译与应用

**Files:**
- Modify: `Dockerfile`（在 Task 2 基础上继续）

**Step 1: 在固件下载步骤的 ADD 之前（RUN 块之外）添加 ADD 指令**

在 `Dockerfile` 开头的 `ADD configs/overrides.yaml` 附近追加：

```dockerfile
ADD configs/dtbo/rk3588-orangepi-5-max-wifi.dts /tmp/rk3588-orangepi-5-max-wifi.dts
```

**Step 2: 在固件下载步骤之后、`ostree container commit` 之前添加 DTB 修补步骤**

```dockerfile
    && dtc -@ -I dts -O dtb -o /tmp/rk3588-orangepi-5-max-wifi.dtbo \
         /tmp/rk3588-orangepi-5-max-wifi.dts \
    && for kdir in /usr/lib/modules/*/; do \
         dtb="${kdir}dtb/rockchip/rk3588-orangepi-5-max.dtb"; \
         if [ -f "${dtb}" ]; then \
           fdtoverlay -i "${dtb}" -o "${dtb}" \
                      /tmp/rk3588-orangepi-5-max-wifi.dtbo \
             && echo "Applied Wi-Fi DTB overlay to ${dtb}"; \
         fi; \
       done \
    && rm /tmp/rk3588-orangepi-5-max-wifi.dts \
          /tmp/rk3588-orangepi-5-max-wifi.dtbo \
```

**重要提示**：若 `fdtoverlay` 报错 `FDT_ERR_NOTFOUND`（DTB 缺少 `__symbols__`），需在此步骤前先重建带符号的 DTB：

```dockerfile
    && for kdir in /usr/lib/modules/*/; do \
         dtb="${kdir}dtb/rockchip/rk3588-orangepi-5-max.dtb"; \
         if [ -f "${dtb}" ]; then \
           dtc -I dtb -O dts "${dtb}" | dtc -@ -I dts -O dtb -o "${dtb}.sym" \
             && mv "${dtb}.sym" "${dtb}"; \
         fi; \
       done \
```

**Step 3: Commit**

```bash
git add Dockerfile
git commit -m "Apply AP6611S Wi-Fi DTB overlay at image build time"
```

---

### Task 4：本地构建测试

**Files:**
- 无新文件，验证步骤

**Step 1: 触发本地构建**

```bash
cd /var/home/core/Developer/coreos-customize
bash scripts/build.sh
```

观察输出，重点关注：
- `rpm-ostree ex rebuild` 是否成功
- `Applied Wi-Fi DTB overlay to ...` 是否出现
- 固件下载是否成功（无 curl 错误）

**Step 2: 若 fdtoverlay 失败，检查 DTB 是否含 __symbols__**

```bash
# 在构建容器内或本地：
fdtdump /usr/lib/modules/$(uname -r)/dtb/rockchip/rk3588-orangepi-5-max.dtb | grep __symbols__
```

若无输出，启用 DTB 重建步骤（见 Task 3 重要提示）。

**Step 3: 镜像部署后验证（在 Orange Pi 5 Max 上执行）**

```bash
# 检查蓝牙固件是否加载
sudo dmesg | grep -i "BCM\|SYN43711"
# 期望：无 "firmware Patch file not found" 错误

# 检查 Wi-Fi 接口
ip link show
# 期望：出现 wlan0

# 检查 brcmfmac 加载
sudo dmesg | grep -i brcmfmac
# 期望：probe 成功信息
```

**Step 4: 最终 Commit（若有调整）**

```bash
git add -A
git commit -m "Fix fdtoverlay DTB symbols handling for Wi-Fi overlay"
```

---

## 已知限制

1. **brcmfmac SYN43711 chip ID**：若 Fedora CoreOS 内核 6.19 的 brcmfmac 未包含 SYN43711 chip ID，`wlan0` 不会出现，但构建不会失败。蓝牙不受影响。
2. **Wi-Fi Layer 3**：即使 `wlan0` 出现，IP 层可能无法正常工作（上游实验性补丁问题）。
3. **网络依赖**：构建时需访问 GitHub raw content，CI 环境需确保网络可达。
