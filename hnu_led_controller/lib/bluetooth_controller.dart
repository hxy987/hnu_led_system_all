import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleController extends ChangeNotifier {
  BluetoothDevice? connectedDevice; // 当前连接成功的蓝牙设备
  BluetoothCharacteristic? txChar; // 专门负责写数据的特征值通道
  BluetoothCharacteristic? rxChar; // 专门负责接收通知的特征值通道（调试用）
  bool isScanning = false; // 蓝牙是否正在扫描
  bool isServicesReady = false; // 服务发现是否完成，TX特征值是否就绪
  List<ScanResult> scanResults = []; // 扫描到的设备列表（已包含信号排序）
  String feedbackMessage = "等待硬件反馈..."; // 接收FPGA传回的消息
  String statusMessage = "未连接"; // 当前蓝牙状态详细描述
  String lastError = ""; // 最近的错误信息

  // 1. 开始扫描附近的蓝牙设备（加入信号强度自动排序）
  void startScan() async {
    if (isScanning) return;
    isScanning = true;
    scanResults.clear();
    statusMessage = "正在扫描BLE设备...";
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
    if (scanResults.isEmpty) {
      statusMessage = "扫描完成：未发现蓝牙设备";
    } else {
      statusMessage = "扫描完成：发现${scanResults.length}个设备";
    }
    notifyListeners();
  }

  // 2. 连接指定的蓝牙设备 (用户在界面上点击哪个卡片就连接哪个)
  void connectToDevice(BluetoothDevice device) async {
    try {
      statusMessage = "正在连接 ${device.platformName.isEmpty ? '未知设备' : device.platformName}...";
      notifyListeners();

      await device.connect();
      connectedDevice = device;
      statusMessage = "已连接！正在发现服务和特征值...";
      notifyListeners();

      // ============================================================
      // 【诊断】：打印所有服务和特征值的详细信息
      // ============================================================
      List<BluetoothService> services = await device.discoverServices();
      debugPrint("══════════════════════════════════════");
      debugPrint("🔍 开始扫描 BLE 服务和特征值...");
      debugPrint("   设备名称: ${device.platformName}");
      debugPrint("   设备地址: ${device.remoteId.str}");
      debugPrint("   发现 ${services.length} 个服务");
      debugPrint("──────────────────────────────────────");

      bool foundWrite = false;
      bool foundNotify = false;
      String writeCharInfo = "未找到";
      String notifyCharInfo = "未找到";

      for (var service in services) {
        debugPrint("  📦 服务 UUID: ${service.uuid}");
        for (var characteristic in service.characteristics) {
          // 构建属性列表字符串
          List<String> props = [];
          if (characteristic.properties.broadcast) props.add("广播");
          if (characteristic.properties.read) props.add("读");
          if (characteristic.properties.write) props.add("写(WR)");
          if (characteristic.properties.writeWithoutResponse) props.add("写(WNR)");
          if (characteristic.properties.notify) props.add("通知");
          if (characteristic.properties.indicate) props.add("指示");

          debugPrint("    📌 特征值 UUID: ${characteristic.uuid}");
          debugPrint("       属性: ${props.join(', ')}");
          debugPrint("       原始值: ${characteristic.properties}");

          // 锁定具有 WRITE 或 WRITE_WITHOUT_RESPONSE 属性的特征值发射大动脉
          // BLE 透传模块(如HM-10/JDY-31)通常只用 WriteWithoutResponse
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            // 【修复】：如果之前已有更合适的（支持WR），不覆盖
            if (txChar == null ||
                (characteristic.properties.write &&
                 !txChar!.properties.write)) {
              txChar = characteristic;
            }
            foundWrite = true;
            writeCharInfo = characteristic.uuid.str;
            debugPrint("       ✅ 绑定为 TX 通道 (写入)!");
          }

          // 查找具有 NOTIFY 属性的特征值，接收 FPGA 传回的数据
          if (characteristic.properties.notify) {
            rxChar = characteristic;
            foundNotify = true;
            notifyCharInfo = characteristic.uuid.str;
            await characteristic.setNotifyValue(true);
            debugPrint("       ✅ 绑定为 RX 通道 (通知)!");

            characteristic.lastValueStream.listen((value) {
              debugPrint("📥 收到硬件数据: $value (长度=${value.length})");
              if (value.isNotEmpty && value[0] == 0xC3) {
                // 对应仲裁器反馈
                feedbackMessage = "✅ 收到FPGA按键反馈: 0xC3";
                statusMessage = "通信正常：双向收发验证通过";
                notifyListeners();
              } else if (value.isNotEmpty) {
                feedbackMessage = "收到数据: $value";
                notifyListeners();
              }
            });
          }
        } // end for characteristic
      } // end for service

      debugPrint("──────────────────────────────────────");
      debugPrint("📊 诊断结果：");
      debugPrint("   TX 写通道状态 : ${foundWrite ? '✅ 已找到' : '❌ 未找到!'}");
      debugPrint("   TX UUID       : $writeCharInfo");
      debugPrint("   RX 通知通道   : ${foundNotify ? '✅ 已找到' : '❌ 未找到!'}");
      debugPrint("   RX UUID       : $notifyCharInfo");
      debugPrint("══════════════════════════════════════");

      // 更新UI状态
      if (!foundWrite) {
        isServicesReady = false;
        statusMessage = "❌ 错误：未找到可写特征值！请检查蓝牙模块";
        lastError = "未找到 WRITE 或 WRITE_WITHOUT_RESPONSE 特征值。请查看调试日志中的服务和特征值列表。";
      } else {
        isServicesReady = true;
        statusMessage = "✅ 通信就绪：可以发送控制指令";
      }

      if (!foundNotify) {
        debugPrint("⚠️ 警告：未找到 NOTIFY 特征值，将无法接收硬件反馈");
      }

      notifyListeners();

    } catch (e) {
      debugPrint("❌ 连接失败: $e");
      statusMessage = "❌ 连接失败: $e";
      lastError = e.toString();
      isServicesReady = false;
      connectedDevice = null;
      txChar = null;
      rxChar = null;
      notifyListeners();
    }
  }

  // 3. 封装发送自定义 3 字节协议数据包的代码
  void sendProtocolCmd(int mode, int param) async {
    // ============================================================
    // 【诊断日志】打印发送前的所有关键状态
    // ============================================================
    debugPrint("══════════════════════════════════════");
    debugPrint("📤 用户触发发送指令:");
    debugPrint("   mode  = 0x${mode.toRadixString(16).padLeft(2, '0')}");
    debugPrint("   param = 0x${param.toRadixString(16).padLeft(2, '0')}");
    debugPrint("   connectedDevice = ${connectedDevice != null ? '已连接' : 'NULL!'}");
    debugPrint("   txChar          = ${txChar != null ? txChar!.uuid.str : 'NULL!'}");
    debugPrint("   isServicesReady = $isServicesReady");

    // 检查1：设备是否已连接
    if (connectedDevice == null) {
      debugPrint("❌ 发送失败：设备未连接！");
      lastError = "发送失败：设备未连接";
      statusMessage = "❌ 发送失败：设备未连接";
      notifyListeners();
      return;
    }

    // 检查2：TX 特征值是否已绑定
    if (txChar == null) {
      debugPrint("❌ 发送失败：txChar 为 null！未找到可写的蓝牙特征值！");
      debugPrint("   请检查蓝牙模块是否支持 BLE UART 透传服务。");
      debugPrint("   常见问题：");
      debugPrint("   1. 蓝牙模块型号不匹配（需要 BLE 4.0+，如 HM-10/JDY-31）");
      debugPrint("   2. 蓝牙模块 AT 配置异常，未开启 UART 透传模式");
      debugPrint("   3. flutter_blue_plus 未发现 WriteWithoutResponse 特征值");
      lastError = "发送失败：txChar 为 null！未找到可写蓝牙特征值。请断开重连后查看调试日志。";
      statusMessage = "❌ 发送通道未就绪——请断开蓝牙并重新连接";
      notifyListeners();
      return;
    }

    // 检查3：特征值是否支持写操作
    if (!txChar!.properties.write && !txChar!.properties.writeWithoutResponse) {
      debugPrint("❌ 发送失败：绑定的特征值不支持写操作！");
      debugPrint("   当前属性: ${txChar!.properties}");
      lastError = "发送失败：特征值不支持写操作";
      statusMessage = "❌ 发送失败：特征值权限不足";
      notifyListeners();
      return;
    }

    List<int> cmdFrame = [0x5A, mode, param];
    debugPrint("   📡 协议帧: $cmdFrame");
    debugPrint("   📡 十六进制: [0x${cmdFrame[0].toRadixString(16).padLeft(2, '0')}, "
        "0x${cmdFrame[1].toRadixString(16).padLeft(2, '0')}, "
        "0x${cmdFrame[2].toRadixString(16).padLeft(2, '0')}]");

    // 确定写模式
    bool useWithoutResponse = txChar!.properties.writeWithoutResponse;
    debugPrint("   📡 写模式: ${useWithoutResponse ? 'WriteWithoutResponse' : 'WriteWithResponse'}");

    try {
      await txChar!.write(cmdFrame, withoutResponse: useWithoutResponse);
      debugPrint("✅ 数据已提交到蓝牙协议栈: $cmdFrame");
      debugPrint("══════════════════════════════════════");
      feedbackMessage = "已发送: [${cmdFrame[0]}, ${cmdFrame[1]}, ${cmdFrame[2]}]";
      statusMessage = "✅ 指令已发送";
      lastError = "";
      notifyListeners();
    } catch (e) {
      debugPrint("❌ BLE写操作异常: $e");
      debugPrint("══════════════════════════════════════");
      lastError = "BLE写操作异常: $e";
      statusMessage = "❌ 发送异常: $e";
      notifyListeners();

      // 【修复】：如果 WriteWithoutResponse 失败，尝试 WriteWithResponse
      if (useWithoutResponse) {
        try {
          debugPrint("🔄 尝试回退到 WriteWithResponse...");
          await txChar!.write(cmdFrame, withoutResponse: false);
          debugPrint("✅ WriteWithResponse 回退成功!");
          debugPrint("══════════════════════════════════════");
          statusMessage = "✅ 指令已发送(WWR回退)";
          lastError = "";
          notifyListeners();
          return;
        } catch (e2) {
          debugPrint("❌ WriteWithResponse 回退也失败: $e2");
          debugPrint("══════════════════════════════════════");
          lastError = "所有写模式均失败: $e2";
          statusMessage = "❌ 发送彻底失败";
          notifyListeners();
        }
      }
    }
  }

  // 断开连接
  void disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      connectedDevice = null;
      txChar = null;
      rxChar = null;
      isServicesReady = false;
      feedbackMessage = "等待硬件反馈...";
      statusMessage = "未连接";
      lastError = "";
      notifyListeners();
    }
  }
}
