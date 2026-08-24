import 'package:flutter/material.dart';

class ClientNavStore {
  ClientNavStore._();

  static final tabIndex = ValueNotifier<int>(0);

  static void goToSearch() => tabIndex.value = 1;
}
