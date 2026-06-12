# hnu_led_system_all — PLUS 双板驱动版

湖南大学 CSEE EC C301 - 综合选题3：无线智能 RGB LED 控制系统（V4 PLUS）

## 项目简介

本项目实现了一套基于 **Flutter 手机 App + FPGA 硬件** 的无线蓝牙智能 RGB LED 控制系统。

- **手机端**：Flutter 应用，通过 BLE 蓝牙发送 5 字节自定义协议指令
- **FPGA 端**：Verilog 硬件设计，通过 UART 接收指令并驱动 **双路 WS2812 LED 灯带**
- **PLUS 新特性**：双板独立驱动（板载 8 灯 + 外接 PMOD 8 灯）、Mode 4 S 型往返追逐、复位时序裕度增强

## 项目结构

```
hnu_led_system_all/
├── hnu_led_controller/           # Flutter 手机 App
│   └── lib/
│       ├── main.dart                     # UI 界面（BLE 扫描/连接、4 模式控制面板）
│       └── bluetooth_controller.dart     # BLE 蓝牙通信控制器（Provider 状态管理）
├── experiements5/                 # Intel Quartus Prime FPGA 工程
│   ├── top_project.v              # 顶层模块（7 模块双板流水线集成）
│   ├── uart_rx.v                  # UART 接收器（115200 baud）
│   ├── uart_tx.v                  # UART 发送器
│   ├── tx_rx_arbiter.v            # 收发仲裁器（Rx 绝对优先）
│   ├── cmd_parser.v               # 5 字节协议帧解析状态机（含看门狗）
│   ├── effect_generator.v         # 多模式 LED 效果发生器（4 模式 + 双板输出）
│   ├── my_ws2812.v                # WS2812 单线驱动（8-LED GRB，500μs 复位）
│   ├── diag_led_test.v            # 双板纯硬件诊断模块（绕过全部上层逻辑）
│   ├── pro1.v                     # 早期独立演示顶层（参考用）
│   ├── experiements5.qpf          # Quartus 工程文件
│   └── experiements5.qsf          # 引脚与工程约束
├── problem.txt                    # 问题记录
└── CLAUDE.md                      # 项目开发指南
```

## 通信协议（V4 — 5 字节帧，nibble 分拆亮度）

| 字节 | 字段 | 说明 |
|------|------|------|
| 0 | `0x5A` | 帧头（魔术字节） |
| 1 | Mode | `0x01` 独立灯珠 / `0x02` 大环流水灯 / `0x03` 呼吸灯 / **`0x04` S 型追逐** |
| 2 | Color | `0x01` 红 / `0x02` 绿 / `0x03` 蓝 |
| 3 | Brightness | Mode 1/2/4: 全局 PWM 亮度 0~255（FPGA 取高 4-bit） |
|   |            | **Mode 3: `[7:4]` = 内群亮度(0~15), `[3:0]` = 外群亮度(0~15)** |
| 4 | Speed/Param | Mode 1: LED 掩码 / Mode 2: 步进索引 / Mode 3: 节拍速度 / Mode 4: 追逐速度 |

FPGA 按键反馈：`0xC3`（通过 BLE NOTIFY 上报至 App）

### Mode 3 nibble 分拆架构（V3 保留）

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

## LED 物理位映射（双板统一）

UI 按钮 1~8 → FPGA `led_data_in10` 比特位：

| UI 按钮 | FPGA 位 | my_ws2812 索引 | 内/外群 | 网格位置 |
|---------|---------|---------------|---------|----------|
| 1 | bit4 | `g_rgb_flat[0]` | 外群 | Row 1, Col 4 |
| 2 | bit5 | `g_rgb_flat[1]` | 内群 | Row 1, Col 3 |
| 3 | bit6 | `g_rgb_flat[2]` | 内群 | Row 1, Col 2 |
| 4 | bit7 | `g_rgb_flat[3]` | 外群 | Row 1, Col 1 |
| 5 | bit3 | `g_rgb_flat[4]` | 外群 | Row 2, Col 1 |
| 6 | bit2 | `g_rgb_flat[5]` | 内群 | Row 2, Col 2 |
| 7 | bit1 | `g_rgb_flat[6]` | 内群 | Row 2, Col 3 |
| 8 | bit0 | `g_rgb_flat[7]` | 外群 | Row 2, Col 4 |

