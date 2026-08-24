import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

// ─── Model ───────────────────────────────────────────────────────────────────
class SupportTicket {
  final String id;
  final String senderName;
  final bool isSenderPro;
  final String subject;
  final String message;
  final String date;
  String status; // 'open' | 'in_review' | 'resolved'
  final List<ChatMsg> conversation;

  SupportTicket({
    required this.id,
    required this.senderName,
    required this.isSenderPro,
    required this.subject,
    required this.message,
    required this.date,
    this.status = 'open',
    List<ChatMsg>? conversation,
  }) : conversation = conversation ??
            [ChatMsg(text: message, fromUser: true, time: date)];
}

class ChatMsg {
  final String text;
  final bool fromUser; // true = sent by pro/client | false = admin reply
  final String time;
  ChatMsg({required this.text, required this.fromUser, required this.time});
}

// ─── In-memory store ─────────────────────────────────────────────────────────
class SupportStore {
  SupportStore._();
  static final tickets = ValueNotifier<List<SupportTicket>>([]);

  static void addTicket(SupportTicket t) {
    tickets.value = [...tickets.value, t];
  }

  static void addMessage(String ticketId, ChatMsg msg) {
    final list = tickets.value.map((t) {
      if (t.id == ticketId) {
        t.conversation.add(msg);
        t.status = 'in_review';
      }
      return t;
    }).toList();
    tickets.value = List.from(list);
  }

  static void resolve(String ticketId) {
    final list = tickets.value.map((t) {
      if (t.id == ticketId) t.status = 'resolved';
      return t;
    }).toList();
    tickets.value = List.from(list);
  }
}

