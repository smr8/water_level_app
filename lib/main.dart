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

class _WaterLevelAppState extends State<WaterLevelApp> with SingleTickerProviderStateMixin {
  // 核心变量
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  
  // 状态与日志
  bool _isScanning = false;
  bool _isConnected = false;
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  
  // 输入控制器 (水位计)
  final TextEditingController _addressController = TextEditingController(text: "001");
  final TextEditingController _customCmdController = TextEditingController();
  final TextEditingController _measureParamController = TextEditingController();
  final TextEditingController _systemParamController = TextEditingController();

  // 输入控制器 (遥测终端)
  final TextEditingController _telemetryZoneController = TextEditingController(text: "000");
  final TextEditingController _telemetryStationController = TextEditingController(text: "001");
  final TextEditingController _telemetryCustomCmdController = TextEditingController();
  final TextEditingController _runParamController = TextEditingController();
  final TextEditingController _alarmParamController = TextEditingController();
  final TextEditingController _commParamController = TextEditingController();
  final TextEditingController _videoParamController = TextEditingController();

  // Tab控制器
  late TabController _tabController;

  // 选中的命令 (水位计)
  String _selectedMeasureCmd = "GLSZ";
  String _selectedSystemCmd = "BZQH";

  // 选中的命令 (遥测终端)
  String _selectedRunParamCmd = "BZQH";
  String _selectedAlarmParamCmd = "SDYL";
  String _selectedCommParamCmd = "CZBM";
  String _selectedSingleCmd = "XTSZ";
  String _selectedVideoParamCmd = "SPDK";

  // 定义目标 UUID (来自 X-E45x 说明书)
  final String serviceUuid = "fff0"; 
  final String notifyUuid = "fff1"; // 接收 (APP <- 设备)
  final String writeUuid = "fff2";  // 发送 (APP -> 设备)

  // 水位计 - 测量参数列表
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

  // 水位计 - 系统参数列表
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

  // 遥测终端 - 运行参数列表
  final List<Map<String, String>> _runParamCommands = [
    {"cmd": "BZQH", "label": "本站区号 (BZQH)"},
    {"cmd": "BZZH", "label": "本站站号 (BZZH)"},
    {"cmd": "YLFB", "label": "雨量分辨 (YLFB)"},
    {"cmd": "XSKG", "label": "显示开关 (XSKG)"},
    {"cmd": "CZJG", "label": "存贮间隔 (CZJG)"},
    {"cmd": "TXYR", "label": "通信预热 (TXYR)"},
    {"cmd": "TPJG", "label": "图片间隔 (TPJG)"},
    {"cmd": "DKSL", "label": "端口数量 (DKSL)"},
    {"cmd": "CYJG", "label": "采样间隔 (CYJG)"},
    {"cmd": "DKYR", "label": "端口预热 (DKYR)"},
    {"cmd": "D1JK", "label": "1#DK接口 (D1JK)"},
    {"cmd": "D2JK", "label": "2#DK接口 (D2JK)"},
    {"cmd": "D3JK", "label": "3#DK接口 (D3JK)"},
    {"cmd": "D4JK", "label": "4-16接口 (D4JK)"},
    {"cmd": "BJLS", "label": "报警历时 (BJLS)"},
    {"cmd": "FBFS", "label": "发报方式 (FBFS)"},
    {"cmd": "PAJG", "label": "平安间隔 (PAJG)"},
    {"cmd": "SWYZ", "label": "水位阈值 (SWYZ)"},
    {"cmd": "YLYZ", "label": "雨量阈值 (YLYZ)"},
    {"cmd": "FWYS", "label": "发完延时 (FWYS)"},
    {"cmd": "ZXLX", "label": "主信类型 (ZXLX)"},
    {"cmd": "BXLX", "label": "备信类型 (BXLX)"},
    {"cmd": "BWGS", "label": "报文格式 (BWGS)"},
    {"cmd": "DTSL", "label": "串口1BPS (DTSL)"},
    {"cmd": "CZLX", "label": "测站类型 (CZLX)"},
    {"cmd": "SWFB", "label": "水位分辨 (SWFB)"},
    {"cmd": "BJLS", "label": "报警历时 (BJLS)"},
    {"cmd": "GRSL", "label": "串口0BPS (GRSL)"},
    {"cmd": "CYSL", "label": "采样速率 (CYSL)"},
    {"cmd": "WLSS", "label": "网络授时 (WLSS)"},
    {"cmd": "SFYS", "label": "收发延时 (SFYS)"},
    {"cmd": "SWGS", "label": "水位公式 (SWGS)"},
  ];

