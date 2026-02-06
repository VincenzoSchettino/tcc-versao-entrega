// lib/models/notificacao_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Notificacao {
  final String id;
  final String titulo;
  final String mensagem;
  final DateTime data;
  final bool lida;

  Notificacao({
    required this.id,
    required this.titulo,
    required this.mensagem,
    required this.data,
    required this.lida,
  });

  factory Notificacao.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Timestamp? ts = data['data'] as Timestamp?;
    return Notificacao(
      id: doc.id,
      titulo: (data['titulo'] as String?) ?? '',
      mensagem: (data['mensagem'] as String?) ?? '',
      data: ts?.toDate() ?? DateTime.now(),
      lida: (data['lida'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'titulo': titulo,
      'mensagem': mensagem,
      'data': Timestamp.fromDate(data),
      'lida': lida,
    };
  }
}