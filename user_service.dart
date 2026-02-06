import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:tcc_3/services/app_notification.dart';
import 'package:tcc_3/models/notificacao_model.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // =====================================================
  // 🔔 BUSCAR NOTIFICAÇÕES DO USUÁRIO (Firestore)
  // =====================================================
  Future<List<Notificacao>> getNotificacoes(String userId) async {
    try {
      final snapshot = await _db
          .collection('usuarios')
          .doc(userId)
          .collection('notificacoes')
          .orderBy('data', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Notificacao.fromDoc(doc))
          .toList();
    } catch (e) {
      print('❌ Erro ao buscar notificações: $e');
      return [];
    }
  }

  // =====================================================
  // 🔔 AGENDAR NOTIFICAÇÕES PARA TODOS OS FILHOS
  // =====================================================
  Future<void> agendarNotificacoesParaTodosFilhos(String userId) async {
    try {
      print("🔄 Atualizando agendamentos de vacinas...");

      final birthDates = await getBirthDates(userId);

      for (final child in birthDates) {
        final dynamic ts = child['data_nascimento'];
        if (ts == null) continue;

        DateTime birthDate;
        if (ts is Timestamp) {
          birthDate = ts.toDate();
        } else if (ts is DateTime) {
          birthDate = ts;
        } else {
          continue;
        }

        final String filhoId = child['id'] ?? '';
        if (filhoId.isEmpty) continue;

        final listaVacinas = _calculateVaccineDates(birthDate);

        for (final vacinaItem in listaVacinas) {
          final String nomeVacina = vacinaItem['vacina'];
          final DateTime dataVacina = vacinaItem['data'];

          bool isHoje(DateTime data) {
            final now = DateTime.now();
            return data.year == now.year &&
                data.month == now.month &&
                data.day == now.day;
          }

          int mesesEntreDatas(DateTime inicio, DateTime fim) {
            return (fim.year - inicio.year) * 12 +
                (fim.month - inicio.month);
          }

          String payloadJson(Map<String, dynamic> data) {
            return jsonEncode(data);
          }

          final payloadBase = {
            'rota': '/datas_importantes',
            'filhoId': filhoId,
            'meses': mesesEntreDatas(birthDate, dataVacina),
            'vacinas': [nomeVacina],
          };

          // =================================================
          // 🟢 HOJE → NOTIFICAÇÃO IMEDIATA
          // =================================================
          if (isHoje(dataVacina)) {
            try {
              await AppNotification.instance.show(
                id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                title: '🍼 Hoje é dia de vacinação',
                body:
                    'Leve a criança para tomar a vacina $nomeVacina hoje.',
                payload: payloadJson(payloadBase),
              );
            } catch (e) {
              print('❌ AppNotification.show falhou: $e');
            }
            continue;
          }

          // =================================================
          // 🟡 FUTURO → D-7 e D-3 (08:00)
          // =================================================
          for (final dias in [7, 3]) {
            final dataAviso =
                dataVacina.subtract(Duration(days: dias));
            final dataNotificacao = DateTime(
              dataAviso.year,
              dataAviso.month,
              dataAviso.day,
              8,
              0,
            );

            if (dataNotificacao.isBefore(DateTime.now())) continue;

            final int idUnico =
                (nomeVacina.hashCode + dias + filhoId.hashCode)
                    .abs();

            try {
              await AppNotification.instance.schedule(
                id: idUnico,
                title: '📅 Vacinação próxima',
                body:
                    'Faltam $dias dias para a vacina $nomeVacina.',
                dateTime: dataNotificacao,
                payload: payloadJson(payloadBase),
              );
            } catch (e) {
              print('❌ AppNotification.schedule falhou: $e');
            }
          }
        }
      }

      print("✅ Notificações configuradas com sucesso!");
    } catch (e) {
      print("❌ Erro geral ao agendar notificações: $e");
    }
  }

  // =====================================================
  // 📅 CALENDÁRIO PADRÃO DE VACINAS
  // =====================================================
  List<Map<String, dynamic>> _calculateVaccineDates(
      DateTime birthDate) {
    final Map<String, int> vaccineSchedule = {
      'BCG': 0,
      'Hepatite B': 0,
      'Pentavalente (1ª dose)': 60,
      'VIP (1ª dose)': 60,
      'Rotavírus (1ª dose)': 60,
      'Pneumocócica 10V (1ª dose)': 60,
      'Meningocócica C (1ª dose)': 90,
      'Pentavalente (2ª dose)': 120,
      'VIP (2ª dose)': 120,
      'Pneumocócica 10V (2ª dose)': 120,
      'Rotavírus (2ª dose)': 120,
      'Meningocócica C (2ª dose)': 150,
      'Pentavalente (3ª dose)': 180,
      'VIP (3ª dose)': 180,
      'Febre Amarela': 270,
      'Tríplice Viral': 365,
      'Pneumocócica 10V (Reforço)': 365,
      'Meningocócica C (Reforço)': 365,
      'Hepatite A': 450,
      'Tetra Viral': 450,
      'DTP (1º Reforço)': 450,
      'VOP (1º Reforço)': 450,
      'DTP (2º Reforço)': 1460,
      'VOP (2º Reforço)': 1460,
      'Varicela (2ª dose)': 1460,
      'HPV (1ª dose)': 3285,
      'Meningocócica ACWY': 3942,
    };

    final List<Map<String, dynamic>> vaccineDates = [];

    vaccineSchedule.forEach((vacina, dias) {
      final dataVacina =
          birthDate.add(Duration(days: dias));

      vaccineDates.add({
        'vacina': vacina,
        'data': dataVacina,
      });
    });

    return vaccineDates;
  }

  // =====================================================
  // 👤 CRUD DE USUÁRIO E FILHOS
  // =====================================================
  Future<void> createUser(Map<String, dynamic> userData) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('usuarios').doc(user.uid).set(userData);
    }
  }

  Future<DocumentSnapshot> getUserData(String userId) {
    return _db.collection('usuarios').doc(userId).get();
  }

  Future<void> updateUserData(
      String userId, Map<String, dynamic> data) {
    return _db.collection('usuarios').doc(userId).update(data);
  }

  Future<void> deleteUser(String userId) {
    return _db.collection('usuarios').doc(userId).delete();
  }

  Future<DocumentReference> addChild(
      String userId, Map<String, dynamic> childData) async {
    final docRef = await _db
        .collection('usuarios')
        .doc(userId)
        .collection('filhos')
        .add(childData);

    await _db.collection('datanasc').doc(docRef.id).set({
      'userId': userId,
      'data_nascimento': childData['data_nascimento'],
      'timestamp': FieldValue.serverTimestamp(),
    });

    return docRef;
  }

  Future<List<Map<String, dynamic>>> getBirthDates(
      String userId) async {
    final snapshot = await _db
        .collection('datanasc')
        .where('userId', isEqualTo: userId)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<void> updateChild(
      String userId, String childId, Map<String, dynamic> data) {
    return _db
        .collection('usuarios')
        .doc(userId)
        .collection('filhos')
        .doc(childId)
        .update(data);
  }

  Future<void> deleteChild(String userId, String childId) async {
    await _db
        .collection('usuarios')
        .doc(userId)
        .collection('filhos')
        .doc(childId)
        .delete();

    await _db.collection('datanasc').doc(childId).delete();
  }
}
