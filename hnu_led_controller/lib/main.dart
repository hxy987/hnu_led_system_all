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
  double _currentSpeed = 10.0; // 流水灯默认速度参数

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

              // ----------------- 3. FPGA 指令控制面板 -----------------
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

                // 模式 1：静态颜色快捷点亮
                const Text(
                  "模式一：APP 静态控色",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildColorButton(
                      context,
                      "纯红",
                      Colors.red,
                      0x0F,
                    ), // 十六进制掩码参数
                    _buildColorButton(context, "纯绿", Colors.green, 0xF0),
                    _buildColorButton(context, "全亮", Colors.white, 0xFF),
                    _buildColorButton(context, "全灭", Colors.grey, 0x00),
                  ],
                ),
                const SizedBox(height: 24),

                // 模式 2：自动流水灯控制
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
                          onPressed: () => bleWatch.sendProtocolCmd(
                            0x02,
                            _currentSpeed.toInt(),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            minimumSize: const Size.fromHeight(45),
                          ),
                          child: const Text("启动自动流水灯"),
                        ),
                        Slider(
                          value: _currentSpeed,
                          min: 1.0,
                          max: 30.0,
                          divisions: 29,
                          label: "速度阻尼: ${_currentSpeed.toInt()}",
                          onChanged: (value) {
                            setState(() {
                              _currentSpeed = value;
                            });
                            // 拖动滑动条时，实时向 FPGA 喷射新的速度阻尼参数
                            bleWatch.sendProtocolCmd(
                              0x02,
                              _currentSpeed.toInt(),
                            );
                          },
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

                // 模式 3：数码管四进制级联控色
                const Text(
                  "模式三：高级组控效果",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => bleWatch.sendProtocolCmd(0x03, 0x00),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    minimumSize: const Size.fromHeight(45),
                  ),
                  child: const Text("启动数码管多色级联滚动"),
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

  // 辅助构建静态控色按钮
  Widget _buildColorButton(
    BuildContext context,
    String label,
    Color color,
    int maskParam,
  ) {
    return ElevatedButton(
      onPressed: () {
        context.read<BleController>().sendProtocolCmd(0x01, maskParam);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.8),
        foregroundColor: Colors.black,
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
      child: Text(label),
    );
  }
}
