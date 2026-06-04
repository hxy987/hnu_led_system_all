import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleController extends ChangeNotifier {
  BluetoothDevice? connectedDevice; // 当前连接成功的蓝牙设备
  BluetoothCharacteristic? txChar; // 专门负责写数据的特征值通道
  bool isScanning = false; // 蓝牙是否正在扫描
  List<ScanResult> scanResults = []; // 扫描到的设备列表（已包含信号排序）
  String feedbackMessage = "等待硬件反馈..."; // 接收FPGA传回的消息

  // 1. 开始扫描附近的蓝牙设备（加入信号强度自动排序）
  void startScan() async {
    if (isScanning) return;
    isScanning = true;
    scanResults.clear();
    notifyListeners();

    // 开始扫描，5秒后自动停止
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    // 监听扫描结果
    FlutterBluePlus.scanResults.listen((results) {
      // 【核心魔法】：根据 RSSI 信号强度从大到小排序（负数越接近0越大，即信号越强越靠前）
      results.sort((a, b) => b.rssi.compareTo(a.rssi));
      scanResults = results;
      notifyListeners(); // 实时刷新界面，最强信号会自动冒泡到最上面
    });

    await Future.delayed(const Duration(seconds: 5));
    isScanning = false;
    notifyListeners();
  }

  // 2. 连接指定的蓝牙设备 (用户在界面上点击哪个卡片就连接哪个)
  void connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      connectedDevice = device;
      notifyListeners();

      // 连接成功后，搜寻物理芯片开放的串口透传通道
      List<BluetoothService> services = await device.discoverServices();
      bool foundWrite = false;
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          // 锁定具有 WRITE 或 WRITE_WITHOUT_RESPONSE 属性的特征值发射大动脉
          // BLE 透传模块(如HM-10/JDY-31)通常只用 WriteWithoutResponse
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            txChar = characteristic;
            foundWrite = true;
            debugPrint("✅ 成功绑定发送通道: ${characteristic.uuid}");
          }

          // 监听具有 NOTIFY 属性的特征值，接收 FPGA 传回的 0xC3 码
          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty && value[0] == 0xC3) {
                // 对应仲裁器反馈
                feedbackMessage = "收到FPGA按键反馈: 0xC3";
                notifyListeners();
              }
            });
          }
        }
      }
      if (!foundWrite) {
        debugPrint("❌ 错误：未找到任何可写的特征值！请检查蓝牙模块是否支持串口透传。");
      }
    } catch (e) {
      debugPrint("连接失败: $e");
    }
  }

  // 3. 封装发送自定义 3 字节协议数据包的代码
  void sendProtocolCmd(int mode, int param) async {
    if (txChar == null) return;
    List<int> cmdFrame = [0x5A, mode, param];
    // 透传模块使用 WriteWithoutResponse 更可靠，无需GATT ACK
    await txChar!.write(cmdFrame, withoutResponse: true);
    debugPrint("📤 APP发射数据: $cmdFrame");
  }

  // 断开连接
  void disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      connectedDevice = null;
      txChar = null;
      feedbackMessage = "等待硬件反馈...";
      notifyListeners();
    }
  }
}
