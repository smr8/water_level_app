import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MaterialApp(home: WaterLevelApp()));
}

class WaterLevelApp extends StatefulWidget {
  const WaterLevelApp({super.key});

  @override
  State<WaterLevelApp> createState() => _WaterLevelAppState();
}

class _WaterLevelAppState extends State<WaterLevelApp> {
  // 核心变量
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  
  // 状态与日志
  bool _isScanning = false;
  bool _isConnected = false;
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  
  // 输入控制器
  final TextEditingController _paramController = TextEditingController();

  // 定义目标 UUID (来自 X-E45x 说明书)
  final String serviceUuid = "fff0"; 
  final String notifyUuid = "fff1"; // 接收 (APP <- 设备)
  final String writeUuid = "fff2";  // 发送 (APP -> 设备)

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  // 1. 权限检查
  Future<void> _checkPermissions() async {
    if (await Permission.location.request().isGranted &&
        await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted) {
      // 权限已获取
    }
  }

  // 2. 扫描设备
  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    // 开始扫描，超时4秒
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    
    // 监听扫描结果
    var subscription = FlutterBluePlus.scanResults.listen((results) {
        // 这里可以添加自动连接逻辑，或者只在UI显示列表
    });

    FlutterBluePlus.isScanning.listen((state) {
      if (mounted) setState(() => _isScanning = state);
    });
  }

  // 3. 连接设备并寻找服务
  Future<void> _connectToDevice(BluetoothDevice device) async {
    _addLog("正在连接: ${device.platformName}...");
    try {
      await device.connect();
      setState(() {
        _connectedDevice = device;
        _isConnected = true;
      });
      _addLog("连接成功，正在发现服务...");

      // 发现服务
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        // 匹配服务 UUID (忽略大小写)
        if (service.uuid.toString().contains(serviceUuid)) {
          _addLog("找到服务: FFF0");
          for (var characteristic in service.characteristics) {
            // 找到写入特征值
            if (characteristic.uuid.toString().contains(writeUuid)) {
              _writeCharacteristic = characteristic;
              _addLog("找到写入特征: FFF2");
            }
            // 找到通知特征值 (接收数据)
            if (characteristic.uuid.toString().contains(notifyUuid)) {
              _notifyCharacteristic = characteristic;
              _addLog("找到通知特征: FFF1");
              
              // 开启通知订阅
              await characteristic.setNotifyValue(true);
              characteristic.lastValueStream.listen((value) {
                // 处理接收到的数据 (字节转字符串)
                String response = utf8.decode(value); 
                _addLog("收到: $response", isError: false, isRx: true);
              });
              _addLog("监听开启成功");
            }
          }
        }
      }
    } catch (e) {
      _addLog("连接失败: $e", isError: true);
    }
  }

  // 4. 断开连接
  Future<void> _disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      setState(() {
        _connectedDevice = null;
        _isConnected = false;
        _writeCharacteristic = null;
        _notifyCharacteristic = null;
      });
      _addLog("已断开连接");
    }
  }

  // 5. 发送命令核心函数
  Future<void> _sendCommand(String cmd) async {
    if (_writeCharacteristic == null) {
      _addLog("错误: 未连接或未找到写入特征", isError: true);
      return;
    }

    try {
      // 1. 加上 \r\n，保证设备能识别结束符
      String finalCmd = "$cmd\r\n"; 
      
      _addLog("发送: $finalCmd");

      // 2. 关键修改：添加 withoutResponse: true
      // 说明书规定 FFF2 是 "Write without response"
      await _writeCharacteristic!.write(
        utf8.encode(finalCmd), 
        withoutResponse: true // <--- 必须加这一句！
      );
      
    } catch (e) {
      _addLog("发送失败: $e", isError: true);
    }
  }


  // 辅助：添加日志
  void _addLog(String msg, {bool isError = false, bool isRx = false}) {
    String time = "${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}";
    String prefix = isRx ? "⬇️" : (isError ? "❌" : "ℹ️");
    setState(() {
      _logs.add("$time $prefix $msg");
    });
    // 自动滚动到底部
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("FMCW50 水位计助手"),
        actions: [
          if (_isConnected)
            IconButton(icon: const Icon(Icons.bluetooth_disabled), onPressed: _disconnect)
        ],
      ),
      body: Column(
        children: [
          // 顶部：扫描区域 (未连接时显示)
          if (!_isConnected)
            Expanded(
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _isScanning ? null : _startScan,
                    child: Text(_isScanning ? "扫描中..." : "扫描蓝牙设备"),
                  ),
                  Expanded(
                    child: StreamBuilder<List<ScanResult>>(
                      stream: FlutterBluePlus.scanResults,
                      builder: (c, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();
                        return ListView(
                          children: snapshot.data!.map((r) => ListTile(
                            title: Text(r.device.platformName.isNotEmpty ? r.device.platformName : "未知设备"),
                            subtitle: Text(r.device.remoteId.toString()),
                            trailing: ElevatedButton(
                              child: const Text("连接"),
                              onPressed: () => _connectToDevice(r.device),
                            ),
                          )).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // 已连接：操作面板
          if (_isConnected) ...[
            // 1. 日志显示区域
            Expanded(
              flex: 4,
              child: Container(
                color: Colors.black12,
                child: ListView.builder(
                  controller: _logScrollController,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(_logs[index], style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ),
            
            // 2. 常用查询按钮区 (基于说明书)
            const Divider(),
            const Text("常用查询 (默认地址 001)"),
            Wrap(
              spacing: 10,
              children: [
                ActionChip(
                  label: const Text("读取数据 (DSWJ)"),
                  onPressed: () => _sendCommand("DSWJ-001:"), // 说明书 4.1
                ),
                ActionChip(
                  label: const Text("查发射功率 (GLSZ)"),
                  onPressed: () => _sendCommand("GLSZ-001:"), // 说明书 4.1
                ),
                ActionChip(
                  label: const Text("查版本 (VER)"),
                  onPressed: () => _sendCommand("AT+VER\r\n"), // 蓝牙模块指令
                ),
              ],
            ),

            // 3. 参数写入区
            const Divider(),
            const Text("参数设置"),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  // 下拉选择命令头
                  DropdownMenu<String>(
                    initialSelection: "GLSZ",
                    label: const Text("命令"),
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: "GLSZ", label: "功率设置 (GLSZ)"),
                      DropdownMenuEntry(value: "SWJZ", label: "水位校正 (SWJZ)"),
                      DropdownMenuEntry(value: "LCXZ", label: "量程选择 (LCXZ)"),
                      DropdownMenuEntry(value: "PJCS", label: "平均次数 (PJCS)"),
                    ],
                    onSelected: (value) {
                      // 这里可以用变量存起来，为了演示简化处理
                    },
                  ),
                  const SizedBox(width: 10),
                  // 参数输入框
                  Expanded(
                    child: TextField(
                      controller: _paramController,
                      decoration: const InputDecoration(
                        labelText: "参数值 (如 0031)",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 发送按钮
                  ElevatedButton(
                    onPressed: () {
                      // 组合命令：命令头-地址:参数
                      // 例如：GLSZ-001:0031
                      String cmdHeader = "GLSZ"; // 这里应该取下拉框的值，简化写死为GLSZ演示
                      String val = _paramController.text;
                      if (val.isEmpty) return;
                      _sendCommand("$cmdHeader-001:$val");
                    },
                    child: const Text("写入"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
