import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:window_manager/window_manager.dart';
import 'package:senhorita/firebase_options.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await _limparCacheFirestore(); // <--- aqui está a exclusão forçada

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Desativa cache (adicional de segurança)
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );

      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(800, 600),
        center: true,
        title: 'Senhorita',
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      windowManager.setPreventClose(true);
      windowManager.addListener(MyWindowListener());

      runApp(const MyApp());
    },
    (error, stack) async {
      await salvarLogErro(error.toString(), stack.toString());
    },
  );
}

Future<void> _limparCacheFirestore() async {
  try {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      final firestoreDir = Directory(
        '$localAppData\\firestore\\[DEFAULT]\\senhorita-5c5fd\\main',
      );
      if (await firestoreDir.exists()) {
        await firestoreDir.delete(recursive: true);
        debugPrint(
          '🔥 Cache Firestore removido com sucesso antes da inicialização.',
        );
      }
    }
  } catch (e) {
    debugPrint('⚠️ Falha ao limpar cache Firestore: $e');
  }
}

Future<void> salvarLogErro(String erro, String stacktrace) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final logFile = File('${dir.path}/senhorita_log_erro.txt');
    final agora = DateTime.now().toIso8601String();
    final log = '[LOG $agora]\nERRO: $erro\nSTACKTRACE:\n$stacktrace\n\n';
    await logFile.writeAsString(log, mode: FileMode.append);
  } catch (e) {
    debugPrint('Falha ao salvar log: $e');
  }
}

class MyWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await FirebaseAuth.instance.signOut();
    windowManager.destroy();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Senhorita',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LoginView(),
    );
  }
}
