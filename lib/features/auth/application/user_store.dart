import 'package:flutter/material.dart';

class UserModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final UserRole? role;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.role,
  });

  UserModel copyWith({UserRole? role}) => UserModel(
        id: id,
        name: name,
        phone: phone,
        email: email,
        role: role ?? this.role,
      );
}

enum UserRole { client, professional }

class UserStore {
  UserStore._();

  static final user = ValueNotifier<UserModel?>(null);
  static final Map<String, _LocalAccount> _accounts = {};

  static void set({
    required String name,
    required String phone,
    String? email,
    String? id,
    UserRole? role,
  }) {
    user.value = UserModel(
      id: id ?? 'user_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      phone: phone,
      email: email,
      role: role,
    );
  }

  static bool register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) {
    final key = email.trim().toLowerCase();
    if (key.isEmpty || _accounts.containsKey(key)) return false;
    final account = _LocalAccount(name: name, phone: phone, password: password);
    _accounts[key] = account;
    set(name: name, phone: phone, email: key);
    return true;
  }

  static bool signIn({required String email, required String password}) {
    final key = email.trim().toLowerCase();
    final account = _accounts[key];
    if (account == null || account.password != password) return false;
    set(name: account.name, phone: account.phone, email: key);
    return true;
  }

  static void setRole(UserRole role) {
    final current = user.value;
    if (current != null) user.value = current.copyWith(role: role);
  }

  static void signOut() => user.value = null;

  static String get displayName {
    final n = user.value?.name.trim();
    if (n != null && n.isNotEmpty) return n.split(' ').first;
    return 'Utilisateur';
  }
}

class _LocalAccount {
  const _LocalAccount({
    required this.name,
    required this.phone,
    required this.password,
  });

  final String name;
  final String phone;
  final String password;
}
