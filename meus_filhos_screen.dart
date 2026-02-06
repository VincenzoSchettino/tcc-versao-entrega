import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:tcc_3/models/filho_model.dart';
import 'package:tcc_3/services/filho_service.dart';
import 'package:tcc_3/views/cadastrar_vacinas_screenfilho.dart';
import 'package:tcc_3/views/home_page_filhos.dart';
import 'package:tcc_3/views/vacinas_tomadas.dart';

class MeusFilhosPage extends StatefulWidget {
  static const String routeName = '/lista_filhos';
  const MeusFilhosPage({super.key});

  @override
  State<MeusFilhosPage> createState() => _MeusFilhosPageState();
}

class _MeusFilhosPageState extends State<MeusFilhosPage> {
  final FilhoService _filhoService = FilhoService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ===============================
  // 📅 CALCULAR IDADE
  // ===============================
  String _calcularIdade(DateTime nascimento) {
    final now = DateTime.now();
    int years = now.year - nascimento.year;
    int months = now.month - nascimento.month;

    if (now.day < nascimento.day) months--;
    if (months < 0) {
      years--;
      months += 12;
    }

    final totalMonths = years * 12 + months;
    if (totalMonths < 12) return '$totalMonths meses';

    final anos = totalMonths ~/ 12;
    return '$anos ${anos == 1 ? 'ano' : 'anos'}';
  }

  // ===============================
  // 📅 DATA DA VACINA
  // ===============================
  DateTime _calcularDataVacina(DateTime nascimento, int meses) {
    final totalMeses = (nascimento.month - 1) + meses;
    final ano = nascimento.year + (totalMeses ~/ 12);
    final mes = (totalMeses % 12) + 1;

    final ultimoDia = DateTime(ano, mes + 1, 0).day;
    final dia = nascimento.day > ultimoDia ? ultimoDia : nascimento.day;

    return DateTime(ano, mes, dia);
  }

  // ===============================
  // 🔔 PUSH IMEDIATO (VACINA HOJE)
  // ===============================
  Future<void> _dispararPushVacinaHoje(Filho filho) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);

    // 🔹 pega fcmToken
    final userDoc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .get();

    final fcmToken = userDoc.data()?['fcmToken'];
    if (fcmToken == null) return;

    // 🔹 vacinas NÃO tomadas do filho
    final vacinasSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .collection('filhos')
        .doc(filho.id)
        .collection('vacinas')
        .where('tomada', isEqualTo: false)
        .get();

    for (final doc in vacinasSnap.docs) {
      final data = doc.data();
      final meses = data['meses'];
      final nomeVacina = data['nome'];

      if (meses == null || nomeVacina == null) continue;

      final dataVacina = _calcularDataVacina(filho.dataNascimento, meses);

      final dataLimpa = DateTime(
        dataVacina.year,
        dataVacina.month,
        dataVacina.day,
      );

      // 🎯 vacina é HOJE
      if (dataLimpa == hojeLimpo) {
        await FirebaseFirestore.instance.collection('notificacoes').add({
          'fcmToken': fcmToken,
          'titulo': 'Vacina hoje!',
          'mensagem': '${filho.nome} precisa tomar "$nomeVacina" hoje',
          'rota': '/home-filho',
          'filhoId': filho.id,
          'criadoEm': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // ===============================
  // ➕ CADASTRAR NOVO FILHO
  // ===============================
  Future<void> _cadastrarNovoFilho(User user) async {
    // 1️⃣ Cadastro do filho
    final Filho? filhoCriado = await Navigator.push<Filho>(
      context,
      MaterialPageRoute(
        builder: (_) => const CadastroFilhoScreen(),
      ),
    );

    if (filhoCriado == null || !mounted) return;

    // 2️⃣ Marca vacinas já tomadas
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VacinasTomadasScreen(
          usuarioId: user.uid,
          filho: filhoCriado,
        ),
      ),
    );

    if (!mounted) return;

    // 🔔 PUSH IMEDIATO SE VACINA FOR HOJE
    await FirebaseFirestore.instance.collection('notificacoes').add({
      'uid': FirebaseAuth.instance.currentUser!.uid,
      'titulo': 'Vacina hoje!',
      'mensagem': '${filhoCriado.nome} precisa tomar "Hepatite B" hoje',
      'rota': '/home-filho',
      'filhoId': filhoCriado.id,
      'criadoEm': FieldValue.serverTimestamp(),
    });

    // 3️⃣ Vai para home do filho
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HomePagefilhos(filho: filhoCriado),
      ),
    );
  }

  // ===============================
  // 🧱 BUILD
  // ===============================
  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.pink),
          onPressed: () {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (route) => false,
            );
          },
        ),
        title: const Text(
          'Meus Filhos',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.pink,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.pink),
      ),
      floatingActionButton: user == null
          ? const SizedBox.shrink()
          : FloatingActionButton(
              backgroundColor: Colors.pink,
              onPressed: () => _cadastrarNovoFilho(user),
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: user == null
          ? const Center(child: Text('Usuário não autenticado'))
          : FutureBuilder<List<Filho>>(
              future: _filhoService.buscarFilhos(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final filhos = snapshot.data ?? [];

                if (filhos.isEmpty) {
                  return const Center(child: Text('Nenhum filho cadastrado'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filhos.length,
                  itemBuilder: (context, index) {
                    final filho = filhos[index];
                    final idade = _calcularIdade(filho.dataNascimento);
                    final fotoUrl = (filho.fotoUrl ?? '').trim();
                    final hasPhoto = fotoUrl.isNotEmpty;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundImage:
                                  hasPhoto ? NetworkImage(fotoUrl) : null,
                              child: !hasPhoto
                                  ? Text(
                                      filho.nome[0].toUpperCase(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          HomePagefilhos(filho: filho),
                                    ),
                                  );
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      filho.nome,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Idade: $idade',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CadastroFilhoScreen(
                                        filhoExistente: filho),
                                  ),
                                );
                                if (!mounted) return;
                                setState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                final confirmar = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Excluir filho'),
                                    content:
                                        Text('Deseja excluir ${filho.nome}?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red),
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text(
                                          'Excluir',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmar == true) {
                                  await _filhoService.excluirFilho(
                                      user.uid, filho.id);
                                  if (!mounted) return;
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
