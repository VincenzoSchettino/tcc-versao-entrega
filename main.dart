import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';

// ================= SERVICES =================
import 'package:tcc_3/services/app_notification.dart';

// ================= MODELS =================
import 'package:tcc_3/models/filho_model.dart';

// ================= SCREENS =================
import 'package:tcc_3/views/login_screen.dart';
import 'package:tcc_3/views/signup_screen.dart';
import 'package:tcc_3/views/forgot_password_screen.dart';
import 'package:tcc_3/views/home_page.dart';
import 'package:tcc_3/views/home_page_filhos.dart';
import 'package:tcc_3/views/meus_filhos_screen.dart';
import 'package:tcc_3/views/datasimportantes.dart';
import 'package:tcc_3/views/todasvacinasscreen.dart';
import 'package:tcc_3/views/notificacoes_screen.dart';

// =======================================================
// 🌍 NAVIGATOR GLOBAL
// =======================================================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// =======================================================
// 🔔 CALLBACK — BACKGROUND / TERMINATED
// =======================================================
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  _handleNotificationTap(response);
}

// =======================================================
// 🔔 CALLBACK — FOREGROUND
// =======================================================
void _onNotificationTapped(NotificationResponse response) {
  _handleNotificationTap(response);
}

// =======================================================
// 🔔 HANDLER CENTRAL DE NOTIFICAÇÃO
// =======================================================
void _handleNotificationTap(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  try {
    final data = jsonDecode(payload);
    final String? rota = data['rota'];

    if (rota == DatasImportantesScreen.routeName) {
      navigatorKey.currentState
          ?.pushNamed(DatasImportantesScreen.routeName);
    } else if (data['filhoId'] != null) {
      navigatorKey.currentState?.pushNamed(
        '/home-filho',
        arguments: data,
      );
    }
  } catch (e) {
    debugPrint('❌ Erro ao tratar payload da notificação: $e');
  }
}

// =======================================================
// 🌍 TIMEZONE
// =======================================================
Future<void> _initTimezone() async {
  tz.initializeTimeZones();
  final localTz = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(localTz));
}

// =======================================================
// 🚀 MAIN
// =======================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializeDateFormatting('pt_BR', null);
  await _initTimezone();

  // 🔔 Inicialização do plugin de notificações
  await AppNotification.instance.initialize(
    onDidReceiveNotificationResponse: _onNotificationTapped,
    onDidReceiveBackgroundNotificationResponse:
        notificationTapBackground,
  );

  runApp(const MyApp());
}

// =======================================================
// 🚀 APP
// =======================================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'ImunizaKids',

      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return const HomePage();
          }

          return const LoginScreen();
        },
      ),

      routes: {
        LoginScreen.routeName: (_) => const LoginScreen(),
        SignupScreen.routeName: (_) => const SignupScreen(),
        ForgotPasswordScreen.routeName: (_) =>
            const ForgotPasswordScreen(),
        HomePage.routeName: (_) => const HomePage(),
        MeusFilhosPage.routeName: (_) => const MeusFilhosPage(),
        DatasImportantesScreen.routeName: (_) =>
            const DatasImportantesScreen(),
        TodasVacinasScreen.routeName: (_) =>
            const TodasVacinasScreen(),
        NotificacoesScreen.routeName: (_) =>
            const NotificacoesScreen(),
      },

      onGenerateRoute: (settings) {
        if (settings.name == '/home-filho') {
          final args = settings.arguments as Map<String, dynamic>;
          final filhoId = args['filhoId'];

          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return null;

          return MaterialPageRoute(
            builder: (_) => FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(user.uid)
                  .collection('filhos')
                  .doc(filhoId)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final data =
                    snapshot.data!.data() as Map<String, dynamic>;

                final filho = Filho(
                  id: filhoId,
                  nome: data['nome'],
                  dataNascimento:
                      (data['dataNascimento'] as Timestamp).toDate(),
                  genero: data['genero'],
                  usuarioId: user.uid,
                  fotoUrl: data['fotoUrl'],
                );

                return HomePagefilhos(filho: filho);
              },
            ),
          );
        }
        return null;
      },
    );
  }
}
