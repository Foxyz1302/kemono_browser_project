import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:signals/signals_flutter.dart';

import 'src/api/pawchive_client.dart';
import 'src/archive/archive_cache.dart';
import 'src/cache/image_cache_service.dart';
import 'src/screens/home_screen.dart';
import 'src/state/app_state.dart';
import 'src/state/auth_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthState.instance.init();
  final settingsBox = await Hive.openBox('kemono_settings');
  AppState.instance.init(settingsBox);
  await PawchiveClient.instance.init(onReLogin: () => AuthState.instance.reLogin());
  await ImageCacheService.instance.init();
  await ArchiveCache.instance.init();
  await AuthState.instance.restoreSession();
  runApp(const KemonoApp());
}

class KemonoApp extends StatelessWidget {
  const KemonoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kemono',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _AuthRouter(),
    );
  }
}

class _AuthRouter extends SignalStatefulWidget {
  const _AuthRouter();

  @override
  State<_AuthRouter> createState() => _AuthRouterState();
}

class _AuthRouterState extends State<_AuthRouter> {
  @override
  Widget build(BuildContext context) {
    final status = AuthState.instance.authStatus.value;
    debugPrint('AuthRouter build: status=$status');
    return switch (status) {
      AuthStatus.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      _ => const HomeScreen(),
    };
  }
}