// ─── Main Support Screen ──────────────────────────────────────────────────────
/// Pass [isPro] = true when opening from Pro side, false from Client side.
class SupportScreen extends StatefulWidget {
  const SupportScreen(
      {super.key, this.isPro = false, this.senderName = 'Utilisateur'});
  final bool isPro;
  final String senderName;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          tr(context, fr: 'Support & Réclamations', ar: 'الدعم والشكاوى'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_rounded,
                color: AppColors.secondary),
            tooltip: tr(context, fr: 'Nouveau ticket', ar: 'تذكرة جديدة'),
            onPressed: () => _openNewTicket(context),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<SupportTicket>>(
        valueListenable: SupportStore.tickets,
        builder: (context, tickets, _) {
          if (tickets.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.support_agent_rounded,
                        color: AppColors.primary, size: 52),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tr(context, fr: 'Aucune réclamation', ar: 'لا توجد شكاوى'),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      context,
                      fr: 'Appuyez sur + pour ouvrir un ticket',
                      ar: 'اضغط + لفتح تذكرة دعم',
                    ),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _openNewTicket(context),
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: Text(
                      tr(context, fr: 'Nouvelle réclamation', ar: 'شكوى جديدة'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tickets.length,
            itemBuilder: (_, i) {
              final t = tickets[i];
              return _TicketCard(
                ticket: t,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _TicketChatScreen(
                      ticket: t,
                      senderName: widget.senderName,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewTicket(context),
        backgroundColor: AppColors.secondary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          tr(context, fr: 'Nouveau ticket', ar: 'تذكرة جديدة'),
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _openNewTicket(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NewTicketSheet(
        isPro: widget.isPro,
        senderName: widget.senderName,
      ),
    );
  }
}

// ─── New Ticket Bottom Sheet ──────────────────────────────────────────────────
class _NewTicketSheet extends StatefulWidget {
  const _NewTicketSheet({required this.isPro, required this.senderName});
  final bool isPro;
  final String senderName;

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _subjectCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String _category =
      'complaint'; // complaint | report_pro | report_client | other

  final _categories = [
    ('complaint', Icons.report_problem_rounded, 'Réclamation'),
    ('report_pro', Icons.engineering_rounded, 'Signaler un professionnel'),
    ('report_client', Icons.person_off_rounded, 'Signaler un client'),
    ('other', Icons.help_outline_rounded, 'Autre demande'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tr(context, fr: 'Nouvelle réclamation', ar: 'شكوى / طلب جديد'),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),

            // Category chips
            Text(
              tr(context, fr: 'Type de demande', ar: 'نوع الطلب'),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final selected = _category == cat.$1;
                return GestureDetector(
                  onTap: () => setState(() => _category = cat.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          selected ? AppColors.primary : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.$2,
                            size: 16,
                            color: selected
                                ? Colors.white
                                : AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          cat.$3,
                          style: TextStyle(
                            color:
                                selected ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Subject
            TextField(
              controller: _subjectCtrl,
              decoration: InputDecoration(
                hintText: tr(context,
                    fr: 'Objet (ex: Plombier absent)',
                    ar: 'الموضوع (مثال: السبّاك لم يحضر)'),
                prefixIcon:
                    const Icon(Icons.title_rounded, color: AppColors.primary),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              ),
            ),
            const SizedBox(height: 12),

            // Message
            TextField(
              controller: _msgCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: tr(
                  context,
                  fr: 'Décrivez votre problème en détail...',
                  ar: 'اشرح مشكلتك بالتفصيل...',
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_subjectCtrl.text.trim().isEmpty ||
                      _msgCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(tr(context,
                            fr: 'Veuillez remplir tous les champs.',
                            ar: 'يرجى ملء جميع الحقول.')),
                      ),
                    );
                    return;
                  }
                  final now = TimeOfDay.now();
                  SupportStore.addTicket(SupportTicket(
                    id: 'tkt_${DateTime.now().millisecondsSinceEpoch}',
                    senderName: widget.senderName,
                    isSenderPro: widget.isPro,
                    subject: _subjectCtrl.text.trim(),
                    message: _msgCtrl.text.trim(),
                    date:
                        '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                  ));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr(
                        context,
                        fr: '✅ Ticket envoyé ! L\'admin vous répondra bientôt.',
                        ar: '✅ تم إرسال التذكرة! سيرد عليك المشرف قريبًا.',
                      )),
                      backgroundColor: AppColors.success,
                    ),
                  );
                },
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18),
                label: Text(
                  tr(context, fr: 'Envoyer', ar: 'إرسال'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ticket Card ──────────────────────────────────────────────────────────────
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});
  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (ticket.status) {
      'resolved' => AppColors.success,
      'in_review' => AppColors.warning,
      _ => AppColors.primary,
    };
    final statusLabel = switch (ticket.status) {
      'resolved' => 'Résolu',
      'in_review' => 'En cours',
      _ => 'Ouvert',
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: statusColor.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ticket.subject,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(ticket.conversation.last.text,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                Text(ticket.date,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ticket Chat Screen ───────────────────────────────────────────────────────
class _TicketChatScreen extends StatefulWidget {
  const _TicketChatScreen({required this.ticket, required this.senderName});
  final SupportTicket ticket;
  final String senderName;

  @override
  State<_TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends State<_TicketChatScreen> {
  final _msgCtrl = TextEditingController();

  void _send() {
    if (_msgCtrl.text.trim().isEmpty) return;
    final now = TimeOfDay.now();
    SupportStore.addMessage(
      widget.ticket.id,
      ChatMsg(
        text: _msgCtrl.text.trim(),
        fromUser: true,
        time: '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      ),
    );
    _msgCtrl.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.ticket.status == 'resolved';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.ticket.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              tr(context, fr: 'Support Allo Service', ar: 'دعم ألو سيرفيس'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Resolved banner — shown only when the ticket is resolved.
          if (resolved)
            Container(
              color: AppColors.primarySurface,
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    tr(context,
                        fr: 'Ce ticket est résolu.', ar: 'هذه التذكرة محلولة.'),
                    style: const TextStyle(
                        color: AppColors.success, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          // Conversation — lazily-built chat bubbles.
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.ticket.conversation.length,
              itemBuilder: (context, index) {
                final msg = widget.ticket.conversation[index];
                return _ChatBubble(msg: msg, senderName: widget.senderName);
              },
            ),
          ),

          // Message input row.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      enabled: !resolved,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: tr(context,
                            fr: 'Écrivez votre message...',
                            ar: 'اكتب رسالتك...'),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: resolved ? null : _send,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: resolved ? Colors.grey : AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.msg, required this.senderName});
  final ChatMsg msg;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.fromUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? senderName : '🛡️ Admin Support',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isUser ? AppColors.secondary : AppColors.primary),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.secondary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                    color: isUser ? Colors.white : AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4),
              ),
            ),
            const SizedBox(height: 2),
            Text(msg.time,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
