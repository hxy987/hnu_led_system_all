import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'bluetooth_controller.dart';

void main() {
  runApp(
    // 使用 Provider 挂载我们的蓝牙控制器，让整个界面能实时感知蓝牙状态的变化
    ChangeNotifierProvider(
      create: (_) => BleController(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '无线智能RGB灯控制端',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF121212), // 暗黑科技风背景
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ============================================================
  // V2 全局状态：5-Byte 协议 [0x5A, mode, color, brightness, speed]
  // ============================================================
  int _activeMode = 0x01; // 当前激活模式：0x01=独立灯珠, 0x02=流水灯, 0x03=呼吸灯
  int _currentColor = 0x02; // 全局颜色：0x01=红, 0x02=绿, 0x03=蓝（默认绿）
  double _currentBrightness = 128.0; // 全局亮度 0~255（默认中位）
  double _currentSpeed = 10.0; // 速度/节拍参数 0~255（默认10）

  // 独立 LED 控制状态（8 个灯珠开关，比特位按 _ledBitPositions 映射）
  final List<bool> _ledStates = List.filled(8, false);

  // Mode 3 波浪呼吸灯状态
  Timer? _waveTimer;
  double _wavePhase = 0.0; // 波浪相位 0.0 ~ 1.0（连续循环）
  double _innerIntensity = 0.0; // 内群强度 0.0~1.0（UI 预览用）
  double _outerIntensity = 0.0; // 外群强度 0.0~1.0（UI 预览用）
  int _innerBrightnessValue = 0; // 内群实际亮度字节值 0~255
  int _outerBrightnessValue = 0; // 外群实际亮度字节值 0~255

  // ================================================================
  // Mode 2 大环流水灯 状态 (V4 Refactor: App-Streaming 双板联动)
  // ================================================================
  Timer? _waterTimer;
  int _waterStep = 0; // 大环流水当前步 (0~15)

  // ================================================================
  // Mode 4 S型往返追逐 状态
  // ================================================================
  Timer? _chaseTimer;
  int _chaseStep = 0; // 追逐当前步 (0~15)

  @override
  Widget build(BuildContext context) {
    // 监听我们的蓝牙大管家
    final bleWatch = context.watch<BleController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('无线智能RGB灯 C301'),
        centerTitle: true,
        backgroundColor: Colors.indigo,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ----------------- 1. 蓝牙连接状态与操作区 -----------------
              Card(
                color: const Color(0xFF1E1E1E),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        bleWatch.connectedDevice == null
                            ? "当前状态：未连接蓝牙"
                            : "已成功连接：${bleWatch.connectedDevice!.platformName.isEmpty ? '未知设备' : bleWatch.connectedDevice!.platformName}",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 【诊断】显示详细蓝牙状态（含TX通道就绪状态）
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: bleWatch.isServicesReady
                              ? Colors.green.withOpacity(0.15)
                              : (bleWatch.connectedDevice != null
                                  ? Colors.orange.withOpacity(0.15)
                                  : Colors.transparent),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: bleWatch.isServicesReady
                                ? Colors.green
                                : (bleWatch.connectedDevice != null
                                    ? Colors.orange
                                    : Colors.transparent),
                          ),
                        ),
                        child: Text(
                          bleWatch.statusMessage,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: bleWatch.isServicesReady
                                ? Colors.greenAccent
                                : (bleWatch.connectedDevice != null
                                    ? Colors.orangeAccent
                                    : Colors.grey),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // 【诊断】显示最近的错误信息
                      if (bleWatch.lastError.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red),
                          ),
                          child: Text(
                            bleWatch.lastError,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.redAccent,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: bleWatch.isScanning
                                ? null
                                : () => bleWatch.startScan(),
                            icon: const Icon(Icons.search),
                            label: Text(
                              bleWatch.isScanning ? "正在搜寻..." : "搜索蓝牙",
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                            ),
                          ),
                          if (bleWatch.connectedDevice != null)
                            ElevatedButton.icon(
                              onPressed: () => bleWatch.disconnect(),
                              icon: const Icon(Icons.link_off),
                              label: const Text("断开连接"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ----------------- 2. 信号由强到弱的设备卡片选择区 -----------------
              if (bleWatch.connectedDevice == null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    "附近设备列表（信号最强的已自动置顶）：",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 6),
                // 动态渲染扫描到的蓝牙列表
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: bleWatch.scanResults.length,
                  itemBuilder: (context, index) {
                    final result = bleWatch.scanResults[index];
                    final name = result.device.platformName;
                    final rssi = result.rssi;

                    // 确定信号强度的视觉颜色
                    Color rssiColor = Colors.green;
                    if (rssi < -80)
                      rssiColor = Colors.red;
                    else if (rssi < -65)
                      rssiColor = Colors.orange;

                    return Card(
                      color: const Color(0xFF252525),
                      child: ListTile(
                        leading: Icon(Icons.bluetooth, color: rssiColor),
                        title: Text(
                          name.isEmpty ? "未命名设备" : name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(result.device.remoteId.str),
                        // 右侧显示信号强弱数值
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$rssi dBm',
                              style: TextStyle(
                                color: rssiColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.signal_cellular_alt,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                        onTap: () {
                          // 手动点击任意一个卡片，连接信号最强的物理板子
                          bleWatch.connectToDevice(result.device);
                        },
                      ),
                    );
                  },
                ),
              ],

              // ----------------- 3. FPGA 指令控制面板 (V2 重构) -----------------
              if (bleWatch.connectedDevice != null) ...[
                const SizedBox(height: 12),
                const Text(
                  "效果控制面板",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigoAccent,
                  ),
                ),
                const Divider(color: Colors.indigo),

                // ================================================================
                // V2: 全局亮度控制（置顶，Mode 3 呼吸灯时锁定禁用）
                // ================================================================
                Card(
                  color: const Color(0xFF1E1E1E),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.brightness_6,
                                color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              "全局亮度控制",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Spacer(),
                            Text(
                              "${_currentBrightness.toInt()}/255",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.amberAccent,
                                fontFamily: 'monospace',
                              ),
                            ),
                            if (_activeMode == 0x03) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.lock,
                                  color: Colors.redAccent, size: 14),
                            ],
                          ],
                        ),
                        Slider(
                          value: _currentBrightness,
                          min: 0.0,
                          max: 255.0,
                          divisions: 51,
                          label: "亮度: ${_currentBrightness.toInt()}",
                          activeColor: (_activeMode != 0x03 &&
                                  bleWatch.isServicesReady)
                              ? Colors.amber
                              : Colors.grey,
                          onChanged: (_activeMode != 0x03 &&
                                  bleWatch.isServicesReady)
                              ? (value) {
                                  setState(() {
                                    _currentBrightness = value;
                                  });
                                  if (_activeMode == 0x01) {
                                    // Mode 1: 亮度变更时保留当前 LED 开关掩码
                                    int mask = 0;
                                    for (int i = 0; i < 8; i++) {
                                      if (_ledStates[i])
                                        mask |= (1 << _ledBitPositions[i]);
                                    }
                                    _sendFullFrame(bleWatch,
                                        mode: 0x01,
                                        brightness: _currentBrightness.toInt(),
                                        speed: mask);
                                  } else if (_activeMode == 0x02) {
                                    // Mode 2: nibble打包亮度 + 保持当前waterStep不跳步
                                    _sendFullFrame(bleWatch,
                                        mode: 0x02,
                                        brightness: _packBrightnessNibbles(value),
                                        speed: _waterStep);
                                  } else if (_activeMode == 0x04) {
                                    // Mode 4: 亮度变更时重发追逐帧
                                    _sendChaseFrame(bleWatch);
                                  } else {
                                    _sendFullFrame(bleWatch,
                                        brightness: _currentBrightness.toInt());
                                  }
                                }
                              : null,
                        ),
                        Text(
                          _activeMode == 0x03
                              ? "⚠ 呼吸灯模式下亮度由FPGA自动调节，手动控制已锁定"
                              : "提示：拖动滑块实时调节LED全局PWM亮度（0最暗，255最亮）",
                          style: TextStyle(
                            fontSize: 11,
                            color: _activeMode == 0x03
                                ? Colors.redAccent
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ================================================================
                // V2: 全局颜色选择行
                // ================================================================
                const Text(
                  "全局颜色",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildGlobalColorButton(
                      bleWatch, "纯红", Colors.red, 0x01),
                    _buildGlobalColorButton(
                      bleWatch, "纯绿", Colors.green, 0x02),
                    _buildGlobalColorButton(
                      bleWatch, "纯蓝", Colors.blue, 0x03),
                  ],
                ),
                const Divider(color: Colors.indigo),
                const SizedBox(height: 4),

                // ================================================================
                // 模式一：独立灯珠控制 (V2 合并原 Mode 1 静态控色 + 独立 LED)
                // ================================================================
                const Text(
                  "模式一：独立灯珠控制",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                // 全开 / 全关 快捷按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: bleWatch.isServicesReady
                          ? () {
                              _stopWaveBreathing();
                              _stopWaterFlow();
                              _stopChaseAnimation();
                              setState(() {
                                _activeMode = 0x01;
                                for (int i = 0; i < 8; i++)
                                  _ledStates[i] = true;
                              });
                              _sendLedMask(bleWatch);
                            }
                          : null,
                      icon: const Icon(Icons.lightbulb, size: 16),
                      label: const Text("全开"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: bleWatch.isServicesReady
                          ? () {
                              _stopWaveBreathing();
                              _stopWaterFlow();
                              _stopChaseAnimation();
                              setState(() {
                                _activeMode = 0x01;
                                for (int i = 0; i < 8; i++)
                                  _ledStates[i] = false;
                              });
                              _sendLedMask(bleWatch);
                            }
                          : null,
                      icon: const Icon(Icons.lightbulb_outline, size: 16),
                      label: const Text("全关"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 2×4 LED 矩阵（对齐物理硬件布局）
                // Row 1 (左→右): Button 4, 3, 2, 1
                // Row 2 (左→右): Button 5, 6, 7, 8
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _ledDisplayOrder.sublist(0, 4).map((i) {
                        return _buildLedButton(
                            bleWatch.isServicesReady, i, '${i + 1}');
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _ledDisplayOrder.sublist(4, 8).map((i) {
                        return _buildLedButton(
                            bleWatch.isServicesReady, i, '${i + 1}');
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ================================================================
                // 模式二：大环流水灯特效 (V4 Refactor — 双板联动 App-Streaming)
                // ================================================================
                const Text(
                  "模式二：大环流水灯特效",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  "双板 16 步 Grand Ring — Board 1 → Board 2 无缝循环",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                // 启动/停止按钮行
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: (_activeMode != 0x02 &&
                              bleWatch.isServicesReady)
                          ? () {
                              _stopWaveBreathing();
                              _stopChaseAnimation();
                              setState(() => _activeMode = 0x02);
                              _startWaterFlow(bleWatch);
                            }
                          : null,
                      icon: const Icon(Icons.water_drop, size: 16),
                      label: const Text("启动流水灯"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: (_activeMode == 0x02 &&
                              bleWatch.isServicesReady)
                          ? () {
                              _stopWaterFlow();
                              setState(() => _activeMode = 0x01);
                              _sendFullFrame(bleWatch,
                                  mode: 0x01, speed: 0);
                            }
                          : null,
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text("停止流水灯"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 仅当流水灯激活时显示双板预览 + 速度滑块
                if (_activeMode == 0x02) ...[
                  // ── 双板 2×4 LED 大环流水预览 ──
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          // 当前步骤提示
                          Text(
                            _buildWaterStepLabel(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.tealAccent,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 10),
                          // 两个板并排
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [
                              // ── Board 1（板载）──
                              _buildWaterBoardPreview(
                                "板载 Board 1",
                                Colors.indigoAccent,
                                0,
                              ),
                              // ── Board 2（外接）──
                              _buildWaterBoardPreview(
                                "外接 Board 2",
                                Colors.tealAccent,
                                1,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── 速度调节滑块 ──
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.speed,
                                  color: Colors.tealAccent, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                "流水速度调节",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                              const Spacer(),
                              Text(
                                "速度: ${_currentSpeed.toInt()}/15",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.tealAccent,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _currentSpeed,
                            min: 1.0,
                            max: 15.0,
                            divisions: 14,
                            label: "速度: ${_currentSpeed.toInt()}",
                            activeColor: bleWatch.isServicesReady
                                ? Colors.tealAccent
                                : Colors.grey,
                            onChanged: bleWatch.isServicesReady
                                ? (value) {
                                    setState(
                                        () => _currentSpeed = value);
                                    _updateWaterSpeed(bleWatch);
                                  }
                                : null,
                          ),
                          const Text(
                            "提示：1=极速流水，15=最缓漫步",
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // ================================================================
                // 模式三：中心对称波浪呼吸灯
                // ================================================================
                const Text(
                  "模式三：中心对称波浪呼吸灯",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  "2×4 网格波浪 — 中心向外扩散，内列/外列交替呼吸",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                // 启动/停止按钮行
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: (_activeMode != 0x03 &&
                              bleWatch.isServicesReady)
                          ? () {
                              _stopChaseAnimation();
                              setState(() => _activeMode = 0x03);
                              _startWaveBreathing(bleWatch);
                            }
                          : null,
                      icon: const Icon(Icons.waves, size: 16),
                      label: const Text("启动波浪"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: (_activeMode == 0x03 &&
                              bleWatch.isServicesReady)
                          ? () {
                              _stopWaveBreathing();
                              _stopWaterFlow();
                              setState(() => _activeMode = 0x01);
                            }
                          : null,
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text("停止波浪"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 仅当波浪激活时显示预览 + 节拍滑块
                if (_activeMode == 0x03) ...[
                  // 波浪可视化预览 — 内群/外群实时亮度
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          const Text(
                            "波浪呼吸预览（动态亮度调制）",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildWaveColumn("外左\nCol1", _outerIntensity,
                                  _outerBrightnessValue),
                              _buildWaveColumn("内左\nCol2", _innerIntensity,
                                  _innerBrightnessValue),
                              _buildWaveColumn("内右\nCol3", _innerIntensity,
                                  _innerBrightnessValue),
                              _buildWaveColumn("外右\nCol4", _outerIntensity,
                                  _outerBrightnessValue),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 节拍调节滑块
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.speed,
                                  color: Colors.purpleAccent, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                "波浪节拍调节",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Spacer(),
                              Text(
                                "节拍: ${_currentSpeed.toInt()}/15",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.purpleAccent,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _currentSpeed,
                            min: 1.0,
                            max: 15.0,
                            divisions: 14,
                            label: "节拍: ${_currentSpeed.toInt()}",
                            activeColor: bleWatch.isServicesReady
                                ? Colors.purpleAccent
                                : Colors.grey,
                            onChanged: bleWatch.isServicesReady
                                ? (value) {
                                    setState(() => _currentSpeed = value);
                                    _updateWaveInterval(bleWatch);
                                  }
                                : null,
                          ),
                          const Text(
                            "提示：1=极速扩散，15=最缓呼吸",
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),

                // ================================================================
                // 模式四：S型往返追逐 (V4 新增)
                // ================================================================
                const Text(
                  "模式四：S型往返追逐",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  "双板联动 — Board 1 与 Board 2 交替S型追光",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                // 启动/停止按钮行
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: (_activeMode != 0x04 &&
                              bleWatch.isServicesReady)
                          ? () {
                              setState(() => _activeMode = 0x04);
                              _startChaseAnimation(bleWatch);
                            }
                          : null,
                      icon: const Icon(Icons.directions_run, size: 16),
                      label: const Text("启动追逐"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: (_activeMode == 0x04 &&
                              bleWatch.isServicesReady)
                          ? () {
                              _stopChaseAnimation();
                              setState(() => _activeMode = 0x01);
                              _sendFullFrame(bleWatch, mode: 0x01, speed: 0);
                            }
                          : null,
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text("停止追逐"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 仅当追逐激活时显示双板预览 + 速度滑块
                if (_activeMode == 0x04) ...[
                  // ── 双板 2×4 LED 追逐预览 ──
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          // 当前步骤提示
                          Text(
                            _buildChaseStepLabel(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orangeAccent,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 10),
                          // 两个板并排
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // ── Board 1（板载）──
                              _buildBoardPreview(
                                "板载 Board 1",
                                Colors.indigoAccent,
                                0,
                              ),
                              // ── Board 2（外接）──
                              _buildBoardPreview(
                                "外接 Board 2",
                                Colors.tealAccent,
                                1,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── 速度调节滑块 ──
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.speed,
                                  color: Colors.deepOrangeAccent, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                "追逐速度调节",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Spacer(),
                              Text(
                                "速度: ${_currentSpeed.toInt()}/15",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.deepOrangeAccent,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _currentSpeed,
                            min: 1.0,
                            max: 15.0,
                            divisions: 14,
                            label: "速度: ${_currentSpeed.toInt()}",
                            activeColor: bleWatch.isServicesReady
                                ? Colors.deepOrangeAccent
                                : Colors.grey,
                            onChanged: bleWatch.isServicesReady
                                ? (value) {
                                    setState(() => _currentSpeed = value);
                                    _updateChaseSpeed(bleWatch);
                                  }
                                : null,
                          ),
                          const Text(
                            "提示：1=极速追逐，15=最缓漫步",
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),

                // ----------------- 4. 上行反馈信息看板 -----------------
                Card(
                  color: Colors.blueGrey.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Colors.blueGrey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.developer_board,
                          color: Colors.blueAccent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            bleWatch.feedbackMessage,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // V2 核心：发送完整 5-Byte 帧，保留所有未修改参数
  //   帧格式：[0x5A, mode, color, brightness, speed]
  // ================================================================
  void _sendFullFrame(
    BleController ble, {
    int? mode,
    int? color,
    int? brightness,
    int? speed,
  }) {
    final m = mode ?? _activeMode;
    final c = color ?? _currentColor;
    final b = brightness ?? _currentBrightness.toInt();
    final s = speed ?? _currentSpeed.toInt();
    ble.sendProtocolCmd(m, c, b, s);
  }

  // 构建全局颜色选择按钮
  Widget _buildGlobalColorButton(
    BleController ble,
    String label,
    Color color,
    int colorCode,
  ) {
    final isSelected = _currentColor == colorCode;
    return ElevatedButton(
      onPressed: ble.isServicesReady
          ? () {
              setState(() => _currentColor = colorCode);
              if (_activeMode == 0x01) {
                // Mode 1: 保留当前 LED 开关掩码，仅切换颜色
                int mask = 0;
                for (int i = 0; i < 8; i++) {
                  if (_ledStates[i]) mask |= (1 << _ledBitPositions[i]);
                }
                _sendFullFrame(ble, mode: 0x01, color: colorCode, speed: mask);
              } else if (_activeMode == 0x03) {
                // Mode 3: 仅更新颜色状态，波浪 Timer 会在下一拍自动使用新颜色
              } else if (_activeMode == 0x04) {
                // Mode 4: 换色时发送新帧，FPGA 立即使用新颜色继续追逐
                _sendChaseFrame(ble);
              } else if (_activeMode == 0x02) {
                // Mode 2: 换色时保持waterStep不跳步，使用nibble打包亮度
                _sendFullFrame(ble, mode: 0x02, color: colorCode,
                    brightness: _packBrightnessNibbles(_currentBrightness),
                    speed: _waterStep);
              } else {
                _sendFullFrame(ble, color: colorCode);
              }
            }
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isSelected ? color.withOpacity(0.8) : Colors.grey.withOpacity(0.3),
        foregroundColor: isSelected ? Colors.white : Colors.grey,
        side: BorderSide(
          color: isSelected ? color : Colors.transparent,
          width: 2,
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, size: 14),
            ),
          Text(label),
          const SizedBox(width: 4),
          Text(
            "0${colorCode.toRadixString(16).toUpperCase()}",
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  // 构建单个 LED 圆形开关按钮
  Widget _buildLedButton(bool enabled, int index, String label) {
    final isOn = _ledStates[index];
    final Color onColor;
    final Color accentColor;
    switch (_currentColor) {
      case 0x01:
        onColor = Colors.red;
        accentColor = Colors.redAccent;
        break;
      case 0x03:
        onColor = Colors.blue;
        accentColor = Colors.blueAccent;
        break;
      default: // 0x02 green
        onColor = Colors.green;
        accentColor = Colors.greenAccent;
        break;
    }
    final Color ledColor = isOn ? onColor : Colors.grey.withOpacity(0.2);
    final Color borderColor = isOn ? accentColor : Colors.grey;
    return GestureDetector(
      onTap: enabled
          ? () {
              _stopWaveBreathing();
              _stopWaterFlow();
              _stopChaseAnimation();
              setState(() {
                _activeMode = 0x01;
                _ledStates[index] = !isOn;
              });
              _sendLedMask(context.read<BleController>());
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ledColor,
          border: Border.all(color: borderColor, width: 2),
          boxShadow: isOn
              ? [
                  BoxShadow(
                    color: ledColor.withOpacity(0.5),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isOn ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // LED 物理位映射：UI 按钮 1~8 → FPGA led_data_in10 比特位
  // my_ws2812.v 映射: g_rgb_flat[0]←bit4, [1]←bit5, [2]←bit6, [3]←bit7,
  //                     g_rgb_flat[4]←bit3, [5]←bit2, [6]←bit1, [7]←bit0
  static const List<int> _ledBitPositions = [4, 5, 6, 7, 3, 2, 1, 0];

  // UI 按钮显示顺序：2×4 矩阵对齐物理硬件布局
  // Row 1 (从左到右): [4, 3, 2, 1], Row 2 (从左到右): [5, 6, 7, 8]
  static const List<int> _ledDisplayOrder = [3, 2, 1, 0, 4, 5, 6, 7];

  void _sendLedMask(BleController ble) {
    int mask = 0;
    for (int i = 0; i < 8; i++) {
      if (_ledStates[i]) {
        mask |= (1 << _ledBitPositions[i]);
      }
    }
    _sendFullFrame(ble, mode: 0x01, speed: mask);
  }

  // ================================================================
  // Mode 2 大环流水灯 — 双板 16 步 Grand Ring App-Streaming 引擎
  //
  // 路径 (16步):
  //   Step  0~ 7: Board 1 LED 1→2→3→4→5→6→7→8
  //   Step  8~15: Board 2 LED 1→2→3→4→8→7→6→5
  //   → 循环回 Step 0
  //
  // 发送策略: App 端 Timer 每 tick 发送 Mode 0x02 帧,
  //          Byte 4 = 当前步索引 (0~15), FPGA 组合逻辑直驱双板.
  //          Byte 3 = nibble 打包亮度 (高4=内群, 低4=外群, 同值).
  // ================================================================

  /// 启动大环流水灯流式发送
  void _startWaterFlow(BleController ble) {
    _stopWaterFlow();
    _stopWaveBreathing();
    _waterStep = 0;
    _onWaterTick(ble); // 立即发送第一帧
    _updateWaterSpeed(ble);
  }

  /// 停止大环流水灯并清理 Timer
  void _stopWaterFlow() {
    _waterTimer?.cancel();
    _waterTimer = null;
  }

  /// 每次 Timer tick: 发送当前步 → 推进 step → 重绘预览
  void _onWaterTick(BleController ble) {
    // Byte 3 nibble 打包：高4-bit = 内群, 低4-bit = 外群 (同值, 统一亮度)
    final packedBri = _packBrightnessNibbles(_currentBrightness);
    // Byte 4 = 当前步索引 (0~15)
    ble.sendProtocolCmd(0x02, _currentColor, packedBri, _waterStep);

    setState(() {
      _waterStep = (_waterStep + 1) % 16;
    });
  }

  /// 根据当前速度滑块重新设定 Timer 间隔 + 发送调速帧
  /// Speed 1=60ms/step (极速), Speed 15=900ms/step (最缓)
  void _updateWaterSpeed(BleController ble) {
    _waterTimer?.cancel();
    final ms = (_currentSpeed * 60).toInt().clamp(60, 900);
    _waterTimer =
        Timer.periodic(Duration(milliseconds: ms), (_) => _onWaterTick(ble));
  }

  /// 将 0~255 亮度值打包为 nibble 对称字节 (高4=低4, 用于 Mode 1/2)
  int _packBrightnessNibbles(double brightness) {
    final val4 = (brightness / 255.0 * 15.0).round().clamp(0, 15);
    return (val4 << 4) | val4;
  }

  /// 判断指定 LED 在大环流水的当前步是否点亮
  /// [boardIndex] 0=Board 1, 1=Board 2
  /// [ledIndex] 0~7 对应 LED 1~8
  bool _isWaterLedActive(int boardIndex, int ledIndex) {
    final step = _waterStep;
    if (boardIndex == 0) {
      // Board 1: step 0~7 → LED 1(0)→2(1)→3(2)→4(3)→5(4)→6(5)→7(6)→8(7)
      return (step <= 7) ? ledIndex == step : false;
    } else {
      // Board 2: step 8~11 → LED 1(0)→2(1)→3(2)→4(3)
      //           step 12~15 → LED 8(7)→7(6)→6(5)→5(4)
      if (step >= 8 && step <= 11) return ledIndex == (step - 8);
      if (step >= 12) return ledIndex == (19 - step);
      return false;
    }
  }

  /// 生成大环流水当前步骤的描述文本
  String _buildWaterStepLabel() {
    final step = _waterStep;
    String board;
    int led;
    if (step <= 7) {
      board = 'B1';
      led = step + 1;
    } else if (step <= 11) {
      board = 'B2';
      led = step - 7;
    } else {
      board = 'B2';
      led = 20 - step;
    }
    return 'Step $_waterStep/15  ●  $board LED$led 点亮';
  }

  /// 构建 Mode 2 大环流水指定 Board 的 2×4 LED 预览网格
  Widget _buildWaterBoardPreview(
      String title, Color accentColor, int boardIndex) {
    final flowColor = _getCurrentWaveColor();
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: accentColor,
          ),
        ),
        const SizedBox(height: 6),
        // Row 1: LEDs 4,3,2,1 (indices 3,2,1,0) — 对应物理 Btn4~Btn1
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [3, 2, 1, 0].map((i) {
            final active = _isWaterLedActive(boardIndex, i);
            return Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    active ? flowColor : Colors.grey.withOpacity(0.15),
                border: Border.all(
                  color: active
                      ? flowColor.withOpacity(0.8)
                      : Colors.grey.withOpacity(0.3),
                  width: active ? 2.5 : 1,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                            color: flowColor.withOpacity(0.6),
                            blurRadius: 5)
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: active
                        ? Colors.white
                        : Colors.grey.withOpacity(0.5),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 2),
        // Row 2: LEDs 5,6,7,8 (indices 4,5,6,7) — 对应物理 Btn5~Btn8
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [4, 5, 6, 7].map((i) {
            final active = _isWaterLedActive(boardIndex, i);
            return Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    active ? flowColor : Colors.grey.withOpacity(0.15),
                border: Border.all(
                  color: active
                      ? flowColor.withOpacity(0.8)
                      : Colors.grey.withOpacity(0.3),
                  width: active ? 2.5 : 1,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                            color: flowColor.withOpacity(0.6),
                            blurRadius: 5)
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: active
                        ? Colors.white
                        : Colors.grey.withOpacity(0.5),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ================================================================
  // Mode 3 中心对称波浪呼吸灯 — nibble 分拆亮度调制算法
  //
  // 核心思路：每 tick 发送单帧 Mode 0x03，
  //   Byte 3 高 4-bit = 内群亮度 (0~15)，低 4-bit = 外群亮度 (0~15)
  //   FPGA my_ws2812 按 LED 分组使用对应 nibble 驱动脉宽，
  //   单帧无竞态，内/外 8 灯同时以不同亮度呼吸。
  // ================================================================

  /// 启动波浪呼吸灯
  void _startWaveBreathing(BleController ble) {
    _stopWaveBreathing();
    _stopWaterFlow();
    _wavePhase = 0.0;
    _innerIntensity = 0.0;
    _outerIntensity = 0.0;
    _innerBrightnessValue = 0;
    _outerBrightnessValue = 0;
    _onWaveTick(ble); // 立即发送第一组帧
    _updateWaveInterval(ble);
  }

  /// 停止波浪呼吸灯并清理资源
  void _stopWaveBreathing() {
    _waveTimer?.cancel();
    _waveTimer = null;
  }

  /// 每次定时器触发：计算正弦波 4-bit 亮度 → nibble 打包 → 发送单帧 Mode 0x03
  ///   Byte 3 = (inner_4bit << 4) | outer_4bit,  Byte 4 = speed
  ///   单帧取代旧版双帧竞态，内/外群亮度独立且无闪烁
  void _onWaveTick(BleController ble) {
    final phaseRad = _wavePhase * 2 * pi;

    // 内群亮度 = cos² 映射到 [0, 15] 4-bit（相位 0 时峰值 15，相位 0.5 时谷值 0）
    final innerRaw = (cos(phaseRad) + 1.0) / 2.0; // [0, 1]
    final inner4 = (innerRaw * 15.0).round().clamp(0, 15);

    // 外群亮度 = 反相（相位差 π），内群亮时外群暗，反之亦然
    final outerRaw = (cos(phaseRad + pi) + 1.0) / 2.0; // [0, 1]
    final outer4 = (outerRaw * 15.0).round().clamp(0, 15);

    // ★ nibble 打包：高 4-bit = 内群，低 4-bit = 外群 → 单帧发送 ★
    final packedBrightness = (inner4 << 4) | outer4;
    ble.sendProtocolCmd(0x03, _currentColor, packedBrightness, _currentSpeed.toInt());

    setState(() {
      _innerIntensity = innerRaw;
      _outerIntensity = outerRaw;
      _innerBrightnessValue = inner4; // 4-bit 实际值 (0~15)
      _outerBrightnessValue = outer4;

      // 推进相位：step=0.03，约 33 tick 完成一个完整呼吸周期
      _wavePhase += 0.03;
      if (_wavePhase >= 1.0) _wavePhase -= 1.0;
    });
  }

  /// 根据滑块值重新设定波浪定时器间隔
  /// Speed 1（极速）= 60ms 间隔, Speed 15（最缓）= 900ms 间隔
  void _updateWaveInterval(BleController ble) {
    _waveTimer?.cancel();
    final ms = (_currentSpeed * 60).toInt().clamp(60, 900);
    _waveTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _onWaveTick(ble));
  }

  /// 构建波浪可视化预览中的单个列指示器（显示实际亮度值）
  Widget _buildWaveColumn(String label, double intensity, int brightnessValue) {
    final waveColor = _getCurrentWaveColor();
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 40,
          height: 56,
          decoration: BoxDecoration(
            color: waveColor.withOpacity(intensity.clamp(0.0, 1.0)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: waveColor.withOpacity(0.5),
              width: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        Text(
          "$brightnessValue/15",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: waveColor.withOpacity(0.8),
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  /// 获取当前全局颜色对应的 Flutter Color
  Color _getCurrentWaveColor() {
    switch (_currentColor) {
      case 0x01:
        return Colors.red;
      case 0x03:
        return Colors.blue;
      default: // 0x02
        return Colors.green;
    }
  }

  // ================================================================
  // Mode 4 S型往返追逐 — 双板联动画引擎
  //
  // 追逐路径 (16步):
  //   Step  0~ 3: Board 1 LED 4→3→2→1
  //   Step  4~11: Board 2 LED 1→2→3→4→5→6→7→8
  //   Step 12~15: Board 1 LED 8→7→6→5
  //   → 循环回 Step 0
  //
  // 发送策略: 启动/调速/换色时发送单帧 Mode 0x04 到 FPGA,
  //          FPGA 自主动画，Flutter 本地 Timer 驱动预览
  // ================================================================

  /// 判断指定 LED 在追逐的当前步是否点亮
  /// [boardIndex] 0=Board 1, 1=Board 2
  /// [ledIndex] 0~7 对应 LED 1~8
  bool _isChaseLedActive(int boardIndex, int ledIndex) {
    final step = _chaseStep;
    if (boardIndex == 0) {
      // Board 1: step 0~3 → LED 4(3)→3(2)→2(1)→1(0)
      if (step <= 3) return ledIndex == (3 - step);
      // Board 1: step 12~15 → LED 8(7)→7(6)→6(5)→5(4)
      if (step >= 12) return ledIndex == (19 - step);
      return false;
    } else {
      // Board 2: step 4~11 → LED 1(0)→2(1)→...→8(7)
      if (step >= 4 && step <= 11) return ledIndex == (step - 4);
      return false;
    }
  }

  /// 生成当前追逐步骤的描述文本
  String _buildChaseStepLabel() {
    final step = _chaseStep;
    String board;
    int led;
    if (step <= 3) {
      board = 'B1'; led = 4 - step;
    } else if (step <= 11) {
      board = 'B2'; led = step - 3;
    } else {
      board = 'B1'; led = 20 - step;
    }
    return 'Step $_chaseStep/15  ●  $board LED$led 点亮';
  }

  /// 构建单个 Board 的 2×4 LED 预览网格
  Widget _buildBoardPreview(String title, Color accentColor, int boardIndex) {
    final chaseColor = _getCurrentWaveColor();
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: accentColor,
          ),
        ),
        const SizedBox(height: 6),
        // Row 1: LEDs 4,3,2,1 (indices 3,2,1,0)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [3, 2, 1, 0].map((i) {
            final active = _isChaseLedActive(boardIndex, i);
            return Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? chaseColor : Colors.grey.withOpacity(0.15),
                border: Border.all(
                  color: active ? chaseColor.withOpacity(0.8) : Colors.grey.withOpacity(0.3),
                  width: active ? 2.5 : 1,
                ),
                boxShadow: active
                    ? [BoxShadow(color: chaseColor.withOpacity(0.6), blurRadius: 5)]
                    : null,
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.white : Colors.grey.withOpacity(0.5),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 2),
        // Row 2: LEDs 5,6,7,8 (indices 4,5,6,7)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [4, 5, 6, 7].map((i) {
            final active = _isChaseLedActive(boardIndex, i);
            return Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? chaseColor : Colors.grey.withOpacity(0.15),
                border: Border.all(
                  color: active ? chaseColor.withOpacity(0.8) : Colors.grey.withOpacity(0.3),
                  width: active ? 2.5 : 1,
                ),
                boxShadow: active
                    ? [BoxShadow(color: chaseColor.withOpacity(0.6), blurRadius: 5)]
                    : null,
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.white : Colors.grey.withOpacity(0.5),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 启动 S 型追逐
  void _startChaseAnimation(BleController ble) {
    _stopChaseAnimation();
    _stopWaveBreathing();
    _stopWaterFlow();
    _chaseStep = 0;
    // 发送启动帧到 FPGA
    _sendChaseFrame(ble);
    // 启动本地预览 Timer
    _updateChaseSpeed(ble);
  }

  /// 停止 S 型追逐
  void _stopChaseAnimation() {
    _chaseTimer?.cancel();
    _chaseTimer = null;
  }

  /// 每次 Timer tick: 推进追逐步 + 重绘预览
  /// FPGA 自主动画，Flutter 本地预览；每16步重发一次帧防止BLE丢帧
  void _onChaseTick(BleController ble) {
    setState(() {
      _chaseStep = (_chaseStep + 1) % 16;
    });
    // 心跳保活：每完整一圈(step=0)重发一次，防止FPGA因丢帧退出Mode 4
    if (_chaseStep == 0) {
      _sendChaseFrame(ble);
    }
  }

  /// 根据当前速度滑块更新 Timer 间隔 + 发送调速帧
  /// Speed 1=60ms/step, Speed 15=900ms/step
  void _updateChaseSpeed(BleController ble) {
    _chaseTimer?.cancel();
    final ms = (_currentSpeed * 60).toInt().clamp(60, 900);
    _chaseTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _onChaseTick(ble));
    // 发送调速帧到 FPGA
    _sendChaseFrame(ble);
  }

  /// 发送 Mode 0x04 追逐帧到 FPGA
  void _sendChaseFrame(BleController ble) {
    ble.sendProtocolCmd(0x04, _currentColor, _currentBrightness.toInt(), _currentSpeed.toInt());
  }

  @override
  void dispose() {
    _stopWaveBreathing();
    _stopWaterFlow();
    _stopChaseAnimation();
    super.dispose();
  }
}
