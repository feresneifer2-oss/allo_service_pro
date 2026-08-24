import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../../../core/models/request_status.dart';
import '../../chat/application/chat_store.dart';
import '../../notifications/application/notification_store.dart';
import '../../pro_dashboard/application/pro_profile_store.dart';

class RequestStore {
  RequestStore._();

  static final requests = ValueNotifier<List<ServiceRequest>>([]);

  static void add(ServiceRequest request) {
    final list = List<ServiceRequest>.from(requests.value);
    list.insert(0, request);
    requests.value = list;

    // Notify professional of new request
    NotificationStore.notifyNewRequest(
      request.id,
      request.customerName,
      request.professionalId,
    );
  }

  /// Returns true when the transition succeeded.
  ///
  /// Confirming a pending order (`accepted`) deducts exactly 10 tokens from
  /// the professional's balance and unlocks the chat for both parties inside
  /// the admin-defined time window. Without enough tokens the confirmation
  /// is refused (returns false).
  static bool updateStatus(String id, RequestStatus status) {
    final request = byId(id);
    if (request == null) return false;

    // Handle token deduction and notifications when accepting
    if (status == RequestStatus.accepted &&
        request.status == RequestStatus.pending) {
      // Confirming the order costs exactly 10 tokens.
      final deducted = ProProfileStore.deductTokens(10);
      if (!deducted) {
        // Not enough tokens: the confirmation cannot proceed.
        return false;
      }
      NotificationStore.notifyTokenDeduction(
        id,
        ProProfileStore.tokens.value,
        request.professionalId,
      );
      NotificationStore.notifyRequestAccepted(
        id,
        request.professionalName,
        request.customerId,
      );
      // Unlock the chat for both parties (auto-expires after 48–72h).
      ChatStore.activate(id);
    } else if (status == RequestStatus.refused &&
        request.status == RequestStatus.pending) {
      NotificationStore.notifyRequestRefused(
        id,
        request.professionalName,
        request.customerId,
      );
    } else if ((status == RequestStatus.cancelled ||
            status == RequestStatus.completed) &&
        request.status == RequestStatus.accepted) {
      // Ending the job also ends its chat window.
      ChatStore.deactivate(id);
    }

    requests.value = requests.value
        .map((r) => r.id == id ? r.copyWith(status: status) : r)
        .toList();
    return true;
  }

  // Admin reset reopens the order as pending: the chat locks again until
  // the professional re-confirms it (charging 10 additional tokens).
  static bool adminResetAcceptance(String id) {
    final request = byId(id);
    if (request == null || request.status != RequestStatus.accepted) {
      return false;
    }

    ChatStore.deactivate(id);
    requests.value = requests.value
        .map((r) => r.id == id ? r.copyWith(status: RequestStatus.pending) : r)
        .toList();
    return true;
  }

  static void rate(String id, double rating, String comment) {
    requests.value = requests.value
        .map(
          (r) => r.id == id
              ? r.copyWith(
                  rating: rating,
                  reviewComment: comment,
                  status: RequestStatus.completed,
                )
              : r,
        )
        .toList();
  }

  static ServiceRequest? byId(String id) {
    try {
      return requests.value.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<ServiceRequest> forProfessional(String proId) =>
      requests.value.where((r) => r.professionalId == proId).toList();

  static List<ServiceRequest> forCustomer(String name) =>
      requests.value.where((r) => r.customerName == name).toList();

  /// Check if chatting is allowed for a request right now.
  ///
  /// Two layers must pass:
  /// 1. Status layer — only live orders carry a chat (pending/refused/
  ///    completed/cancelled never do).
  /// 2. Session layer — admin closure and the 48–72h auto-expiry window.
  static bool isChatAllowed(String requestId) {
    final request = byId(requestId);
    if (request == null) return false;

    final statusOk = request.status == RequestStatus.accepted ||
        request.status == RequestStatus.enRoute ||
        request.status == RequestStatus.arrived ||
        request.status == RequestStatus.inProgress;

    return statusOk && ChatStore.isActive(requestId);
  }
}