2×4 网格布局（俯视）：
```
Row 1: [Btn4] [Btn3] [Btn2] [Btn1]   ← 外左 → 外右
Row 2: [Btn5] [Btn6] [Btn7] [Btn8]   ← 外左 → 外右
```

**内群** (LED 2,3,6,7)：网格中间 2 列，使用 `inner_brightness`
**外群** (LED 1,4,5,8)：网格外侧 2 列，使用 `outer_brightness`

## PLUS 双板驱动架构

```
                         top_project.v
┌──────────────────────────────────────────────────────────────┐
│  UART RX ← 蓝牙模块                                           │
│      ↓                                                       │
│  tx_rx_arbiter (Rx 绝对优先级仲裁)                              │
│      ↓                                                       │
│  cmd_parser (5 字节帧解析 FSM + 1ms 看门狗)                      │
│      ↓                                                       │
│  effect_generator (4 模式效果计算)                               │
│      ├── led_data_in10 / led_data_in32 ─────→ Board 1 数据总线 │
│      ├── led_data_in10_b2 / led_data_in32_b2 → Board 2 数据总线 │
│      ├── inner_brightness / outer_brightness (双板共享)         │
│      └── driver_mode (双板共享)                                │
│      ↓                                                       │
│  ┌─────────────────────┐   ┌─────────────────────┐            │
│  │ my_ws2812 (Board 1) │   │ my_ws2812 (Board 2) │            │
│  │ 独立状态机，独立时序  │   │ 独立状态机，独立时序  │            │
│  │ 帧锁存 @ ST_RESET   │   │ 帧锁存 @ ST_RESET   │            │
│  │ 192-bit GRB 串出    │   │ 192-bit GRB 串出    │            │
│  └─────────┬───────────┘   └─────────┬───────────┘            │
│            ↓                         ↓                        │
│        PIN_T2 → Board 1          PIN_T3 → Board 2             │
│        (板载 8 灯)               (外接 PMOD 8 灯)              │
└──────────────────────────────────────────────────────────────┘
```

**关键设计**：两个 `my_ws2812` 实例完全独立运行，在每帧 RESET 结束时刻同时锁存输入数据，各自独立生成 192-bit GRB 串行波形。

## 硬件平台

- **FPGA**：Cyclone IV E EP4CE15F17C8
- **主时钟**：50MHz（PIN_E1）
- **LED**：WS2812 灯带 ×2（板载 8 灯 + 外接 PMOD 8 灯）
- **蓝牙**：BLE 串口透传模块（PMOD 接口，UART 115200 baud）
- **开发工具**：Intel Quartus Prime 24.1std.0 Lite Edition

### 引脚分配

| 引脚 | 信号 | 功能 |
|------|------|------|
| PIN_E1 | `clk` | 50MHz 主时钟 |
| PIN_L2 | `rst_n` | 硬件复位（低有效） |
| PIN_B11 | `uart_rx` | UART RX（蓝牙 → FPGA） |
| PIN_D6 | `uart_tx` | UART TX（FPGA → 蓝牙） |
| PIN_K1 | `key_feedback` | 按键反馈（触发 0xC3 上报） |
| PIN_T2 | `led_out` | Board 1 WS2812 数据输出（板载） |
| PIN_T3 | `led_out_b2` | Board 2 WS2812 数据输出（外接 PMOD） |
| PIN_P1 | `feedback_b2` | Board 2 末级环回监测（预留） |

## 功能特性

### 模式一：独立灯珠控制（Mode `0x01`）

