import 'package:flutter/material.dart';

import 'ui/home_page.dart';

void main() {
  runApp(const CollarApp());
}

class CollarApp extends StatelessWidget {
  const CollarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '首輪アプリ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFB85042),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
