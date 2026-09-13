import 'package:flutter/material.dart';

import 'pages/camera_page.dart';

void main() => runApp(const EdgeDetectionApp());

class EdgeDetectionApp extends StatelessWidget {
  const EdgeDetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF7F7FC);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Detector de Bordas',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          surface: background,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Color(0xFF24243A),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF24243A),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: const CameraPage(),
    );
  }
}
