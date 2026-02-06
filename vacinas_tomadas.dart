import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:tcc_3/models/filho_model.dart';

class VacinasTomadasScreen extends StatefulWidget {
  final String usuarioId;
  final Filho filho;

  const VacinasTomadasScreen({
    super.key,
    required this.usuarioId,
    required this.filho,
  });

  @override
  State<VacinasTomadasScreen> createState() => _VacinasTomadasScreenState();
}

class _VacinasTomadasScreenState extends State<VacinasTomadasScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// caminho:
  /// usuarios/{uid}/filhos/{filhoId}/vacinas
  CollectionReference get _vacinasRef =>
      _firestore
          .collection('usuarios')
          .doc(widget.usuarioId)
          .collection('filhos')
          .doc(widget.filho.id)
          .collection('vacinas');

  Future<void> _toggleVacina(
    String vacinaId,
    bool tomadaAtual,
  ) async {
    await _vacinasRef.doc(vacinaId).update({
      'tomada': !tomadaAtual,
      'dataAtualizacao': Timestamp.now(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.pink),
        title: const Text(
          'Vacinas Tomadas',
          style: TextStyle(
            color: Colors.pink,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: _vacinasRef.orderBy('meses').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Erro ao carregar vacinas'),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('Nenhuma vacina cadastrada'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final String nome = data['nome'] ?? 'Vacina';
              final bool tomada = data['tomada'] ?? false;
              final int meses = data['meses'] ?? 0;

              final periodo = meses < 12
                  ? '$meses meses'
                  : '${meses ~/ 12} anos';

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CheckboxListTile(
                  value: tomada,
                  activeColor: Colors.green,
                  title: Text(
                    nome,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: tomada ? Colors.green : Colors.black,
                    ),
                  ),
                  subtitle: Text(
                    'Período: $periodo',
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                  onChanged: (_) =>
                      _toggleVacina(doc.id, tomada),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
