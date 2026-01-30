# FMCW50 雷达水位计调试助手 (Flutter Android)

这是一个基于 Flutter 开发的 Android 应用程序，专门用于通过蓝牙（BLE）与 **FMCW50V1 型雷达水位计**（搭载 **X-E45x 系列蓝牙模块**）进行通信。

该程序允许用户通过手机蓝牙连接水位计，发送 ASCII 指令查询实时水位、信号强度，并修改传感器参数。

## 📱 功能特性

*   **蓝牙扫描与连接**：自动过滤并列出附近的 BLE 设备，支持一键连接。
*   **服务发现**：自动匹配 X-E45x 模块的透传服务 UUID (`FFF0`)。
*   **实时数据接收**：订阅 Notification 特征值 (`FFF1`)，实时显示传感器返回的 ASCII 数据流。
*   **指令发送**：
    *   支持 **无回复写入 (Write Without Response)** 模式，适配 `FFF2` 特征值。
    *   自动追加 `\r\n` 结束符，确保指令被模块正确识别。
*   **快捷操作**：内置常用查询指令（读取水位、查询功率、查询版本）。
*   **自定义参数**：支持手动输入指令头和参数值进行配置写入。
*   **日志系统**：可视化日志窗口，区分发送（ℹ️）、接收（⬇️）和错误（❌）信息。

## 🛠️ 硬件环境

1.  **传感器**：FMCW50V1 型雷达水位计。
2.  **通信模块**：X-E45x (如 X-E453SM) 蓝牙转串口模块。
3.  **运行设备**：Android 手机（需支持蓝牙 4.0+，Android 5.0+）。

## ⚙️ 技术参数与协议

根据硬件说明书，本程序使用了以下关键参数：

### 1. 蓝牙 UUID 配置
| 名称 | UUID | 说明 |
| :--- | :--- | :--- |
| **Service** | `0000fff0-0000-1000-8000-00805f9b34fb` | 透传服务 |
| **Notify** | `0000fff1-0000-1000-8000-00805f9b34fb` | **接收** (APP <- 设备)，需开启通知 |
| **Write** | `0000fff2-0000-1000-8000-00805f9b34fb` | **发送** (APP -> 设备)，属性: **Write No Response** |

### 2. 通信协议 (ASCII)
*   **波特率**：默认 115200 (取决于模块配置)。
*   **指令格式**：`CMD-ADDR:PARAM`
    *   **查询**：`DSWJ-001:` (读水位，地址001)
    *   **写入**：`GLSZ-001:0031` (设功率为31，地址001)
*   **注意**：发送指令时必须在末尾添加 `\r\n` (回车换行)。

## 🚀 开发环境搭建

### 依赖库 (`pubspec.yaml`)
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^1.32.0  # 蓝牙核心库
  permission_handler: ^11.3.0 # 权限处理
```

### Android 配置
1.  **权限** (`AndroidManifest.xml`)：需添加 `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION` 等权限。
2.  **SDK 版本** (`android/app/build.gradle`)：
    ```gradle
    defaultConfig {
        minSdkVersion 21
    }
    ```

## ⚠️ 常见问题与解决方案 (Troubleshooting)

### 1. 报错 `PlatformException(writeCharacteristic, The WRITE property is not supported...)`
*   **原因**：尝试使用了“带回复写入”模式，但硬件特征值 `FFF2` 仅支持“无回复写入”。
*   **解决**：在写入代码中必须添加 `withoutResponse: true`。
    ```dart
    await _writeCharacteristic!.write(data, withoutResponse: true);
    ```

### 2. 报错 `cmdline-tools component is missing`
*   **原因**：Android Studio 未安装命令行工具。
*   **解决**：Android Studio -> SDK Manager -> SDK Tools -> 勾选 **Android SDK Command-line Tools** -> Apply。

### 3. 扫描不到设备
*   **原因**：Android 6.0+ 扫描蓝牙需要定位权限，且必须开启手机 GPS。
*   **解决**：确保已在 APP 中授予位置权限，并下拉手机状态栏开启“位置信息”。

### 4. 发送指令无反应
*   **原因**：指令末尾缺少结束符。
*   **解决**：确保发送的字符串末尾包含 `\r\n`。

## 📝 核心代码逻辑 (`lib/main.dart`)

```dart
// 核心发送函数示例
Future<void> _sendCommand(String cmd) async {
  // 1. 拼接回车换行
  String finalCmd = "$cmd\r\n"; 
  // 2. 编码为 UTF8/ASCII
  List<int> bytes = utf8.encode(finalCmd);
  // 3. 发送 (注意 withoutResponse: true)
  await _writeCharacteristic!.write(bytes, withoutResponse: true);
}
```

## 📅 版本历史

*   **v1.0.0**: 初始版本，实现蓝牙连接、服务发现、数据接收及基础指令发送功能。修复了写入属性报错的问题。
