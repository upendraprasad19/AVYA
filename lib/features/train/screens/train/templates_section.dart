part of 'screen.dart';

extension _TemplatesSection on _TrainScreenState {
  // ── My Templates Section ─────────────────────────────────────

  Widget _buildMyTemplatesSection(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with + button
          Row(
            children: [
              Text(
                'MY TEMPLATES',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/train/template-builder'),
                child: const WardChip(
                  label: '+ CREATE',
                  tone: WardChipTone.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (templates.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Row(
                children: [
                  Text(
                    'No templates yet — tap ',
                    style: AppTypography.bodyS
                        .copyWith(color: AppColors.textDim),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/train/template-builder'),
                    child: Text(
                      '+ CREATE',
                      style: AppTypography.bodyS.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    ' to build one.',
                    style: AppTypography.bodyS
                        .copyWith(color: AppColors.textDim),
                  ),
                ],
              ),
            )
          else
            ...templates.map((tmpl) {
              final name = tmpl['name'] as String? ?? 'Unnamed';
              final exercises = tmpl['exercises'] as List? ?? [];
              final templateId = tmpl['id'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: WardCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: AppTypography.h3.copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${exercises.length} EXERCISE${exercises.length == 1 ? '' : 'S'}',
                              style: AppTypography.monoXs.copyWith(
                                color: AppColors.textDim,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            context.go('/train/template-builder', extra: {
                          'templateId': templateId,
                          'templateData': tmpl,
                        }),
                        child: const WardChip(
                          label: 'EDIT',
                          tone: WardChipTone.neutral,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _scheduleTemplate(
                            context, ref, templateId, name),
                        child: const WardChip(
                          label: 'SCHEDULE',
                          tone: WardChipTone.gold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _confirmDeleteTemplate(
                            context, ref, templateId, name),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.bgRaise,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            border:
                                Border.all(color: AppColors.line2),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: AppColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTemplate(
      BuildContext context, WidgetRef ref, String templateId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        title: Text(
          'Delete "$name"?',
          style: AppTypography.h3,
        ),
        content: Text(
          'Your originally scheduled workouts will be restored on those days. Completed workouts stay in your history.',
          style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'CANCEL',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.textDim,
                letterSpacing: 2,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'DELETE',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.bad,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref.read(templatesProvider.notifier).deleteTemplate(templateId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Template deleted',
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.card,
        ),
      );
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('train_template_delete_failed',
          message: clipped));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to delete template: $e',
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.bad,
        ),
      );
    }
  }
}
