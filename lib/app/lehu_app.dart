import 'package:flutter/material.dart';

import '../data/repositories/forum_repository.dart';
import 'app_shell.dart';
import '../shared/lehu_text_styles.dart';

class LehuApp extends StatelessWidget {
  const LehuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '乐乎',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66E0A3),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Colors.white,
          unselectedItemColor: Color(0xFF8A8A8A),
          type: BottomNavigationBarType.fixed,
        ),
        textTheme: LehuTextStyles.theme,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 17.5,
            height: 1.22,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          toolbarTextStyle: TextStyle(
            fontSize: 14.5,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
      home: FutureBuilder<ForumRepository>(
        future: ForumRepositoryFactory.load(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StartupError(error: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const _StartupLoading();
          }
          return AppShell(
            repository: snapshot.data!,
            reloadRepository: ForumRepositoryFactory.loadOnline,
          );
        },
      ),
    );
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '启动失败',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(error, style: const TextStyle(color: Color(0xFFBDBDBD))),
            ],
          ),
        ),
      ),
    );
  }
}