- 8 个 LED 独立开关（2×4 网格 UI）
- **双板镜像输出**：Board 1 和 Board 2 同步点亮相同灯珠
- 全局颜色切换（红/绿/蓝），保留当前 LED 开关掩码
- 全开 / 全关快捷按钮
- 全局亮度滑块实时调节（0~255）

### 模式二：大环流水灯（Mode `0x02`）

- 16 步 Grand Ring 追逐路径，**双板联动无缝桥接**：
  - Step 0~7：Board 1 LED 1→2→3→4→5→6→7→8
  - Step 8~15：Board 2 LED 1→2→3→4→8→7→6→5
- App 端 Timer 流式发送步索引（Byte 4 = step 0~15）
- FPGA 组合逻辑译码，零延迟响应
- 速度滑块 + 全局颜色/亮度叠加控制

### 模式三：中心对称波浪呼吸灯（Mode `0x03`）

- **仅 Board 1 参与**（Board 2 全灭）
- 内列与外列以 180° 反相呼吸
- **nibble 分拆**：Byte 3 高 4-bit 控制内群，低 4-bit 控制外群（各 0~15）
- 视觉波浪预览 UI（4 列实时强度指示器）
- 节拍调节滑块（1=极速，15=最缓）

### 模式四：S 型往返追逐（Mode `0x04`）★ PLUS 新增

- 16 步 S 型路径，**双板接力追逐**：
  - Step 0~3：Board 1 上排右→左（LED 4→3→2→1）
  - Step 4~11：Board 2 全板 S 型扫描（LED 1→2→3→4→5→6→7→8）
  - Step 12~15：Board 1 下排左→右（LED 8→7→6→5）
- FPGA 硬件自主动画（50ms 基础步进 × 速度衰减因子）
- 心跳保活：每 16 步 App 自动重发帧，防止 BLE 丢帧导致退出
- 速度滑块（Byte 4，值小越快）+ 全局颜色/亮度叠加

### 系统功能

- BLE 蓝牙扫描（RSSI 信号强度自动排序置顶）
- 双向通信：App 下发指令 + FPGA 按键反馈上报（0xC3）
- 帧同步看门狗自动恢复（1ms 超时）
- 暗黑科技风 UI（AnimatedContainer 动态视觉效果）

## FPGA 架构（数据流水线，V4 双板输出）

```
UART RX ──────→ UART TX
    ↓               ↑
tx_rx_arbiter (Rx 绝对优先级仲裁)
    ↓
cmd_parser (5 字节帧 FSM：WAIT_HEADER → GET_MODE → GET_COLOR → GET_BRIGHT → GET_PARAM)
    ↓
effect_generator (4 模式效果计算 → 双板 data10/data32 + 双亮度输出)
    ↓
┌───────────────────┴───────────────────┐
my_ws2812 (Board 1)          my_ws2812 (Board 2)
    ↓                               ↓
led_out (PIN_T2)              led_out_b2 (PIN_T3)
    ↓                               ↓
Board 1 (板载 8 LED)         Board 2 (外接 PMOD 8 LED)
```

### WS2812 时序参数

| 参数 | 值 | 说明 |
|------|-----|------|
| T1H | 900ns (45 cycles) | 1 码高电平 |
| T0H | 300ns (15 cycles) | 0 码高电平 |
| Tbit | 1.25μs (62 cycles) | 单 bit 周期 |
| **Treset** | **500μs (25000 cycles)** | **复位低电平（> 80μs 规格线，6× 裕度）** |

> ⚠️ **Treset 从 90μs 提升至 500μs** 是 PLUS 版的关键修复。旧版 90μs 刚好擦过 WS2812 规格下限，外接板经 PMOD 排线传输后裕度不足，导致首次烧录/冷启动时灯条复位失败。500μs 提供充足裕度，确保任何条件下双板均可靠初始化。

## 快速开始

### Flutter App

```bash
cd hnu_led_controller
flutter pub get
flutter run
```

### FPGA

