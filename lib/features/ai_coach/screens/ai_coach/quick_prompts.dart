part of 'screen.dart';

extension _QuickPrompts on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // QUICK PROMPT CHIPS — only shown when chat is empty/welcome
  // ────────────────────────────────────────────────────────────────

  Widget _buildQuickPrompts() {
    final prompts = ref.watch(contextualPromptsProvider);
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line2)),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter, vertical: 10),
            child: Row(
              children: prompts.map((prompt) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PromptChip(
                    label: prompt,
                    onTap: () => _sendMessage(prompt),
                  ),
                );
              }).toList(),
            ),
          ),
          // Right-edge fade to signal more chips are scrollable
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.bg.withValues(alpha: 0.0),
                      AppColors.bg.withValues(alpha: 0.90),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
