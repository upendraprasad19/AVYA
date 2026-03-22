import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';

class ICanBeFitterApp extends StatelessWidget {
  const ICanBeFitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICANBEFITTER',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // TODO: Replace with GoRouter when routes are defined
      home: const Scaffold(
        body: Center(
          child: Text('ICANBEFITTER'),
        ),
      ),
    );
  }
}
