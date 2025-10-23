import 'package:flutter/material.dart';
import 'package:nerfrontend/view/live_translator_view.dart';
// Make sure this path matches your file structure
// import 'package:?/view/live_translator_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soniox Translator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // This is the main UI screen
      home: const LiveTranslatorView(),
      debugShowCheckedModeBanner: false,
    );
  }
}