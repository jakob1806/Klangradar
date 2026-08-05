import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Phase B.2 (docs/09-feature-expansion-plan.md), Nutzerwunsch Punkt 13:
/// "Eine schlanke Meldefunktion statt eines aufwendigen
/// Communitysystems... Meldungen gehen in eine Review-Queue und verändern
/// Daten nicht unmittelbar." Ein Insert in content_reports, keine
/// direkte Datenänderung — die Redaktion entscheidet im Admin-Dashboard.
enum ReportReason {
  wrongImage('wrong_image'),
  wrongTime('wrong_time'),
  cancelled('cancelled'),
  wrongArtist('wrong_artist'),
  brokenTicketLink('broken_ticket_link'),
  missingProgram('missing_program'),
  other('other');

  const ReportReason(this.value);

  final String value;
}

String reportReasonLabel(AppLocalizations l10n, ReportReason reason) =>
    switch (reason) {
      ReportReason.wrongImage => l10n.reportReasonWrongImage,
      ReportReason.wrongTime => l10n.reportReasonWrongTime,
      ReportReason.cancelled => l10n.reportReasonCancelled,
      ReportReason.wrongArtist => l10n.reportReasonWrongArtist,
      ReportReason.brokenTicketLink => l10n.reportReasonBrokenTicketLink,
      ReportReason.missingProgram => l10n.reportReasonMissingProgram,
      ReportReason.other => l10n.reportReasonOther,
    };

/// Je Entitätstyp nur die sinnvollen Gründe — "Programminformation fehlt"
/// ergibt bei einer Venue keinen Sinn, "Falsches Bild" dagegen überall.
const _reasonsByEntityType = {
  'event': [
    ReportReason.wrongImage,
    ReportReason.wrongTime,
    ReportReason.cancelled,
    ReportReason.wrongArtist,
    ReportReason.brokenTicketLink,
    ReportReason.missingProgram,
    ReportReason.other,
  ],
  'venue': [ReportReason.wrongImage, ReportReason.other],
  'person': [ReportReason.wrongImage, ReportReason.other],
  'ensemble': [ReportReason.wrongImage, ReportReason.other],
};

/// Dezenter Text-Link (kein auffälliger Button — Melden ist ein
/// Ausnahmefall, keine primäre Aktion) für Detailseiten. `entityType` muss
/// zu content_reports' entity_type-Check passen ('event'/'venue'/'person'/
/// 'ensemble').
class ReportContentLink extends StatelessWidget {
  const ReportContentLink({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  final String entityType;
  final String entityId;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: () => _showReportSheet(context, entityType, entityId),
      child: Text(
        AppLocalizations.of(context)!.reportLinkText,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 11,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

void _showReportSheet(
  BuildContext context,
  String entityType,
  String entityId,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(entityType: entityType, entityId: entityId),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.entityType, required this.entityId});

  final String entityType;
  final String entityId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _selected;
  final _messageController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _selected;
    if (reason == null || _submitting) return;
    setState(() => _submitting = true);

    final user = Supabase.instance.client.auth.currentUser;
    try {
      await Supabase.instance.client.from('content_reports').insert({
        'entity_type': widget.entityType,
        'entity_id': widget.entityId,
        'reporter_id': user?.id,
        'reason': reason.value,
        'message': _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
      });
      if (mounted) setState(() => _submitted = true);
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final reasons = _reasonsByEntityType[widget.entityType] ?? const [];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _submitted
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: colors.success),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l10n.reportThankYou,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.reportReviewNotice,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.reportWhatIsWrong,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in reasons)
                        ChoiceChip(
                          label: Text(
                            reportReasonLabel(l10n, r),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          selected: _selected == r,
                          onSelected: (_) => setState(() => _selected = r),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _messageController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: l10n.reportDetailsHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selected == null || _submitting
                          ? null
                          : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accentPrimary,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.reportSubmit),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
