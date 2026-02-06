import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_auth/firebase_auth.dart';

class NotificationSchedulerService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> agendarVacinasSemanaAntes({
    required String filhoId,
    required String nomeFilho,
    required DateTime dataNascimento,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 🔥 Cancela apenas notificações desse filho
    await _cancelarNotificacoesDoFilho(filhoId);

    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .collection('filhos')
        .doc(filhoId)
        .collection('vacinas')
        .where('tomada', isEqualTo: false)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final int? meses = data['meses'];
      final String? nomeVacina = data['nome'];

      if (meses == null || nomeVacina == null) continue;

      final dataVacina = _calcularDataVacina(dataNascimento, meses);

      final dataNotificacao = dataVacina.subtract(const Duration(days: 7));

      if (dataNotificacao.isBefore(DateTime.now())) continue;

      await _notifications.zonedSchedule(
        _gerarIdUnico(filhoId, nomeVacina),
        'Vacina próxima',
        '$nomeFilho precisa tomar $nomeVacina em 7 dias',
        tz.TZDateTime.from(dataNotificacao, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'vacinas_7_dias',
            'Vacinas - 7 dias antes',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  static Future<void> _cancelarNotificacoesDoFilho(String filhoId) async {
    final pending = await _notifications.pendingNotificationRequests();

    for (final n in pending) {
      if (n.id.toString().contains(filhoId.hashCode.toString())) {
        await _notifications.cancel(n.id);
      }
    }
  }

  static int _gerarIdUnico(String filhoId, String vacina) {
    return '${filhoId}_$vacina'.hashCode & 0x7FFFFFFF;
  }

  static DateTime _calcularDataVacina(DateTime nascimento, int meses) {
    final totalMeses = (nascimento.month - 1) + meses;
    final ano = nascimento.year + (totalMeses ~/ 12);
    final mes = (totalMeses % 12) + 1;

    final ultimoDia = DateTime(ano, mes + 1, 0).day;
    final dia = nascimento.day > ultimoDia ? ultimoDia : nascimento.day;

    return DateTime(ano, mes, dia);
  }
}
