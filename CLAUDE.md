# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **湖南大学 CSEE EC C301 - 综合选题3** (HNU LED System), a wireless smart RGB LED control system with two sub-projects:

1. **`hnu_led_controller/`** — Flutter mobile app that sends Bluetooth control commands
2. **`experiements5/`** — Intel Quartus Prime FPGA project (Verilog) that receives UART commands via a Bluetooth module and drives WS2812 LED strips

## Common Commands

### Flutter App (`hnu_led_controller/`)

```bash
# Install dependencies
cd hnu_led_controller && flutter pub get

# Static analysis / lint
flutter analyze

# Run tests
flutter test

# Run a single test
flutter test test/widget_test.dart

# Run the app (requires connected device/emulator)
flutter run

# Build APK
flutter build apk
```

### FPGA Project (`experiements5/`)

- Open `experiements5.qpf` in Intel Quartus Prime (version 24.1std.0 Lite Edition or newer)
- Target device: **Cyclone IV E EP4CE15F17C8**
- Processing menu: Compile Design (or `quartus_map`, `quartus_fit`, `quartus_asm` from CLI)
- Programmer: Use USB Blaster to flash the `.sof` file from `output_files/`

## Architecture

### Communication Protocol

The Flutter app communicates with the FPGA over **Bluetooth Low Energy (BLE) via a UART serial pass-through module** (PMOD interface). A custom 3-byte protocol is used:

| Byte | Field | Description |
|------|-------|-------------|
| 0 | `0x5A` | Frame header (magic byte) |
| 1 | Mode | `0x01` = static color, `0x02` = water-flow animation, `0x03` = digitron group color scroll |
| 2 | Param | Color mask (mode 1) / speed divisor (mode 2) / reserved (mode 3) |

FPGA acknowledges button presses by sending `0xC3` back to the app.

### Flutter App Architecture (`hnu_led_controller/lib/`)

- **`main.dart`** — Entry point. Wraps the app in a `ChangeNotifierProvider<BleController>` (via the `provider` package). `HomeScreen` widget builds the full UI: BLE scan list (sorted by RSSI signal strength), connection status, and three LED control panels (static color, water-flow animation with speed slider, and digitron group scroll).
- **`bluetooth_controller.dart`** — `BleController` extends `ChangeNotifier`. Manages BLE scanning (`flutter_blue_plus`), device connection, service/characteristic discovery (targeting WRITE and NOTIFY characteristics), and sending the 3-byte protocol frames. Receives `0xC3` feedback from the FPGA via NOTIFY.

Key dependencies: `flutter_blue_plus: ^1.34.0`, `provider: ^6.1.2`, `flutter_lints: ^6.0.0`.

### FPGA Architecture (`experiements5/`)

The FPGA design is a **6-module data pipeline** instantiated in `top_project.v`:

```
UART RX → UART TX
    ↓         ↑
tx_rx_arbiter (Rx-priority bus arbiter)
    ↓
cmd_parser (3-byte frame detection via FSM: IDLE→CHECK→UPDATE)
    ↓
effect_generator (water-flow animation, digitron scrolling, static color passthrough)
    ↓
my_ws2812 (WS2812 single-wire driver, 8-LED GRB serial output)
    ↓
led_out (physical pin)
```

**Module details:**

- **`uart_rx.v`** — Parametrizable UART receiver (50MHz, 115200 baud). Uses a half-stop-bit return technique for fast consecutive byte processing. 4-state FSM: IDLE → START → DATA → STOP.
- **`uart_tx.v`** — UART transmitter. Triggered by a negative-edge on `tx_en`. Sends 1 start bit, 8 data bits, 1 stop bit at 115200 baud.
- **`tx_rx_arbiter.v`** — Bus arbiter implementing **Rx absolute priority** over Tx. Registers pending Tx requests so they aren't lost when Rx is active. Outputs filtered `arb_rx_data`/`arb_rx_valid` to downstream modules.
- **`cmd_parser.v`** — 3-state FSM that assembles 3-byte packets, validates the `0x5A` frame header, and latches `ctrl_mode`/`ctrl_param` onto global control buses.
- **`effect_generator.v`** — Multi-mode effect engine: mode `0x01` passes through static color mask; mode `0x02` generates water-flow one-hot patterns with speed controlled by `ctrl_param`; mode `0x03` scrolls 4-digitron color codes (2-bit quaternary encoding: 0=off, 1=green, 2=red, 3=blue per segment).
- **`my_ws2812.v`** — WS2812 timing driver. Generates precise 1-bit (900ns high) and 0-bit (300ns high) pulses within 1.25μs bit periods. Drives 8 LEDs in sequence per frame, with a 90μs reset gap. Supports two modes: binary on/off and quaternary 4-color group control. Locks input data at frame boundaries for stable rendering.
- **`pro1.v`** — Earlier standalone demo top-level (using physical mode-switch key). Not part of the `top_project` pipeline; kept as reference.

**Pin assignments** (Cyclone IV E EP4CE15F17C8):
- `PIN_E1` — 50MHz clock
- `PIN_L2` — Hardware reset (active low)
- `PIN_B11` — UART RX (Bluetooth → FPGA)
- `PIN_D6` — UART TX (FPGA → Bluetooth)
- `PIN_T2` — WS2812 LED data output
- `PIN_K1` — Button feedback (triggers `0xC3` response)

## Testing

The Flutter test (`test/widget_test.dart`) is a stock Flutter counter test template and does **not** test actual app functionality. It will fail with the real app — update it to match the actual UI before running tests.
