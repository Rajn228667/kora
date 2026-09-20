import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';

class SupportRepository {
  SupportRepository(this._ref);

  final Ref _ref;

  Future<List<FaqItem>> faq() async {
    final res = await _ref.read(apiClientProvider).get('/support/faq')
        as Map<String, dynamic>;
    return (res['items'] as List)
        .map((f) => FaqItem(
              question: (f as Map)['question'] as String,
              answer: f['answer'] as String,
            ),)
        .toList();
  }

  Future<List<SupportTicket>> tickets() async {
    final res = await _ref.read(apiClientProvider).get('/support/tickets')
        as Map<String, dynamic>;
    return (res['items'] as List).map((t) {
      final j = t as Map<String, dynamic>;
      return SupportTicket(
        id: j['id'] as String,
        subject: j['subject'] as String? ?? S.t('support.ticket_fallback'),
        status: TicketStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => TicketStatus.open,
        ),
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ??
                DateTime.now(),
      );
    }).toList();
  }

  Future<SupportTicket> createTicket(String subject, String message) async {
    final res = await _ref
        .read(apiClientProvider)
        .post('/support/tickets',
            body: {'subject': subject, 'message': message},)
        as Map<String, dynamic>;
    return SupportTicket(
      id: res['id'] as String,
      subject: res['subject'] as String? ?? subject,
      status: TicketStatus.open,
      createdAt: DateTime.now(),
    );
  }
}

final supportRepositoryProvider =
    Provider((ref) => SupportRepository(ref));

final faqProvider =
    FutureProvider((ref) => ref.watch(supportRepositoryProvider).faq());

final ticketsProvider = AsyncNotifierProvider<TicketsController,
    List<SupportTicket>>(TicketsController.new);

class TicketsController extends AsyncNotifier<List<SupportTicket>> {
  @override
  Future<List<SupportTicket>> build() =>
      ref.watch(supportRepositoryProvider).tickets();

  Future<void> create(String subject, String message) async {
    final t = await ref
        .read(supportRepositoryProvider)
        .createTicket(subject, message);
    state = AsyncData([t, ...state.value ?? []]);
  }
}

/// Support hub: FAQ + tickets.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faq = ref.watch(faqProvider);
    final tickets = ref.watch(ticketsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('support.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(S.t('support.faq'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          faq.when(
            loading: () => const KoraSkeleton(height: 180, radius: 16),
            error: (_, __) => const SizedBox.shrink(),
            data: (items) => KoraCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: items
                    .map(
                      (f) => ExpansionTile(
                        title: Text(f.question, style: AppTypography.label),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md,
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(f.answer,
                                style: AppTypography.bodySecondary,),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                  child:
                      Text(S.t('support.tickets'), style: AppTypography.title),),
              KoraGhostButton(
                label: S.t('support.create'),
                icon: AppIcons.add,
                onPressed: () => _createTicket(context, ref),
              ),
            ],
          ),
          tickets.when(
            loading: () => const KoraSkeleton(height: 90, radius: 16),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => list.isEmpty
                ? Padding(
                    padding:
                        const EdgeInsets.only(top: AppSpacing.lg),
                    child: Text(
                      S.t('support.none'),
                      style: AppTypography.bodySecondary,
                    ),
                  )
                : Column(
                    children: list
                        .map(
                          (t) => Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,),
                            child: KoraCard(
                              child: Row(
                                children: [
                                  const Icon(AppIcons.chat,
                                      color: KoraColors.primary,),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(t.subject,
                                            style: AppTypography.label,),
                                        Text(
                                          S.t('support.created_at', {
                                            'date':
                                                '${t.createdAt.day}.${t.createdAt.month}.${t.createdAt.year}',
                                          }),
                                          style: AppTypography.caption,
                                        ),
                                      ],
                                    ),
                                  ),
                                  KoraStatusChip(
                                    label: switch (t.status) {
                                      TicketStatus.open =>
                                        S.t('ticket.open'),
                                      TicketStatus.inProgress =>
                                        S.t('ticket.in_progress'),
                                      TicketStatus.resolved =>
                                        S.t('ticket.resolved'),
                                      TicketStatus.closed =>
                                        S.t('ticket.closed'),
                                    },
                                    tone: switch (t.status) {
                                      TicketStatus.open =>
                                        KoraStatusTone.warning,
                                      TicketStatus.inProgress =>
                                        KoraStatusTone.active,
                                      _ => KoraStatusTone.neutral,
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  void _createTicket(BuildContext context, WidgetRef ref) {
    final subject = TextEditingController();
    final message = TextEditingController();
    KoraBottomSheet.show<void>(
      context,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.t('support.new'), style: AppTypography.title),
            const SizedBox(height: AppSpacing.md),
            KoraTextField(
                controller: subject, hint: S.t('support.subject'),),
            const SizedBox(height: AppSpacing.sm),
            KoraTextField(
              controller: message,
              hint: S.t('support.describe'),
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.md),
            KoraButton(
              label: S.t('common.send'),
              onPressed: () async {
                if (subject.text.trim().isEmpty) return;
                await ref
                    .read(ticketsProvider.notifier)
                    .create(subject.text.trim(), message.text.trim());
                if (context.mounted) {
                  Navigator.pop(context);
                  KoraSnackbar.show(context, S.t('support.created'));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
