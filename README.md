# hnu_led_system_all

湖南大学 CSEE EC C301 - 综合选题3：无线智能 RGB LED 控制系统

## 项目简介

本项目实现了一套基于 **Flutter 手机 App + FPGA 硬件** 的无线蓝牙智能 RGB LED 控制系统。

- **手机端**：Flutter 应用，通过 BLE 蓝牙发送 3 字节自定义协议指令
- **FPGA 端**：Verilog 硬件设计，通过 UART 接收指令并驱动 WS2812 LED 灯带

## 项目结构

```
hnu_led_system_all/
├── hnu_led_controller/   # Flutter 手机 App
│   └── lib/
│       ├── main.dart                  # UI 界面（蓝牙扫描、连接、控制面板）
│       └── bluetooth_controller.dart  # BLE 蓝牙通信控制器
└── experiements5/         # Intel Quartus Prime FPGA 工程
    ├── top_project.v      # 顶层模块（6 模块流水线集成）
    ├── uart_rx.v          # UART 接收器（115200 baud）
    ├── uart_tx.v          # UART 发送器
    ├── tx_rx_arbiter.v    # 收发仲裁器（Rx 绝对优先）
    ├── cmd_parser.v       # 3 字节协议解析状态机
    ├── effect_generator.v # 多模式 LED 效果发生器
    ├── my_ws2812.v        # WS2812 单线驱动
    ├── pro1.v             # 早期独立演示顶层（参考用）
    └── experiements5.qpf  # Quartus 工程文件
```

## 通信协议

| 字节 | 字段 | 说明 |
|------|------|------|
| 0 | `0x5A` | 帧头（魔术字节） |
| 1 | Mode | `0x01` 静态单色 / `0x02` 流水灯 / `0x03` 数码管级联 |
| 2 | Param | 颜色掩码 / 速度阻尼 / 保留 |

FPGA 按键反馈：`0xC3`

## 硬件平台

- **FPGA**：Cyclone IV E EP4CE15F17C8
- **LED**：WS2812 灯带（8 灯）
- **蓝牙**：BLE 串口透传模块（PMOD 接口）
- **开发工具**：Intel Quartus Prime 24.1std.0 Lite Edition

## 功能特性

- 📱 Flutter App 蓝牙扫描与连接（RSSI 信号强度排序）
- 🎨 静态颜色控制（红/绿/全亮/全灭）
- 🌊 自动流水灯特效（速度可调）
- 🔢 数码管四进制级联组控
- 📡 FPGA 按键反馈上报（0xC3）
- 🛡️ 帧同步看门狗自动恢复

## 快速开始

### Flutter App

```bash
cd hnu_led_controller
flutter pub get
flutter run
```

### FPGA

1. 用 Intel Quartus Prime 打开 `experiements5/experiements5.qpf`
2. 编译设计（Processing → Compile Design）
3. 通过 USB Blaster 烧录 `output_files/experiements5.sof`
