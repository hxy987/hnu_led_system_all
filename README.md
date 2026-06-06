# hnu_led_system_all

湖南大学 CSEE EC C301 - 综合选题3：无线智能 RGB LED 控制系统（V2）

## 项目简介

本项目实现了一套基于 **Flutter 手机 App + FPGA 硬件** 的无线蓝牙智能 RGB LED 控制系统。

- **手机端**：Flutter 应用，通过 BLE 蓝牙发送 5 字节自定义协议指令
- **FPGA 端**：Verilog 硬件设计，通过 UART 接收指令并驱动 WS2812 LED 灯带

## 项目结构

```
hnu_led_system_all/
├── hnu_led_controller/        # Flutter 手机 App
│   └── lib/
│       ├── main.dart                  # UI 界面（BLE 扫描/连接、3 模式控制面板、波浪预览）
│       └── bluetooth_controller.dart  # BLE 蓝牙通信控制器（Provider 状态管理）
├── experiements5/              # Intel Quartus Prime FPGA 工程
│   ├── top_project.v           # 顶层模块（6 模块流水线集成）
│   ├── uart_rx.v               # UART 接收器（115200 baud）
│   ├── uart_tx.v               # UART 发送器
│   ├── tx_rx_arbiter.v         # 收发仲裁器（Rx 绝对优先）
│   ├── cmd_parser.v            # 5 字节协议帧解析状态机
│   ├── effect_generator.v      # 多模式 LED 效果发生器（静态/流水/呼吸）
│   ├── my_ws2812.v             # WS2812 单线驱动（8-LED GRB）
│   ├── pro1.v                  # 早期独立演示顶层（参考用）
│   └── experiements5.qpf       # Quartus 工程文件
├── problem.txt                 # 最新需求文档（V2 重构规格）
└── CLAUDE.md                   # 项目开发指南
```

## 通信协议（V2 — 5 字节帧）

| 字节 | 字段 | 说明 |
|------|------|------|
| 0 | `0x5A` | 帧头（魔术字节） |
| 1 | Mode | `0x01` 独立灯珠 / `0x02` 流水灯 / `0x03` 呼吸灯 |
| 2 | Color | `0x01` 红 / `0x02` 绿 / `0x03` 蓝 |
| 3 | Brightness | 全局 PWM 亮度 0~255 |
| 4 | Speed/Param | Mode 1: LED 掩码 / Mode 2&3: 速度参数 1~15 |

FPGA 按键反馈：`0xC3`（通过 BLE NOTIFY 上报至 App）

### LED 物理位映射

UI 按钮 1~8 → FPGA `led_data_in10` 比特位：

| UI 按钮 | FPGA 位 | 网格位置 |
|---------|---------|----------|
| 1 | bit4 | Row 1, Col 4（外右） |
| 2 | bit5 | Row 1, Col 3（内右） |
| 3 | bit6 | Row 1, Col 2（内左） |
| 4 | bit7 | Row 1, Col 1（外左） |
| 5 | bit3 | Row 2, Col 1（外左） |
| 6 | bit2 | Row 2, Col 2（内左） |
| 7 | bit1 | Row 2, Col 3（内右） |
| 8 | bit0 | Row 2, Col 4（外右） |

2×4 网格布局（俯视）：
```
Row 1: [Btn4] [Btn3] [Btn2] [Btn1]   ← 外左 → 外右
Row 2: [Btn5] [Btn6] [Btn7] [Btn8]   ← 外左 → 外右
```

## 硬件平台

- **FPGA**：Cyclone IV E EP4CE15F17C8
- **主时钟**：50MHz（PIN_E1）
- **LED**：WS2812 灯带（8 灯串联）
- **蓝牙**：BLE 串口透传模块（PMOD 接口，UART 115200 baud）
- **开发工具**：Intel Quartus Prime 24.1std.0 Lite Edition

### 引脚分配

| 引脚 | 功能 |
|------|------|
| PIN_E1 | 50MHz 时钟 |
| PIN_L2 | 硬件复位（低有效） |
| PIN_B11 | UART RX（蓝牙 → FPGA） |
| PIN_D6 | UART TX（FPGA → 蓝牙） |
| PIN_T2 | WS2812 LED 数据输出 |
| PIN_K1 | 按键反馈（触发 0xC3 上报） |

## 功能特性

### 模式一：独立灯珠控制（Mode `0x01`）
- 8 个 LED 独立开关（2×4 网格 UI）
- 全局颜色切换（红/绿/蓝），**保留当前 LED 开关掩码**
- 全开 / 全关快捷按钮
- 全局亮度滑块实时调节（0~255）

### 模式二：自动流水灯特效（Mode `0x02`）
- FPGA 硬件驱动的单热点流水扫描
- 滑块调节流水速度（1=极速，15=最缓）
- 全局颜色和亮度可叠加控制

### 模式三：中心对称波浪呼吸灯（Mode `0x03`）
- **App 驱动**的中心对称波浪算法：内列（Col 2,3）与外列（Col 1,4）以 cos/sin 180° 反相呼吸
- 视觉波浪预览 UI（4 列实时强度指示器）
- 节拍调节滑块（1=极速扩散，15=最缓呼吸）
- 全局颜色可切换（波浪帧自动读取）
- 呼吸模式下亮度滑块锁定

### 系统功能
- BLE 蓝牙扫描（RSSI 信号强度自动排序置顶）
- 双向通信：App 下发指令 + FPGA 按键反馈上报（0xC3）
- 帧同步看门狗自动恢复
- 暗黑科技风 UI（AnimatedContainer 动态视觉效果）

## FPGA 架构（数据流水线）

```
UART RX ──────→ UART TX
    ↓               ↑
tx_rx_arbiter (Rx 绝对优先级仲裁)
    ↓
cmd_parser (5 字节帧 FSM：IDLE → MAGIC → COLOR → BRIGHTNESS → PARAM)
    ↓
effect_generator (多模式效果计算)
    ↓
my_ws2812 (WS2812 单线时序驱动)
    ↓
led_out → WS2812 LED 灯带
```

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
4. 上电后打开 Flutter App，扫描并连接蓝牙设备
5. 选择模式并实时控制 LED 灯带

## 依赖

### Flutter
- `flutter_blue_plus: ^1.34.0` — BLE 蓝牙通信
- `provider: ^6.1.2` — 状态管理
- `flutter_lints: ^6.0.0` — 代码规范

### FPGA
- Intel Quartus Prime 24.1std.0 Lite Edition（或更新版本）
- USB Blaster 下载器
