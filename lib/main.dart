import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// Modbus RTU 页面
class ModbusRTUPage extends StatefulWidget {
  final BluetoothCharacteristic? writeCharacteristic;
  final BluetoothCharacteristic? notifyCharacteristic;

  const ModbusRTUPage({
    super.key,
    required this.writeCharacteristic,
    required this.notifyCharacteristic,
  });

  @override
  State<ModbusRTUPage> createState() => _ModbusRTUPageState();
}

class _ModbusRTUPageState extends State<ModbusRTUPage> {
  final List<LogEntry> _logs = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _subscription;

  // 输入控制器
  final TextEditingController _stationController = TextEditingController(text: "01");
  final TextEditingController _funcController = TextEditingController(text: "03");
  final TextEditingController _addrController = TextEditingController(text: "0000");
  final TextEditingController _countController = TextEditingController(text: "0002");

  // 接收数据显示
  final TextEditingController _rxDataHexController = TextEditingController();
  final TextEditingController _rxDataDecController = TextEditingController();

  // 数据类型选择 (默认为整型)
  String _selectedDataType = "Integer"; // "Integer" or "Float"

  @override
  void initState() {
    super.initState();
    if (widget.notifyCharacteristic != null) {
      _subscription = widget.notifyCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
           _addLog("RX", value, "Received");
           _handleReceivedData(value);
        }
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stationController.dispose();
    _funcController.dispose();
    _addrController.dispose();
    _countController.dispose();
    _rxDataHexController.dispose();
    _rxDataDecController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleReceivedData(List<int> data) {
    // 简单解析 Modbus RTU (03功能码返回)
    // 格式: [站号] [功能码] [字节数] [数据...] [CRC低] [CRC高]
    if (data.length < 5) return;
    
    // 如果是功能码 03
    if (data[1] == 0x03) {
      int byteCount = data[2];
      if (data.length >= 3 + byteCount + 2) {
        List<int> dataBytes = data.sublist(3, 3 + byteCount);
        
        // 1. 填入十六进制框
        String hexStr = dataBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
        _rxDataHexController.text = hexStr;

        // 2. 根据选择类型解析数值
        if (_selectedDataType == "Float") {
          // 尝试解析为浮点数 (IEEE 754)
          // Modbus通常使用 ABCD 顺序 (Big Endian)
          if (dataBytes.length == 4) {
             // 32-bit float
             ByteData byteData = ByteData(4);
             for(int i=0; i<4; i++) byteData.setUint8(i, dataBytes[i]);
             double floatVal = byteData.getFloat32(0, Endian.big);
             _rxDataDecController.text = floatVal.toString();
          } else {
             _rxDataDecController.text = "Error: Need 4 bytes for Float";
          }
        } else {
          // 默认为整型 (Big Endian)
          BigInt value = BigInt.zero;
          for (var b in dataBytes) {
            value = (value << 8) | BigInt.from(b);
          }
          _rxDataDecController.text = value.toString();
        }
      }
    }
  }

  void _addLog(String direction, List<int> data, String message) {
    setState(() {
      _logs.add(LogEntry(
        timestamp: DateTime.now(),
        direction: direction,
        rawData: data,
        message: message,
      ));
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // CRC16 计算 (Modbus RTU)
  List<int> _calculateCRC(List<int> data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc >>= 1;
          crc ^= 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    // 低位在前，高位在后
    return [crc & 0xFF, (crc >> 8) & 0xFF];
  }

  void _send() async {
    if (widget.writeCharacteristic == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("未连接设备")));
      return;
    }

    try {
      // 解析输入 (假设输入为16进制字符串)
      int station = int.parse(_stationController.text, radix: 16);
      int func = int.parse(_funcController.text, radix: 16);
      int addr = int.parse(_addrController.text, radix: 16);
      int count = int.parse(_countController.text, radix: 16);

      List<int> cmd = [];
      cmd.add(station & 0xFF);
      cmd.add(func & 0xFF);
      cmd.add((addr >> 8) & 0xFF);
      cmd.add(addr & 0xFF);
      cmd.add((count >> 8) & 0xFF);
      cmd.add(count & 0xFF);

      List<int> crc = _calculateCRC(cmd);
      cmd.addAll(crc);

      _addLog("TX", cmd, "Sent");
      await widget.writeCharacteristic!.write(cmd, withoutResponse: true);
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("发送错误: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Modbus RTU 调试")),
      body: Column(
        children: [
          // 上半部分：日志
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black12,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final timeStr = "${log.timestamp.hour.toString().padLeft(2,'0')}:${log.timestamp.minute.toString().padLeft(2,'0')}:${log.timestamp.second.toString().padLeft(2,'0')}";
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: SelectableText(
                      "[$timeStr] ${log.direction}: ${log.hexString}",
                      style: TextStyle(
                        fontFamily: 'Courier',
                        color: log.direction == "TX" ? Colors.blue[800] : (log.direction == "RX" ? Colors.green[800] : Colors.black),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(height: 1),
          // 下半部分：输入
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _stationController,
                          decoration: const InputDecoration(labelText: "站号 (Hex)", border: OutlineInputBorder()),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _funcController,
                          decoration: const InputDecoration(labelText: "功能码 (Hex)", border: OutlineInputBorder()),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addrController,
                          decoration: const InputDecoration(labelText: "起始地址 (Hex)", border: OutlineInputBorder()),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _countController,
                          decoration: const InputDecoration(labelText: "读取点数 (Hex)", border: OutlineInputBorder()),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _send,
                      child: const Text("生成校验码并发送"),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // 数据类型选择
                  DropdownButtonFormField<String>(
                    value: _selectedDataType,
                    decoration: const InputDecoration(
                      labelText: "解析类型",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: "Integer", child: Text("Integer (整型)")),
                      DropdownMenuItem(value: "Float", child: Text("Float (浮点数)")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                         setState(() {
                           _selectedDataType = val;
                           // 如果已有数据，重新解析需要保存原始数据，这里简单清空或让用户重发
                           // 为了体验，可以暂存上一次的 rawData，这里简单处理: 清空显示
                           _rxDataDecController.clear();
                           _rxDataHexController.clear();
                         });
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _rxDataHexController,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: "接收数据 (Hex)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _rxDataDecController,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: "接收数据 (Dec/Float)", border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 1. 定义日志条目类
class LogEntry {
  final DateTime timestamp;
  final String direction; // "TX", "RX", "INFO", "ERROR"
  final List<int>? rawData;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.direction,
    this.rawData,
    required this.message,
  });

  String get hexString {
    if (rawData == null) return "";
    return rawData!.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  // 主界面简略显示
  String get shortDisplay {
    String time = "${timestamp.hour.toString().padLeft(2,'0')}:${timestamp.minute.toString().padLeft(2,'0')}:${timestamp.second.toString().padLeft(2,'0')}";
    String prefix = direction == "RX" ? "⬇️" : (direction == "TX" ? "⬆️" : (direction == "ERROR" ? "❌" : "ℹ️"));
    return "$time $prefix $message";
  }
}

// 2. 详细日志页面
class LogPage extends StatelessWidget {
  final List<LogEntry> logs;

  const LogPage({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("详细日志 (Log Details)")),
      body: ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) {
          // 倒序显示，最新的在上面？或者保持顺序。通常查看日志习惯最新的在最后或最前。
          // 这里保持列表顺序 (index 0 是最早的)
          final log = logs[index];
          
          final timeStr = "${log.timestamp.hour.toString().padLeft(2,'0')}:${log.timestamp.minute.toString().padLeft(2,'0')}:${log.timestamp.second.toString().padLeft(2,'0')}.${log.timestamp.millisecond.toString().padLeft(3,'0')}";
          
          Color typeColor = Colors.grey;
          IconData typeIcon = Icons.info_outline;
          if (log.direction == "TX") {
            typeColor = Colors.blue;
            typeIcon = Icons.arrow_upward;
          } else if (log.direction == "RX") {
            typeColor = Colors.green;
            typeIcon = Icons.arrow_downward;
          } else if (log.direction == "ERROR") {
            typeColor = Colors.red;
            typeIcon = Icons.error_outline;
          }

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(typeIcon, size: 16, color: typeColor),
                      const SizedBox(width: 8),
                      Text(log.direction, style: TextStyle(fontWeight: FontWeight.bold, color: typeColor)),
                      const SizedBox(width: 16),
                      Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (log.rawData != null && log.rawData!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      color: Colors.grey[200],
                      child: SelectableText(
                        "HEX: ${log.hexString}",
                        style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  if (log.rawData != null) const SizedBox(height: 8),
                  SelectableText(
                    "TEXT: ${log.message}",
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

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
  StreamSubscription<List<int>>? _notifySubscription;
  Completer<void>? _responseCompleter;
  
  // 状态与日志
  bool _isScanning = false;
  bool _isConnected = false;
  // 修改为 LogEntry 列表
  final List<LogEntry> _logs = [];
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
  String _selectedMeasureCmd = "DSWJ";
  String _selectedSystemCmd = "BZZH";

  // 选中的命令 (遥测终端)
  String _selectedRunParamCmd = "BZQH";
  String _selectedAlarmParamCmd = "S1XZ";
  String _selectedCommParamCmd = "CZBM";
  String _selectedSingleCmd = "DDQZ";
  String _selectedVideoParamCmd = "SPDK";

  // 命令与控制器的映射 (分Tab)
  final Map<String, TextEditingController> _waterLevelCmdMap = {};
  final Map<String, TextEditingController> _telemetryCmdMap = {};

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
    {"cmd": "XTSZ", "label": "系统时钟 (XTSZ)"},
  ];

  // 遥测终端 - 单个命令列表
  final List<Map<String, String>> _singleCommands = [
    {"cmd": "DDQZ", "label": "读当前值 (DDQZ)"},
    {"cmd": "ZDZT", "label": "终端状态 (ZDZT)"},
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
    _initCmdMap();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _initCmdMap() {
    // Tab 0: 水位计
    for (var item in _measureCommands) _waterLevelCmdMap[item['cmd']!] = _measureParamController;
    for (var item in _systemCommands) _waterLevelCmdMap[item['cmd']!] = _systemParamController;
    
    // Tab 1: 遥测终端
    for (var item in _runParamCommands) _telemetryCmdMap[item['cmd']!] = _runParamController;
    for (var item in _alarmParamCommands) _telemetryCmdMap[item['cmd']!] = _alarmParamController;
    for (var item in _commParamCommands) _telemetryCmdMap[item['cmd']!] = _commParamController;
    for (var item in _videoParamCommands) _telemetryCmdMap[item['cmd']!] = _videoParamController;
  }

  @override
  void dispose() {
    _notifySubscription?.cancel();
    _disconnect(); // Ensure disconnection on dispose
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
              
              // 防止重复订阅
              await _notifySubscription?.cancel();

              // 开启通知订阅
              try {
                await characteristic.setNotifyValue(true);
                // 使用 StreamSubscription 管理订阅，防止内存泄漏
                _notifySubscription = characteristic.lastValueStream.listen((value) {
                  // 处理接收到的数据
                  // 允许畸形UTF8，防止解析错误
                  String response = utf8.decode(value, allowMalformed: true); 
                  _addLog("收到: $response", direction: "RX", rawData: value);
                  
                  _handleResponse(response);
                  
                  // 收到回复，完成 Completer
                  if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
                    _responseCompleter!.complete();
                  }
                }, onError: (e) {
                  _addLog("接收数据错误: $e", direction: "ERROR");
                });
                _addLog("监听开启成功");
              } catch (e) {
                _addLog("开启通知失败: $e", direction: "ERROR");
              }
            }
          }
        }
      }
    } catch (e) {
      _addLog("连接失败: $e", direction: "ERROR");
    }
  }

  // 4. 断开连接
  Future<void> _disconnect() async {
    // 先取消订阅，防止 Stream 泄漏
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    if (_connectedDevice != null) {
      // 尝试关闭通知 (虽然 disconnect 会自动断开，但显式调用更安全)
      if (_notifyCharacteristic != null) {
        try {
          await _notifyCharacteristic!.setNotifyValue(false);
        } catch (e) {
          // 忽略断开时的错误
        }
      }

      await _connectedDevice!.disconnect();
      
      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _isConnected = false;
          _writeCharacteristic = null;
          _notifyCharacteristic = null;
        });
      }
      _addLog("已断开连接");
    }
  }

  void _handleResponse(String response) {
    if (!response.contains(":")) return;
    try {
      int colonIndex = response.indexOf(":");
      String header = response.substring(0, colonIndex);
      String val = response.substring(colonIndex + 1).trim();
      
      // Extract command (part before first -)
      String cmd = header.split("-")[0];
      
      if (mounted) {
        setState(() {
          // 根据当前 Tab 更新对应的控制器
          if (_tabController.index == 0) {
            if (_waterLevelCmdMap.containsKey(cmd)) {
              _waterLevelCmdMap[cmd]!.text = val;
            }
          } else {
            if (_telemetryCmdMap.containsKey(cmd)) {
              _telemetryCmdMap[cmd]!.text = val;
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Parse error: $e");
    }
  }

  // 5. 发送命令核心函数
  Future<void> _sendCommand(String cmd) async {
    if (_writeCharacteristic == null) {
      _addLog("错误: 未连接或未找到写入特征", direction: "ERROR");
      return;
    }

    try {
      // 1. Append CRLF
      String finalCmd = "$cmd\r\n";
      List<int> bytes = utf8.encode(finalCmd);
      
      _addLog("发送: ${finalCmd.trim()}", direction: "TX", rawData: bytes);

      // 初始化 Completer
      _responseCompleter = Completer<void>();

      // 2. 关键修改：添加 withoutResponse: true
      await _writeCharacteristic!.write(
        bytes, 
        withoutResponse: true
      );
      
      // 3. 等待回复，超时3秒
      try {
        await _responseCompleter!.future.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // 超时未收到回复
        _addLog("超时未收到回复", direction: "ERROR");
      }

    } catch (e) {
      _addLog("发送失败: $e", direction: "ERROR");
    } finally {
      _responseCompleter = null;
    }
  }

  // 构建带地址的命令
  void _sendParamCommand(String cmd, String value, {bool useTelemetryAddr = false, bool shouldPad = true}) {
    String finalValue = value;
    if (value.isNotEmpty && shouldPad) {
      // 验证数字
      if (int.tryParse(value) == null) return; 
      // 超过四位不处理
      if (value.length > 4) return;
      // 补全至四位
      finalValue = value.padLeft(4, '0');
    }

    if (useTelemetryAddr) {
      String zone = _telemetryZoneController.text;
      String station = _telemetryStationController.text;
      
      if (zone.isEmpty) zone = "000";
      if (station.isEmpty) station = "001";
      
      String fullCmd = "$cmd-$zone-$station:$finalValue";
      _sendCommand(fullCmd);
    } else {
      String addr = _addressController.text;
      if (addr.isEmpty) {
        addr = "001"; 
      }
      String fullCmd = "$cmd-$addr:$finalValue";
      _sendCommand(fullCmd);
    }
  }

  // 辅助：添加日志 (更新为支持 LogEntry)
  void _addLog(String msg, {String direction = "INFO", List<int>? rawData}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      direction: direction,
      rawData: rawData,
      message: msg,
    );
    
    setState(() {
      _logs.add(entry);
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
        title: const Text("南京疆瀚水务"),
        actions: [
          IconButton(
             icon: const Icon(Icons.code),
             tooltip: "Modbus RTU",
             onPressed: () {
               Navigator.push(
                 context,
                 MaterialPageRoute(builder: (context) => ModbusRTUPage(
                   writeCharacteristic: _writeCharacteristic,
                   notifyCharacteristic: _notifyCharacteristic,
                 ))
               );
             },
          ),
          // 新增：日志页面入口
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "查看详细日志",
            onPressed: () {
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => LogPage(logs: _logs))
              );
            },
          ),
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
            // 1. 日志显示区域 (显示简略信息)
            Expanded(
              flex: 3,
              child: Container(
                color: Colors.black12,
                child: ListView.builder(
                  controller: _logScrollController,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(_logs[index].shortDisplay, style: const TextStyle(fontSize: 12)),
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
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    isDense: true,
                                  ),
                                  items: _measureCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedMeasureCmd = value;
                                        _measureParamController.clear();
                                      });
                                    }
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
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    isDense: true,
                                  ),
                                  items: _systemCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedSystemCmd = value;
                                        _systemParamController.clear();
                                      });
                                    }
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
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    isDense: true,
                                  ),
                                  items: _runParamCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedRunParamCmd = value;
                                        _runParamController.clear();
                                      });
                                    }
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
                                onPressed: () => _sendParamCommand(_selectedRunParamCmd, _runParamController.text, useTelemetryAddr: true, shouldPad: false),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedAlarmParamCmd,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        isDense: true,
                                      ),
                                      items: _alarmParamCommands.map((item) {
                                        return DropdownMenuItem(
                                          value: item['cmd'],
                                          child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() {
                                            _selectedAlarmParamCmd = value;
                                            _alarmParamController.clear();
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const Spacer(flex: 1), // 占位保持对齐
                                  const SizedBox(width: 64 + 5), // 对齐按钮和间距
                                ],
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Expanded(
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
                                    onPressed: () => _sendParamCommand(_selectedAlarmParamCmd, _alarmParamController.text, useTelemetryAddr: true, shouldPad: false),
                                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                    child: const Text("发送"),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 通信设置
                        const Text("通信设置", style: TextStyle(fontWeight: FontWeight.bold)),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedCommParamCmd,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        isDense: true,
                                      ),
                                      items: _commParamCommands.map((item) {
                                        return DropdownMenuItem(
                                          value: item['cmd'],
                                          child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() {
                                            _selectedCommParamCmd = value;
                                            _commParamController.clear();
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const Spacer(flex: 1), // 占位保持对齐
                                  const SizedBox(width: 64 + 5), // 对齐按钮和间距
                                ],
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Expanded(
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
                                    onPressed: () => _sendParamCommand(_selectedCommParamCmd, _commParamController.text, useTelemetryAddr: true, shouldPad: false),
                                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                                    child: const Text("发送"),
                                  ),
                                ],
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
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    isDense: true,
                                  ),
                                  items: _videoParamCommands.map((item) {
                                    return DropdownMenuItem(
                                      value: item['cmd'],
                                      child: Text(item['label']!, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedVideoParamCmd = value;
                                        _videoParamController.clear();
                                      });
                                    }
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