1. 用 Intel Quartus Prime 打开 `experiements5/experiements5.qpf`
2. 编译设计（Processing → Start Compilation）
3. 通过 USB Blaster 烧录 `output_files/experiements5.sof`
4. 上电后打开 Flutter App，扫描并连接蓝牙设备
5. 选择模式并实时控制 LED 灯带

### 硬件诊断

如果怀疑外接板硬件故障，可切换到纯硬件诊断模式：

1. 修改 `experiements5.qsf` 第 42 行：
   ```
   set_global_assignment -name TOP_LEVEL_ENTITY diag_led_test
   ```
2. 重新编译并烧录
3. `diag_led_test` 绕过全部上层逻辑，硬编码双板 8 灯全亮绿色
4. 诊断完成后恢复 `TOP_LEVEL_ENTITY top_project`

## 依赖

### Flutter

- `flutter_blue_plus: ^1.34.0` — BLE 蓝牙通信
- `provider: ^6.1.2` — 状态管理
- `flutter_lints: ^6.0.0` — 代码规范

### FPGA

- Intel Quartus Prime 24.1std.0 Lite Edition（或更新版本）
- USB Blaster 下载器
- Cyclone IV E EP4CE15F17C8 开发板
- WS2812 灯带 ×2（板载 + PMOD 外接）
- BLE 串口透传模块（HM-10 / JDY-31 等）

## 变更日志

### V4 PLUS — 双板独立驱动（当前版本）

**新功能**：

| 特性 | 说明 |
|------|------|
| 双板驱动 | `top_project.v` 例化两个独立 `my_ws2812` 实例，`effect_generator.v` 输出双板独立数据总线 |
| Mode 4 S 型追逐 | 16 步双板接力 S 型路径，FPGA 硬件自主动画 |
| 诊断模块 | `diag_led_test.v` 纯硬件双板测试，绕过全部上层逻辑 |
| 复位时序增强 | `RST_COUNT` 90μs → 500μs，解决外接板冷启动不亮 |

**Bug 修复**：

| 问题 | 根因 | 修复 |
|------|------|------|
| Mode 4 Board 2 全黑 | `effect_generator.v` 诊断镜像代码残留（`chase_data_b1` → Board 2） | 改为 `chase_data_b2` |
| Mode 2 亮度/换色跳步 | Flutter 发送 `_currentSpeed` 替代 `_waterStep` 作为 Byte 4 | Mode 2 分支使用 `_waterStep` + nibble 打包亮度 |
| Mode 4 单帧丢帧退出 | BLE 启动帧丢失后 FPGA 永远停留在默认模式 | `_onChaseTick` 每 16 步心跳重发 |
| 外接板首次烧录不亮 | `RST_COUNT=90μs` 裕度不足，PMOD 排线传输后 WS2812 复位失败 | `RST_COUNT` 提升至 500μs（6× 裕度） |

**修改文件清单**：

| 文件 | 变更 |
|------|------|
| `effect_generator.v` | 新增 Mode 4 S 型追逐引擎 + 双板独立数据输出（`led_data_in10_b2`, `led_data_in32_b2`） |
| `my_ws2812.v` | `RST_COUNT` 90μs → 500μs |
| `top_project.v` | 新增 Board 2 `my_ws2812` 实例 + `led_out_b2` / `feedback_b2` 端口 |
| `cmd_parser.v` | 看门狗定时器 + 默认参数 `8'hFF`（全亮） |
| `experiements5.qsf` | 新增 PIN_T3 (`led_out_b2`) / PIN_P1 (`feedback_b2`) 引脚约束 |
| `diag_led_test.v` | **新增**：双板纯硬件诊断模块 |
| `main.dart` | Mode 2 nibble 打包 + Mode 4 心跳保活 + 双板追逐 UI |
| `bluetooth_controller.dart` | 5 字节协议 `sendProtocolCmd` 诊断日志增强 |

### V3.0 — nibble 分拆双亮度端口

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
