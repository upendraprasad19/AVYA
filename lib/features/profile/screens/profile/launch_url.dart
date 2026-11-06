part of 'screen.dart';

extension _LaunchUrl on _ProfileScreenState {

  void _launchUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
