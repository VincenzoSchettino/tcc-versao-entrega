import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:tcc_3/models/filho_model.dart';

class FilhoService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String collectionName = 'usuarios';

  // ==============================================================
  // 🔍 BUSCAR FILHOS
  // ==============================================================
  Future<List<Filho>> buscarFilhos(String userId) async {
    final snapshot = await _db
        .collection(collectionName)
        .doc(userId)
        .collection('filhos')
        .orderBy('dataNascimento', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => Filho.fromFirestore(doc.data(), doc.id))
        .toList();
  }

  // ==============================================================
  // ➕ ADICIONAR FILHO (SEM NOTIFICAÇÃO)
  // ==============================================================
  Future<String> adicionarFilho(String userId, Filho filho) async {
    final docRef = _db
        .collection(collectionName)
        .doc(userId)
        .collection('filhos')
        .doc();

    final filhoComId = filho.copyWith(id: docRef.id);

    await docRef.set(filhoComId.toMap());

    // ✅ Apenas inicializa vacinas (SEM notificação)
    await inicializarStatusVacinas(
      usuarioId: userId,
      filhoId: docRef.id,
    );

    debugPrint("✅ Filho criado: ${docRef.id}");
    return docRef.id;
  }

  // ==============================================================
  // ⚙️ INICIALIZAR VACINAS (DADOS APENAS)
  // ==============================================================
  Future<void> inicializarStatusVacinas({
    required String usuarioId,
    required String filhoId,
  }) async {
    final catalogo = await _db.collection('vaccines').get();
    final batch = _db.batch();

    for (var doc in catalogo.docs) {
      final ref = _db
          .collection(collectionName)
          .doc(usuarioId)
          .collection('filhos')
          .doc(filhoId)
          .collection('vacinas')
          .doc(doc.id);

      batch.set(ref, {
        'nome': doc['nome'],
        'meses': doc['meses'],
        'tomada': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    debugPrint('✅ Vacinas inicializadas');
  }

  // ==============================================================
  // ✏️ ATUALIZAR FILHO (SEM NOTIFICAÇÃO)
  // ==============================================================
  Future<void> atualizarFilho(String userId, Filho filho) async {
    final ref = _db
        .collection(collectionName)
        .doc(userId)
        .collection('filhos')
        .doc(filho.id);

    await ref.update({
      'nome': filho.nome,
      'dataNascimento': Timestamp.fromDate(filho.dataNascimento),
      'genero': filho.genero,
      'fotoUrl': filho.fotoUrl ?? '',
    });

    debugPrint("✏️ Filho atualizado");
  }

  // ==============================================================
  // 🗑️ EXCLUIR FILHO (SEM NOTIFICAÇÃO)
  // ==============================================================
  Future<void> excluirFilho(String userId, String filhoId) async {
    await _db
        .collection(collectionName)
        .doc(userId)
        .collection('filhos')
        .doc(filhoId)
        .delete();

    debugPrint("🗑️ Filho excluído");
  }

  // ==============================================================
  // 🔍 BUSCAR FILHO POR ID
  // ==============================================================
  Future<Filho> buscarFilhoPorId({
    required String usuarioId,
    required String filhoId,
  }) async {
    final doc = await _db
        .collection(collectionName)
        .doc(usuarioId)
        .collection('filhos')
        .doc(filhoId)
        .get();

    if (!doc.exists) throw Exception('Filho não encontrado');

    return Filho.fromFirestore(doc.data()!, doc.id);
  }
}
