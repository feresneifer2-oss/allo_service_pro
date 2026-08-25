import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/models/chat_message.dart';
import 'package:allo_service_pro/features/chat/models/chat_session.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/core/models/request_status.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send({required bool isCustomer}) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final request = RequestStore.byId(widget.requestId);
    if (request == null) return;
    ChatStore.send(
      requestId: widget.requestId,
      senderId: isCustomer ? 'customer' : 'pro',
      senderName: isCustomer ? request.customerName : request.professionalName,
      text: text,
      isCustomer: isCustomer,
    );
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    // React live to admin closures / expiry / status changes.
    return ValueListenableBuilder<Map<String, ChatSession>>(
      valueListenable: ChatStore.sessions,
      builder: (_, __, ___) =>
          ValueListenableBuilder<Map<String, List<ChatMessage>>>(
        valueListenable: ChatStore.messages,
        builder: (_, __, ___) => _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final request = RequestStore.byId(widget.requestId);

    // Check if chat is allowed
    if (request == null || !RequestStore.isChatAllowed(widget.requestId)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(tr(context, fr: 'Chat', ar: 'محادثة'),
              style: const TextStyle(fontSize: 18)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded,
                  color: AppColors.textSecondary, size: 48),
              const SizedBox(height: 12),
              Text(
                _lockedTitle(context, request?.status),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (request?.status == RequestStatus.pending) ...[
                const SizedBox(height: 8),
                Text(
                  tr(context,
                      fr: 'Le professionnel doit accepter la demande pour activer le chat',
                      ar: 'يجب على الحرفي قبول الطلب لتفعيل المحادثة'),
                  style:
                      const TextStyle(color: AppColors.slate400, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    final header =
        '${tr(context, fr: request.serviceTitleFr, ar: request.serviceTitleAr)} — ${request.dateTime.day}/${request.dateTime.month} — ${request.dateTime.hour}:${request.dateTime.minute.toString().padLeft(2, '0')}';

    final msgs = ChatStore.forRequest(widget.requestId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, fr: 'Chat', ar: 'محادثة'),
                style: const TextStyle(fontSize: 18)),
            if (header.isNotEmpty)
              Text(header,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: Column(
        children: [
          // ⏳ Auto-close countdown (4 days after acceptance).
          Builder(
            builder: (_) {
              final session = ChatStore.sessionOf(widget.requestId);
              if (session == null || !session.active) {
                return const SizedBox.shrink();
              }
              final hours = session.hoursUntilAutoClose;
              final minutes = session.minutesUntilAutoClose;
              final countdown = hours >= 1
                  ? tr(context,
                      fr: 'Fermeture auto dans $hours h',
                      ar: 'الإغلاق التلقائي بعد $hours ساعة')
                  : tr(context,
                      fr: 'Fermeture auto dans $minutes min',
                      ar: 'بقت $minutes دقيقة على الإغلاق');
              return Container(
                width: double.infinity,
                color: AppColors.primarySurface,
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '⏳ $countdown',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.primary, fontSize: 11),
                ),
              );
            },
          ),
          Expanded(
            // Le seul abonnement à ChatStore.messages est celui de build() ;
            // cette liste lit simplement l'instantané courant à chaque
            // rebuild (pas d'écoute dupliquée).
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                final isMe = m.isCustomer;
                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * .75),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                          color: isMe ? Colors.white : AppColors.textPrimary),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!RequestStore.isChatAllowed(widget.requestId)) ...[
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_rounded, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'هذه المحادثة مغلقة تلقائياً بعد مرور 4 أيام',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ] else
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText:
                          tr(context, fr: 'Votre message...', ar: 'رسالتك...'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _send(isCustomer: true),
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                      backgroundColor: AppColors.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _lockedTitle(BuildContext context, RequestStatus? status) {
    switch (ChatStore.closureStateOf(widget.requestId)) {
      case ChatClosureReason.adminClosed:
        return tr(context,
            fr: "Conversation clôturée par l'administration.",
            ar: 'أغلق الإدارة هذه المحادثة.');
      case ChatClosureReason.expired:
        return tr(context,
            fr: 'Fenêtre de chat expirée — confirmez à nouveau pour discuter.',
            ar: 'انتهت مدة المحادثة — أكّد الطلب من جديد للمحادثة.');
      case ChatClosureReason.none:
        break;
    }
    return status == RequestStatus.pending
        ? tr(context, fr: "En attente d'acceptation", ar: 'في انتظار القبول')
        : tr(context, fr: 'Chat non disponible', ar: 'المحادثة غير متاحة');
  }
}
