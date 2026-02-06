import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:tcc_3/services/filho_service.dart';

class NotificacoesScreen extends StatefulWidget {
  static const String routeName = '/notificacoes';

  const NotificacoesScreen({super.key});

  @override
  State<NotificacoesScreen> createState() => _NotificacoesScreenState();
}

class _NotificacoesScreenState extends State<NotificacoesScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FilhoService _filhoService = FilhoService();

  List<Map<String, dynamic>> _notificacoes = [];
  bool _isLoading = true;

  /// 🔘 Filtro por filho (null = todos)
  String? _filhoSelecionadoId;

  @override
  void initState() {
    super.initState();
    _carregarNotificacoes();
  }

  // ===============================
  // 🔄 CARGA DAS NOTIFICAÇÕES
  // ===============================
  Future<void> _carregarNotificacoes() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final filhos = await _filhoService.buscarFilhos(user.uid);
      final vacinasSnapshot =
          await FirebaseFirestore.instance.collection('vaccines').get();

      final List<Map<String, dynamic>> lista = [];
      final hoje = DateTime.now();
      final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);

      for (final filho in filhos) {
        // Busca vacinas do filho para verificar quais já foram tomadas
        final vacinasFilhoSnap = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(user.uid)
            .collection('filhos')
            .doc(filho.id)
            .collection('vacinas')
            .get();

        // Mapa de vacinas tomadas (vaccineId -> tomada)
        final vacinasTomadas = <String, bool>{};
        for (final vDoc in vacinasFilhoSnap.docs) {
          vacinasTomadas[vDoc.id] = vDoc.data()['tomada'] == true;
        }

        for (final doc in vacinasSnapshot.docs) {
          final data = doc.data();
          final nome = data['nome'];
          final meses = data['meses'];

          if (nome == null || meses == null) continue;

          // Pula vacinas já tomadas
          if (vacinasTomadas[doc.id] == true) continue;

          final dataPrevista =
              _calcularDataVacina(filho.dataNascimento, meses);

          final dataLimpa = DateTime(
            dataPrevista.year,
            dataPrevista.month,
            dataPrevista.day,
          );

          final dias = dataLimpa.difference(hojeLimpo).inDays;

          Color cor;
          IconData icone;

          if (dias < 0) {
            cor = Colors.red.shade300;
            icone = Icons.warning;
          } else if (dias == 0) {
            cor = Colors.green.shade400;
            icone = Icons.today;
          } else {
            cor = Colors.blue.shade300;
            icone = Icons.schedule;
          }

          lista.add({
            'filho': filho.nome,
            'filhoId': filho.id,
            'vacina': nome,
            'dataReal': dataLimpa,
            'dataFormatada':
                DateFormat('dd/MM/yyyy').format(dataLimpa),
            'cor': cor,
            'icone': icone,
            'dias': dias,
            'status': dias < 0
                ? 'ATRASADA'
                : dias == 0
                    ? 'HOJE'
                    : 'EM $dias DIAS',
          });
        }
      }

      lista.sort(
        (a, b) =>
            (a['dataReal'] as DateTime)
                .compareTo(b['dataReal'] as DateTime),
      );

      setState(() {
        _notificacoes = lista;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ===============================
  // 🧠 FILTRO APENAS POR FILHO
  // ===============================
  List<Map<String, dynamic>> get _notificacoesFiltradas {
    if (_filhoSelecionadoId == null) {
      return _notificacoes;
    }

    return _notificacoes
        .where((n) => n['filhoId'] == _filhoSelecionadoId)
        .toList();
  }

  // ===============================
  // 📅 CÁLCULO DA DATA DA VACINA
  // ===============================
  DateTime _calcularDataVacina(DateTime nascimento, int meses) {
    final totalMeses = (nascimento.month - 1) + meses;
    final ano = nascimento.year + (totalMeses ~/ 12);
    final mes = (totalMeses % 12) + 1;

    final ultimoDia = DateTime(ano, mes + 1, 0).day;
    final dia =
        nascimento.day > ultimoDia ? ultimoDia : nascimento.day;

    return DateTime(ano, mes, dia);
  }

  // ===============================
  // 🧱 UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    final filtradas = _notificacoesFiltradas;

    /// lista única de filhos (para os chips)
    final filhosUnicos = {
      for (var n in _notificacoes)
        n['filhoId']: n['filho'],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notificações',
          style: TextStyle(
            color: Colors.pink,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.pink),
      ),
      body: Column(
        children: [
          // 🎯 FILTRO POR FILHO
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilhoChip(
                    label: 'TODOS',
                    filhoId: null,
                  ),
                  const SizedBox(width: 8),
                  ...filhosUnicos.entries.map(
                    (e) => Padding(
                      padding:
                          const EdgeInsets.only(right: 8),
                      child: _buildFilhoChip(
                        label: e.value,
                        filhoId: e.key,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 📊 CONTADOR
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtradas.length} vacina(s)',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ),
          ),

          // 📋 LISTA
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : filtradas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 64,
                              color:
                                  Colors.green.shade300,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '🎉 VACINAÇÃO EM DIA!',
                              style: TextStyle(
                                color: Colors.pink,
                                fontWeight:
                                    FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Nenhuma vacina para este filho',
                              style: TextStyle(
                                  color:
                                      Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh:
                            _carregarNotificacoes,
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.all(12),
                          itemCount: filtradas.length,
                          itemBuilder: (_, i) {
                            final n = filtradas[i];
                            final cor =
                                n['cor'] as Color;

                            return Card(
                              elevation: 3,
                              margin:
                                  const EdgeInsets.only(
                                      bottom: 10),
                              shape:
                                  RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius
                                        .circular(12),
                                side: BorderSide(
                                    color: cor,
                                    width: 2),
                              ),
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets
                                        .all(12),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      cor,
                                  child: Icon(
                                    n['icone']
                                        as IconData,
                                    color:
                                        Colors.white,
                                  ),
                                ),
                                title: Text(
                                  '${n['filho']} – ${n['vacina']}',
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight
                                              .bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(n[
                                        'dataFormatada']),
                                    Text(
                                      n['status'],
                                      style: TextStyle(
                                        color: cor,
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ===============================
  // 🎛️ CHIP DE FILHO
  // ===============================
  Widget _buildFilhoChip({
    required String label,
    required String? filhoId,
  }) {
    final selecionado =
        _filhoSelecionadoId == filhoId;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color:
              selecionado ? Colors.white : Colors.pink,
          fontWeight: FontWeight.bold,
        ),
      ),
      selected: selecionado,
      selectedColor: Colors.pink,
      backgroundColor: Colors.white,
      onSelected: (_) {
        setState(() {
          _filhoSelecionadoId = filhoId;
        });
      },
      shape: StadiumBorder(
        side: BorderSide(
          color: Colors.pink.shade100,
        ),
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
  }
}
