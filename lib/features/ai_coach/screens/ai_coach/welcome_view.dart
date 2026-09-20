part of 'screen.dart';

extension _WelcomeView on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // WELCOME VIEW — shown when chat is empty
  // ────────────────────────────────────────────────────────────────

  Widget _buildWelcomeView() {
    // AG.2 — JSX handoff's full coach "home" layout: Today's Insight
    // quote, 3 Suggested Actions, Patterns I've Noticed, and the
    // Deep Analysis dashed CTA. Shown only while the chat history is
    // empty; as soon as the user sends a message `_buildChatArea`
    // takes over and these sections scroll out of the way naturally.
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: const [
        CoachInsightSection(),
        CoachSuggestedActions(),
        CoachPatternsCard(),
        CoachDeepAnalysisCard(),
      ],
    );
  }
}
