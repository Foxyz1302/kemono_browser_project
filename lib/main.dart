import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:media_kit/media_kit.dart';
import 'package:signals/signals_flutter.dart';

import 'src/api/pawchive_client.dart';
import 'src/archive/archive_cache.dart';
import 'src/cache/image_cache_service.dart';
import 'src/screens/home_screen.dart';
import 'src/state/app_state.dart';
import 'src/state/auth_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The debug-only DevTools observer stringifies every signal value on each
  // set — a 200-500ms toString pass for the 89K filteredCreators list.
  SignalsObserver.instance = null;
  MediaKit.ensureInitialized();
  await AuthState.instance.init();
  final settingsBox = await Hive.openBox('kemono_settings');
  AppState.instance.init(settingsBox);
  await AppState.instance.loadLastChecked();
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
    if (status == AuthStatus.error) {
      final error = AuthState.instance.errorMsg.value ?? 'Unknown error';
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                onPressed: () => AuthState.instance.restoreSession(),
              ),
              TextButton(
                onPressed: () => AuthState.instance.authStatus.value = AuthStatus.loggedOut,
                child: const Text('Use without signing in'),
              ),
            ],
          ),
        ),
      );
    }
    return switch (status) {
      AuthStatus.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      _ => const HomeScreen(),
    };
  }
}
