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
                                  _sendFullFrame(bleWatch,
                                      brightness: _currentBrightness.toInt());
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
                // 模式二：自动流水灯特效
                // ================================================================
                const Text(
                  "模式二：自动流水灯特效",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Card(
                  color: const Color(0xFF1E1E1E),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        ElevatedButton(
                          onPressed: bleWatch.isServicesReady
                              ? () {
                                  setState(() => _activeMode = 0x02);
                                  _sendFullFrame(bleWatch,
                                      mode: 0x02,
                                      speed: _currentSpeed.toInt());
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            minimumSize: const Size.fromHeight(45),
                          ),
                          child: const Text("启动自动流水灯"),
                        ),
                        Slider(
                          value: _currentSpeed,
                          min: 1.0,
                          max: 255.0,
                          divisions: 254,
                          label: "速度阻尼: ${_currentSpeed.toInt()}",
                          activeColor: bleWatch.isServicesReady
                              ? Colors.teal
                              : Colors.grey,
                          onChanged: bleWatch.isServicesReady
                              ? (value) {
                                  setState(() {
                                    _currentSpeed = value;
                                  });
                                  _sendFullFrame(bleWatch,
                                      mode: 0x02,
                                      speed: _currentSpeed.toInt());
                                }
                              : null,
                        ),
                        const Text(
                          "提示：滑动条数值越小，FPGA计数器溢出越快，流水速度越炫酷！",
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ================================================================
                // 模式三：生命体征呼吸灯 (V2 重命名 + 心跳算法)
                // ================================================================
                const Text(
                  "模式三：生命体征呼吸灯",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  "模拟人体心跳节律 — 收缩快速点亮 → 舒张缓慢衰减",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: bleWatch.isServicesReady
                      ? () {
                          setState(() => _activeMode = 0x03);
                          _sendFullFrame(bleWatch,
                              mode: 0x03,
                              speed: _currentSpeed.toInt());
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    minimumSize: const Size.fromHeight(45),
                  ),
                  child: const Text("启动心跳呼吸灯"),
                ),
                const SizedBox(height: 8),
                if (_activeMode == 0x03)
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.favorite,
                                  color: Colors.pinkAccent, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                "心跳节拍调节",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Spacer(),
                              Text(
                                "节拍: ${_currentSpeed.toInt()}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.pinkAccent,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _currentSpeed,
                            min: 1.0,
                            max: 255.0,
                            divisions: 254,
                            label: "节拍: ${_currentSpeed.toInt()}",
                            activeColor: bleWatch.isServicesReady
                                ? Colors.pinkAccent
                                : Colors.grey,
                            onChanged: bleWatch.isServicesReady
                                ? (value) {
                                    setState(() {
                                      _currentSpeed = value;
                                    });
                                    _sendFullFrame(bleWatch,
                                        mode: 0x03,
                                        speed: _currentSpeed.toInt());
                                  }
                                : null,
                          ),
                          const Text(
                            "提示：数值越小节奏越快，模拟真实心跳「咚-咚」律动",
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
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
              _sendFullFrame(ble, color: colorCode);
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
}
