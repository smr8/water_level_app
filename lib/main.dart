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
  final TextEditingController _addressController = TextEditingController(text: "001");
  final TextEditingController _measureParamController = TextEditingController();
  final TextEditingController _systemParamController = TextEditingController();

  // 选中的命令
  String _selectedMeasureCmd = "GLSZ";
  String _selectedSystemCmd = "BZQH";

  // 定义目标 UUID (来自 X-E45x 说明书)
  final String serviceUuid = "fff0"; 
  final String notifyUuid = "fff1"; // 接收 (APP <- 设备)
  final String writeUuid = "fff2";  // 发送 (APP -> 设备)

  // 测量参数列表
  final List<Map<String, String>> _measureCommands = [
    {"cmd": "LCXZ", "label": "量程选择 (LCXZ)"},
    {"cmd": "YXYZ", "label": "有效阈值 (YXYZ)"},
    {"cmd": "ZXCJ", "label": "最小测距 (ZXCJ)"},
    {"cmd": "ZDCJ", "label": "最大测距 (ZDCJ)"},
    {"cmd": "PJCS", "label": "平均次数 (PJCS)"},
    {"cmd": "MBXZ", "label": "目标选择 (MBXZ)"},
    {"cmd": "JDXZ", "label": "精度选择 (JDXZ)"},
    {"cmd": "GLSZ", "label": "功率设置 (GLSZ)"},
    {"cmd": "JSCS", "label": "积扫次数 (JSCS)"},
    {"cmd": "DJLB", "label": "短距滤波 (DJLB)"},
    {"cmd": "DSWJ", "label": "读传感器 (DSWJ)"},
  ];

  // 系统参数列表
  final List<Map<String, String>> _systemCommands = [
    {"cmd": "BZQH", "label": "本站区号 (BZQH)"},
    {"cmd": "BZZH", "label": "本站站号 (BZZH)"},
    {"cmd": "SCXX", "label": "输出信息 (SCXX)"},
    {"cmd": "GZMS", "label": "工作模式 (GZMS)"},
    {"cmd": "CYJG", "label": "采样间隔 (CYJG)"},
    {"cmd": "WCRX", "label": "误差容限 (WCRX)"},
    {"cmd": "PAJG", "label": "平安间隔 (PAJG)"},
    {"cmd": "BWGS", "label": "报文格式 (BWGS)"},
    {"cmd": "JL04", "label": "4MA距离 (JL04)"},
    {"cmd": "JL20", "label": "20MA距离 (JL20)"},
    {"cmd": "JZ04", "label": "4MA校准 (JZ04)"},
    {"cmd": "JZ20", "label": "20MA校准 (JZ20)"},
    {"cmd": "TXYR", "label": "通信预热 (TXYR)"},
    {"cmd": "FWYS", "label": "发完延时 (FWYS)"},
    {"cmd": "TXSL", "label": "通信速率 (TXSL)"},
    {"cmd": "SZPY", "label": "时钟偏移 (SZPY)"},
    {"cmd": "BJSX", "label": "报警上限 (BJSX)"},
    {"cmd": "BJXX", "label": "报警下限 (BJXX)"},
    {"cmd": "SWJZ", "label": "水位校正 (SWJZ)"},
  ];

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

  // 构建带地址的命令
  // 格式: CMD-ADDR:VALUE (写入) 或 CMD-ADDR: (读取)
  void _sendParamCommand(String cmd, String value) {
    String addr = _addressController.text;
    if (addr.isEmpty) {
      addr = "001"; // 默认
    }
    // 如果value为空，则是读取命令，如果不为空，则是写入命令
    // 注意：无论读写，命令格式都是 CMD-ADDR:VALUE (读取时VALUE为空)
    String fullCmd = "$cmd-$addr:$value";
    _sendCommand(fullCmd);
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
              flex: 3,
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
            
            const Divider(),
            
            // 2. 常用查询区 + 地址设置
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  const Text("地址: ", style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text("常用查询", style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            Wrap(
              spacing: 10,
              children: [
                ActionChip(
                  label: const Text("读取数据 (DSWJ)"),
                  onPressed: () => _sendParamCommand("DSWJ", ""),
                ),
                ActionChip(
                  label: const Text("查发射功率 (GLSZ)"),
                  onPressed: () => _sendParamCommand("GLSZ", ""),
                ),
                ActionChip(
                  label: const Text("查版本 (VER)"),
                  onPressed: () => _sendCommand("AT+VER"),
                ),
              ],
            ),

            const Divider(),
            
            // 3. 测量参数设置
            const Text("测量参数", style: TextStyle(fontWeight: FontWeight.bold)),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedMeasureCmd,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        isDense: true,
                      ),
                      items: _measureCommands.map((item) {
                        return DropdownMenuItem(
                          value: item['cmd'],
                          child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _selectedMeasureCmd = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _measureParamController,
                      decoration: const InputDecoration(
                        labelText: "参数值",
                        hintText: "空为查询",
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  ElevatedButton(
                    onPressed: () => _sendParamCommand(_selectedMeasureCmd, _measureParamController.text),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                    child: const Text("发送"),
                  ),
                ],
              ),
            ),

            // 4. 系统参数设置
            const Text("系统参数", style: TextStyle(fontWeight: FontWeight.bold)),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedSystemCmd,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        isDense: true,
                      ),
                      items: _systemCommands.map((item) {
                        return DropdownMenuItem(
                          value: item['cmd'],
                          child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _selectedSystemCmd = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _systemParamController,
                      decoration: const InputDecoration(
                        labelText: "参数值",
                        hintText: "空为查询",
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  ElevatedButton(
                    onPressed: () => _sendParamCommand(_selectedSystemCmd, _systemParamController.text),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                    child: const Text("发送"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
