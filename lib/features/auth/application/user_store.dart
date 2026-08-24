import 'package:flutter/material.dart';

class UserModel {
  final String name;
  final String phone;
  final String? email;

  const UserModel({
    required this.name,
    required this.phone,
    this.email,
  });
}

class UserStore {
  UserStore._();

  static final user = ValueNotifier<UserModel?>(null);

  static void set({
    required String name,
    required String phone,
    String? email,
  }) {
    user.value = UserModel(name: name, phone: phone, email: email);
  }

  static String get displayName {
    final n = user.value?.name.trim();
    if (n != null && n.isNotEmpty) return n.split(' ').first;
    return 'Feres';
  }
}
