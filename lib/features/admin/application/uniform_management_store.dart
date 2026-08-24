import 'package:flutter/material.dart';

class UniformRequest {
  final String id;
  final String proName;
  final String proId;
  final String address;
  final String status; // 'pending', 'shipped', 'delivered'
  final DateTime requestedAt;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;

  const UniformRequest({
    required this.id,
    required this.proName,
    required this.proId,
    required this.address,
    required this.status,
    required this.requestedAt,
    this.shippedAt,
    this.deliveredAt,
  });

  UniformRequest copyWith({
    String? id,
    String? proName,
    String? proId,
    String? address,
    String? status,
    DateTime? requestedAt,
    DateTime? shippedAt,
    DateTime? deliveredAt,
  }) {
    return UniformRequest(
      id: id ?? this.id,
      proName: proName ?? this.proName,
      proId: proId ?? this.proId,
      address: address ?? this.address,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      shippedAt: shippedAt ?? this.shippedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
    );
  }
}

class UniformManagementStore {
  UniformManagementStore._();

  static final uniformRequests = ValueNotifier<List<UniformRequest>>([
    UniformRequest(
      id: 'ur_1',
      proName: 'Ahmed Ben Ali',
      proId: 'pro_1',
      address: '123 Rue de la Liberté, Tunis',
      status: 'pending',
      requestedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    UniformRequest(
      id: 'ur_2',
      proName: 'Sonia Belhaj',
      proId: 'pro_2',
      address: '45 Avenue Habib Bourguiba, Ariana',
      status: 'shipped',
      requestedAt: DateTime.now().subtract(const Duration(days: 5)),
      shippedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ]);

  static void addUniformRequest(UniformRequest request) {
    final list = List<UniformRequest>.from(uniformRequests.value);
    list.insert(0, request);
    uniformRequests.value = list;
  }

  static void updateStatus(String id, String status) {
    uniformRequests.value = uniformRequests.value.map((r) {
      if (r.id == id) {
        final now = DateTime.now();
        return r.copyWith(
          status: status,
          shippedAt: status == 'shipped' ? now : r.shippedAt,
          deliveredAt: status == 'delivered' ? now : r.deliveredAt,
        );
      }
      return r;
    }).toList();
  }

  static void deleteRequest(String id) {
    uniformRequests.value =
        uniformRequests.value.where((r) => r.id != id).toList();
  }

  static List<UniformRequest> get pendingRequests =>
      uniformRequests.value.where((r) => r.status == 'pending').toList();

  static List<UniformRequest> get shippedRequests =>
      uniformRequests.value.where((r) => r.status == 'shipped').toList();

  static List<UniformRequest> get deliveredRequests =>
      uniformRequests.value.where((r) => r.status == 'delivered').toList();
}
