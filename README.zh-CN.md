# BusLens Mac (`v0.2.0`)

**[English](README.md)** | **简体中文**

**原生 macOS 雷雳 (Thunderbolt)、USB4 与 USB-C 协商速率、线材降速瓶颈及 USB-C PD 供电功率分析仪（支持应用内 `中文 / EN` 实时双语切换）。**

![BusLens Mac 主界面](docs/screenshot-main-zh.png)

每一根 USB-C 线材从外观上看起来几乎完全相同——无论它实际协商出 **80 Gb/s 雷雳 5** 隧道、**40 Gb/s USB4 / 雷雳 4** 满速通道、**10 Gb/s USB 3.2** 降级速率，还是将 3,200 MB/s 的外置 NVMe 固态硬盘盒死死卡在 38 MB/s 的 **480 Mb/s USB 2.0 充电线陷阱**。

**BusLens Mac** (`v0.2.0`) 与 [CrystalDiskInfoMac](https://github.com/zxu756/CrystalDiskInfoMac)（SMART 磁盘健康度）及 [CrystalDiskMarkMac](https://github.com/zxu756/CrystalDiskMarkMac)（磁盘读写基准测试）共同组成原生 Apple Silicon 存储与硬件链路诊断三件套。

## 核心亮点

- **机身物理端口拓扑矩阵** — 直观映射每一路 Apple Silicon 雷雳 / USB4 主控总线与 USB 3.1 主机控制器，实时对比当前协商速率与物理端口带宽上限。
- **线材降速与扩展坞瓶颈精准诊断** — 自动揪出因误用“仅充电 USB-C 线”受困于 `480 Mb/s`、或经由扩展坞/10G 线材降速至 `10 Gb/s` 的外置 NVMe 硬盘盒与移动固态硬盘；同时智能识别机械键盘、无线接收器等低延迟 HID 外设在 `480 Mb/s` 独立通道下的正常工作状态，绝不误报。
- **应用内 `中文 / EN` 实时切换 (`v0.2.0`)** — 主窗口顶部与菜单栏弹窗均内置工业阳极氧化铝风格的 `中文 | EN` 分段切换胶囊，支持快捷键 `⇧⌘L` 与命令行 `--lang zh|en`；当 macOS 系统首选语言为中文时自动默认启用简体中文界面。
- **跨代兼容 macOS 14–27+ 硬件数据结构** — 同时兼容 `SPUSBDataType`（macOS 14–15）与新版 `SPUSBHostDataType`（`USBDeviceKeyLinkSpeed`，macOS 26+），结合 `SPThunderboltDataType` 与 `SPPowerDataType`，**全程零 root 提权弹窗**。
- **隐私优先的硬件标识符脱敏** — 在解析阶段自动剥离外设序列号以及雷雳域 / 交换芯片 UUID。

<p align="center">
  <img src="docs/screenshot-menubar-zh.png" width="380" alt="BusLens Mac 菜单栏弹窗" />
</p>

## 安装方式 (`v0.2.0`)

### Homebrew Cask 一键安装

```bash
brew install --cask zxu756/tap/buslens-mac
```

### 从源码构建（macOS 14.0+，Apple Silicon）

```bash
git clone https://github.com/zxu756/BusLensMac.git
cd BusLensMac
swift test --no-parallel
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh
open build/BusLensMac.app
```

## 命令行与语言参数

```bash
# 终端打印完整物理端口与外设协商速率拓扑
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology

# 仅检查被线材或集线器限速的异常设备（适用于脚本巡检）
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli bottlenecks

# 显式指定以简体中文或英文启动图形界面
build/BusLensMac.app/Contents/MacOS/BusLensMac --lang zh
build/BusLensMac.app/Contents/MacOS/BusLensMac --lang en

# 导出 2x Retina 高清宣传截图（英文 + 简体中文）
build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots docs --lang en
build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots docs --lang zh
```

## 架构与技术规范

详见 [docs/SPEC.md](docs/SPEC.md)。

## 开源协议

MIT
