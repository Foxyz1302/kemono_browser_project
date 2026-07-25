import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'src/api/pawchive_client.dart';
import 'src/archive/archive_cache.dart';
import 'src/cache/image_cache_service.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/state/auth_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthState.instance.init();
  await PawchiveClient.instance.init();
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
      AuthStatus.loggedIn => const HomeScreen(),
      AuthStatus.loggedOut || AuthStatus.error => const LoginScreen(),
    };
  }
}
