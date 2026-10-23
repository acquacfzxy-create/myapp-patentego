import 'package:integration_test/integration_test_driver.dart';

// flutter drive 入口：跑完不卸载 App，便于从模拟器取回测试截图。
Future<void> main() => integrationDriver();
