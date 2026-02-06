import 'dart:async';
import 'package:tcc_3/models/notificacao_model.dart';

class AppNotification {
  AppNotification._internal();

  static final AppNotification instance = AppNotification._internal();

  // Inicialização sem nulls
  Future<void> initialize({bool requestPermissions = true}) async {
    print('AppNotification inicializado. Permissões: $requestPermissions');
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String payload = '', // Valor padrão vazio em vez de null
  }) async {
    print('Exibindo agora: $title - $body');
  }

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String payload = '', // Valor padrão vazio em vez de null
  }) async {
    print('Agendado para $when: $title');
  }

  Future<void> cancelAllNotifications() async {
    print('Todas as notificações locais foram canceladas.');
  }
}