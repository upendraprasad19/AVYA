part of 'screen.dart';

extension _BuildCard on _ProfileScreenState {

  /// Wraps children in a Wardroom card.
  Widget _buildCard(List<Widget> children) {
    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}
