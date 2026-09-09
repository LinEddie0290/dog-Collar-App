import 'package:flutter/material.dart';

import 'state/collar_controller.dart';
import 'ui/root_shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const CollarApp());
}

class CollarApp extends StatefulWidget {
  const CollarApp({super.key});

  @override
  State<CollarApp> createState() => _CollarAppState();
}

class _CollarAppState extends State<CollarApp> {
  final CollarController _controller = CollarController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '首輪アプリ',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: RootShell(controller: _controller),
    );
  }
}