  // 遥测终端 - 报警参数列表
  final List<Map<String, String>> _alarmParamCommands = [
    {"cmd": "SDYL", "label": "时段雨量 (SDYL)"},
    {"cmd": "S1XZ", "label": "水位1修正 (S1XZ)"},
    {"cmd": "S2XZ", "label": "水位2修正 (S2XZ)"},
    {"cmd": "S1JZ", "label": "水位1基值 (S1JZ)"},
    {"cmd": "S2JZ", "label": "水位2基值 (S2JZ)"},
    {"cmd": "ADJZ", "label": "AD基准 (ADJZ)"},
    {"cmd": "XSK1", "label": "系数K1 (XSK1)"},
    {"cmd": "CSB1", "label": "常数B1 (CSB1)"},
    {"cmd": "XSK2", "label": "系数K2 (XSK2)"},
    {"cmd": "CSB2", "label": "常数B2 (CSB2)"},
    {"cmd": "S1SX", "label": "水位1上限 (S1SX)"},
    {"cmd": "S2SX", "label": "水位2上限 (S2SX)"},
    {"cmd": "S1XX", "label": "水位1下限 (S1XX)"},
    {"cmd": "S2XX", "label": "水位2下限 (S2XX)"},
  ];

  // 遥测终端 - 通信设置列表
  final List<Map<String, String>> _commParamCommands = [
    {"cmd": "CZBM", "label": "测站编码 (CZBM)"},
    {"cmd": "SZX1", "label": "短信中心1 (SZX1)"},
    {"cmd": "SZX2", "label": "短信中心2 (SZX2)"},
    {"cmd": "SZX3", "label": "短信中心3 (SZX3)"},
    {"cmd": "GZX1", "label": "GPRS中心1 (GZX1)"},
    {"cmd": "GZX2", "label": "GPRS中心2 (GZX2)"},
    {"cmd": "GZX3", "label": "GPRS中心3 (GZX3)"},
    {"cmd": "WLJD", "label": "网络节点 (WLJD)"},
    {"cmd": "XTZF", "label": "心跳字符 (XTZF)"},
    {"cmd": "WLYH", "label": "网络用户 (WLYH)"},
    {"cmd": "WLMM", "label": "网络密码 (WLMM)"},
    {"cmd": "WXZX", "label": "卫星中心 (WXZX)"},
    {"cmd": "D1SX", "label": "1#端口属性 (D1SX)"},
    {"cmd": "D2SX", "label": "2#端口属性 (D2SX)"},
    {"cmd": "D3SX", "label": "3#端口属性 (D3SX)"},
    {"cmd": "D4SX", "label": "3#以后属性 (D4SX)"},
    {"cmd": "ZXZH", "label": "中心站3HEX (ZXZH)"},
    {"cmd": "CZMM", "label": "置密码2HEX (CZMM)"},
    {"cmd": "BYJB", "label": "置暴雨加报 (BYJB)"},
  ];

  // 遥测终端 - 单个命令列表
  final List<Map<String, String>> _singleCommands = [
    {"cmd": "XTSZ", "label": "系统时钟 (XTSZ)"},
    {"cmd": "YCZC", "label": "远程召测 (YCZC)"},
    {"cmd": "XTFW", "label": "系统复位 (XTFW)"},
    {"cmd": "YYBB", "label": "应用版本 (YYBB)"},
  ];

