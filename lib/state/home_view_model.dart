import 'package:flutter/foundation.dart';

class HomeViewModel extends ChangeNotifier {
  int _index = 0;

  /// 设置页需要 BuildContext，托盘和快捷键只有这个 ViewModel，用计数信号让外壳负责入栈。
  final ValueNotifier<int> settingsRequests = ValueNotifier<int>(0);

  /// 「消息」菜单内部的子页：0 = 会话，1 = 设备。
  final ValueNotifier<int> commSegment = ValueNotifier<int>(0);

  int get index => _index;

  void select(int value) {
    if (value == _index) return;
    _index = value;
    notifyListeners();
  }

  void openSettings() => settingsRequests.value++;

  void openChats() {
    commSegment.value = 0;
    select(2);
  }

  void openDevices() {
    commSegment.value = 1;
    select(2);
  }

  void openShare() => select(3);

  void openNews() => select(0);

  @override
  void dispose() {
    settingsRequests.dispose();
    commSegment.dispose();
    super.dispose();
  }
}
