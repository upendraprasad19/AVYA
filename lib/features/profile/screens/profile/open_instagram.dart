part of 'screen.dart';

extension _OpenInstagram on _ProfileScreenState {

  Future<void> _openInstagram() async {
    final native = Uri.parse('instagram://user?username=icanbefitter');
    if (await canLaunchUrl(native)) {
      await launchUrl(native);
    } else {
      await launchUrl(Uri.parse('https://instagram.com/icanbefitter'));
    }
  }
}