  // 遥测终端 - 视频电源列表
  final List<Map<String, String>> _videoParamCommands = [
    {"cmd": "SPDK", "label": "视频打开 (SPDK)"},
    {"cmd": "SPGB", "label": "视频关闭 (SPGB)"},
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addressController.dispose();
    _customCmdController.dispose();
    _measureParamController.dispose();
    _systemParamController.dispose();
    _telemetryZoneController.dispose();
    _telemetryStationController.dispose();
    _telemetryCustomCmdController.dispose();
    _runParamController.dispose();
    _alarmParamController.dispose();
    _commParamController.dispose();
    _videoParamController.dispose();
    _logScrollController.dispose();
    super.dispose();
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
      // 1. Append CRLF
      String finalCmd = "$cmd\r\n";
      
      _addLog("发送: ${finalCmd.trim()}");

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
  // useTelemetryAddr: true 使用遥测终端地址，false 使用水位计地址
  void _sendParamCommand(String cmd, String value, {bool useTelemetryAddr = false}) {
    // 遥测终端地址处理
    if (useTelemetryAddr) {
      String zone = _telemetryZoneController.text;
      String station = _telemetryStationController.text;
      
      if (zone.isEmpty) zone = "000";
      if (station.isEmpty) station = "001";
      
      String fullCmd = "$cmd-$zone-$station:$value";
      _sendCommand(fullCmd);
    } else {
      // 水位计地址处理
      String addr = _addressController.text;
      if (addr.isEmpty) {
        addr = "001"; // 默认
      }
      String fullCmd = "$cmd-$addr:$value";
      _sendCommand(fullCmd);
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
            
            // TabBar
            Container(
              color: Colors.grey[200],
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.black54,
                indicatorColor: Colors.blue,
                tabs: const [
                  Tab(text: "水位计"),
                  Tab(text: "遥测终端"),
                ],
              ),
            ),

            // TabBarView
            Expanded(
              flex: 4,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: 水位计
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            children: [
                              const Text("地址: ", style: TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(
                                width: 50,
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
                              Expanded(
                                child: TextField(
                                  controller: _customCmdController,
                                  decoration: const InputDecoration(
                                    labelText: "自编命令 (如 GLSZ-001:)",
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              ElevatedButton(
                                onPressed: () {
                                  if (_customCmdController.text.isNotEmpty) {
                                    _sendCommand(_customCmdController.text);
                                  }
                                },
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                child: const Text("发送"),
                              ),
                            ],
                          ),
                        ),

                        const Divider(),
                        
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
                    ),
                  ),
                  
                  // Tab 2: 遥测终端
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Column(
                            children: [
                              // Row 1: Zone and Station Code
                              Row(
                                children: [
                                  const Text("区号: ", style: TextStyle(fontWeight: FontWeight.bold)),
                                  SizedBox(
                                    width: 60,
                                    child: TextField(
                                      controller: _telemetryZoneController,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  const Text("站号: ", style: TextStyle(fontWeight: FontWeight.bold)),
                                  SizedBox(
                                    width: 60,
                                    child: TextField(
                                      controller: _telemetryStationController,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const Spacer(), // Push content to left
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Row 2: Custom Command
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _telemetryCustomCmdController,
                                      decoration: const InputDecoration(
                                        labelText: "自编命令",
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  ElevatedButton(
                                    onPressed: () {
                                      if (_telemetryCustomCmdController.text.isNotEmpty) {
                                        _sendCommand(_telemetryCustomCmdController.text);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                    child: const Text("发送"),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        
                        // 运行参数
                        const Text("运行参数", style: TextStyle(fontWeight: FontWeight.bold)),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedRunParamCmd,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    isDense: true,
                                  ),
                                  items: _runParamCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) setState(() => _selectedRunParamCmd = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _runParamController,
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
                                onPressed: () => _sendParamCommand(_selectedRunParamCmd, _runParamController.text, useTelemetryAddr: true),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                child: const Text("发送"),
                              ),
                            ],
                          ),
                        ),

                        // 报警参数
                        const Text("报警参数", style: TextStyle(fontWeight: FontWeight.bold)),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedAlarmParamCmd,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    isDense: true,
                                  ),
                                  items: _alarmParamCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) setState(() => _selectedAlarmParamCmd = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _alarmParamController,
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
                                onPressed: () => _sendParamCommand(_selectedAlarmParamCmd, _alarmParamController.text, useTelemetryAddr: true),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                child: const Text("发送"),
                              ),
                            ],
                          ),
                        ),

                        // 通信设置
                        const Text("通信设置", style: TextStyle(fontWeight: FontWeight.bold)),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedCommParamCmd,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    isDense: true,
                                  ),
                                  items: _commParamCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) setState(() => _selectedCommParamCmd = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _commParamController,
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
                                onPressed: () => _sendParamCommand(_selectedCommParamCmd, _commParamController.text, useTelemetryAddr: true),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                child: const Text("发送"),
                              ),
                            ],
                          ),
                        ),

                        // 单个命令
                        const Text("单个命令", style: TextStyle(fontWeight: FontWeight.bold)),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedSingleCmd,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    isDense: true,
                                  ),
                                  items: _singleCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) setState(() => _selectedSingleCmd = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 1,
                                child: Container(), // 占位
                              ),
                              const SizedBox(width: 5),
                              ElevatedButton(
                                onPressed: () => _sendParamCommand(_selectedSingleCmd, "", useTelemetryAddr: true),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                child: const Text("发送"),
                              ),
                            ],
                          ),
                        ),

                        // 视频电源
                        const Text("视频电源", style: TextStyle(fontWeight: FontWeight.bold)),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedVideoParamCmd,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    isDense: true,
                                  ),
                                  items: _videoParamCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) setState(() => _selectedVideoParamCmd = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _videoParamController,
                                  decoration: const InputDecoration(
                                    labelText: "参数值",
                                    hintText: "秒",
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              ElevatedButton(
                                onPressed: () => _sendParamCommand(_selectedVideoParamCmd, _videoParamController.text, useTelemetryAddr: true),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                child: const Text("发送"),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
