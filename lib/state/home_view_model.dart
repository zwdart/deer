import 'package:flutter/foundation.dart';

class HomeViewModel extends ChangeNotifier {
  int _index = 0;

  /// 设置页需要 BuildContext，托盘和快捷键只有这个 ViewModel，用计数信号让外壳负责入栈。
  final ValueNotifier<int> settingsRequests = ValueNotifier<int>(0);

  int get index => _index;

  void select(int value) {
    if (value == _index) return;
    _index = value;
    notifyListeners();
  }

  void openSettings() => settingsRequests.value++;

  void openNews() => select(3);

  void openDevices() => select(1);

  void openShare() => select(2);

  @override
  void dispose() {
    settingsRequests.dispose();
    super.dispose();
  }
}
