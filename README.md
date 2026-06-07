# hnu_led_system_all

湖南大学 CSEE EC C301 - 综合选题3：无线智能 RGB LED 控制系统（V3）

## 项目简介

本项目实现了一套基于 **Flutter 手机 App + FPGA 硬件** 的无线蓝牙智能 RGB LED 控制系统。

- **手机端**：Flutter 应用，通过 BLE 蓝牙发送 5 字节自定义协议指令
- **FPGA 端**：Verilog 硬件设计，通过 UART 接收指令并驱动 WS2812 LED 灯带
- **V3 新特性**：Mode 3 Byte 3 高低 4-bit nibble 分拆，内/外群 LED 独立亮度控制，单帧无竞态

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
├── problem.txt                 # V3 nibble 分拆需求规格
└── CLAUDE.md                   # 项目开发指南
```

## 通信协议（V3 — 5 字节帧，nibble 分拆亮度）

| 字节 | 字段 | 说明 |
|------|------|------|
| 0 | `0x5A` | 帧头（魔术字节） |
| 1 | Mode | `0x01` 独立灯珠 / `0x02` 流水灯 / `0x03` 呼吸灯 |
| 2 | Color | `0x01` 红 / `0x02` 绿 / `0x03` 蓝 |
| 3 | Brightness | Mode 1&2: 全局 PWM 亮度 0~255（FPGA 取高 4-bit） |
|   |            | **Mode 3: `[7:4]`=内群亮度(0~15), `[3:0]`=外群亮度(0~15)** |
| 4 | Speed/Param | Mode 1: LED 掩码 / Mode 2: 流水速度 / Mode 3: 节拍速度 1~15 |

FPGA 按键反馈：`0xC3`（通过 BLE NOTIFY 上报至 App）

### Mode 3 nibble 分拆架构（V3 核心升级）

```
Flutter 单帧/拍                    FPGA my_ws2812 双亮度端口
┌──────────────────────┐      ┌──────────────────────────────┐
│ [0x5A,0x03,clr,br,sp]│ ───→ │ inner_brightness = br[7:4]  │
│ br[7:4] = inner 0~15 │      │ outer_brightness = br[3:0]  │
│ br[3:0] = outer 0~15 │      │                              │
│ sp = 节拍速度 1~15   │      │ LED 2,3,6,7 ← inner 亮度    │
└──────────────────────┘      │ LED 1,4,5,8 ← outer 亮度    │
                              └──────────────────────────────┘
```

**关键收益**：单帧同时携带内/外群亮度，彻底消除旧版双帧竞态导致的闪烁 bug。

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
- **App 驱动 + FPGA 双亮度端口**：内列（Col 2,3 / LED 2,3,6,7）与外列（Col 1,4 / LED 1,4,5,8）以 180° 反相呼吸
- **nibble 分拆**：Byte 3 高 4-bit 控制内群亮度，低 4-bit 控制外群亮度（各 0~15）
- **单帧无竞态**：每拍仅发一帧 Mode 0x03，FPGA my_ws2812 按 LED 分组自动应用对应亮度
- 视觉波浪预览 UI（4 列实时强度指示器，显示 0~15 实际 4-bit 值）
- 节拍调节滑块（1=极速扩散，15=最缓呼吸）
- 全局颜色可切换（波浪帧自动读取）
- 呼吸模式下亮度滑块锁定

### 系统功能
- BLE 蓝牙扫描（RSSI 信号强度自动排序置顶）
- 双向通信：App 下发指令 + FPGA 按键反馈上报（0xC3）
- 帧同步看门狗自动恢复
- 暗黑科技风 UI（AnimatedContainer 动态视觉效果）

## FPGA 架构（数据流水线，V3 双亮度端口）

```
UART RX ──────→ UART TX
    ↓               ↑
tx_rx_arbiter (Rx 绝对优先级仲裁)
    ↓
cmd_parser (5 字节帧 FSM：WAIT_HEADER → GET_MODE → GET_COLOR → GET_BRIGHT → GET_PARAM)
    ↓
effect_generator (多模式效果计算 → inner_brightness + outer_brightness 双输出)
    ↓
my_ws2812 (双亮度端口：内群/外群独立脉宽驱动)
    ↓
led_out → WS2812 LED 灯带
```

### Mode 0x03 nibble 解包路径

```
ctrl_brightness[7:0]
    ├── [7:4] → inner_brightness → my_ws2812 内群 (LED 2,3,6,7)
    └── [3:0] → outer_brightness → my_ws2812 外群 (LED 1,4,5,8)
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

## 变更日志

### V3.0 — nibble 分拆双亮度端口（当前版本）

**Bug 修复**：Mode 3 中心对称波浪呼吸灯内群（中间 4 颗 LED）闪烁问题。

**根因**：旧版每拍发送两帧 Mode 0x01（内群帧 + 外群帧），两帧到达 FPGA 存在 ~435μs 时间差，后帧覆盖前帧的 `led_data_in10` 掩码，导致内群仅在帧间瞬间可见（<1% 占空比），表现为持续闪烁。

**修改**：

| 文件 | 变更 |
|------|------|
| `my_ws2812.v` | `led_brightness` 单端口 → `inner_brightness` + `outer_brightness` 双端口；Mode 0 按 LED 分组应用独立亮度 |
| `effect_generator.v` | 输出双亮度；Mode 0x03 解包 `ctrl_brightness[7:4]`→inner, `[3:0]`→outer；`led_data_in10=0xFF` |
| `top_project.v` | 路由 `w_inner_brightness` + `w_outer_brightness` 双线 |
| `main.dart` | Mode 3 单帧发包 + nibble 打包 `(inner4<<4)\|outer4`；移除旧双帧竞态逻辑 |

### V2.0 — 5 字节协议 + 中心对称波浪呼吸灯

### V1.0 — 初版：3 字节协议 + 基础 BLE 双向通信
