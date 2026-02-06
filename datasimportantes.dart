import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:tcc_3/models/evento_vacina_model.dart';
import 'package:tcc_3/models/filho_model.dart';
import 'package:tcc_3/services/filho_service.dart';

class DatasImportantesScreen extends StatefulWidget {
  static const String routeName = '/datas_importantes';

  const DatasImportantesScreen({super.key});

  @override
  State<DatasImportantesScreen> createState() => _DatasImportantesScreenState();
}

class _DatasImportantesScreenState extends State<DatasImportantesScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FilhoService _filhoService = FilhoService();

  List<Filho> _filhos = [];
  Filho? _filhoSelecionado;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  DateTime? _inicio;
  DateTime? _fim;

  Map<DateTime, List<EventoVacina>> _eventos = {};
  Map<String, List<EventoVacina>> _vacinasPorFilho = {};

  bool _loading = true;

  // modo: "Calendário" ou "Datas Importantes"
  String _modoSelecionado = 'Calendário';

  @override
  void initState() {
    super.initState();
    _carregarFilhosEVacinas();
  }

  // ===============================
  // CARREGAMENTO INICIAL
  // ===============================
  Future<void> _carregarFilhosEVacinas() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      _filhos = await _filhoService.buscarFilhos(user.uid);

      await _carregarVacinasPorFilho(user.uid);

      if (_filhos.isNotEmpty) {
        _filhoSelecionado = _filhos.first;
        await _carregarEventosDoFilho(_filhoSelecionado!);
      } else {
        _inicio = DateTime.now().subtract(const Duration(days: 365));
        _fim = DateTime.now().add(const Duration(days: 365));
      }
    } catch (e) {
      debugPrint('Erro DatasImportantes: $e');
      _inicio = DateTime.now().subtract(const Duration(days: 365));
      _fim = DateTime.now().add(const Duration(days: 365));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===============================
  // VACINAS POR FILHO (LISTA)
  // ===============================
  Future<void> _carregarVacinasPorFilho(String uid) async {
    final Map<String, List<EventoVacina>> mapa = {};

    final catalogoSnap =
        await FirebaseFirestore.instance.collection('vaccines').get();

    final Map<String, dynamic> catalogo = {
      for (var d in catalogoSnap.docs) d.id: d.data()
    };

    for (final filho in _filhos) {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .collection('filhos')
          .doc(filho.id)
          .collection('vacinas')
          .get();

      final List<EventoVacina> lista = [];

      for (final doc in snap.docs) {
        final data = doc.data();

        final Timestamp? ts = data['dataPrevista'] as Timestamp?;
        final dynamic mesesRaw = data['meses'];

        if (ts == null && mesesRaw == null) continue;

        DateTime dataVacina = ts != null
            ? ts.toDate()
            : _calcularDataVacina(
                filho.dataNascimento,
                mesesRaw is int ? mesesRaw : int.tryParse(mesesRaw.toString()) ?? 0,
              );

        final nome =
            (data['nome'] as String?) ?? (catalogo[doc.id]?['nome'] as String?) ?? 'Vacina';

        final tomada = (data['tomada'] as bool?) ?? false;

        final doencas = (catalogo[doc.id]?['doencasEvitadas'] is List)
            ? (catalogo[doc.id]?['doencasEvitadas'] as List).map((e) => e.toString()).join(', ')
            : (data['descricao'] as String?) ?? '';

        lista.add(EventoVacina(
          nome: nome,
          descricao: doencas.isNotEmpty ? '$nome: $doencas' : nome,
          tomada: tomada,
          data: dataVacina,
        ));
      }

      lista.sort((a, b) => a.data.compareTo(b.data));
      mapa[filho.id] = lista;
    }

    if (mounted) setState(() => _vacinasPorFilho = mapa);
  }

  // ===============================
  // EVENTOS DO CALENDÁRIO
  // ===============================
  Future<void> _carregarEventosDoFilho(Filho filho) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .collection('filhos')
        .doc(filho.id)
        .collection('vacinas')
        .get();

    final Map<DateTime, List<EventoVacina>> eventos = {};

    for (final doc in snap.docs) {
      final data = doc.data();

      final Timestamp? ts = data['dataPrevista'] as Timestamp?;
      final dynamic mesesRaw = data['meses'];
      if (ts == null && mesesRaw == null) continue;

      DateTime dataVacina = ts != null
          ? ts.toDate()
          : _calcularDataVacina(
              filho.dataNascimento,
              mesesRaw is int ? mesesRaw : int.tryParse(mesesRaw.toString()) ?? 0,
            );

      final dia = DateTime(dataVacina.year, dataVacina.month, dataVacina.day);

      eventos.putIfAbsent(dia, () => []);
      eventos[dia]!.add(EventoVacina(
        nome: (data['nome'] as String?) ?? 'Vacina',
        descricao: (data['descricao'] as String?) ?? '',
        tomada: (data['tomada'] as bool?) ?? false,
        data: dataVacina,
      ));
    }

    final datas = eventos.keys.toList()..sort();

    if (mounted) {
      setState(() {
        _eventos = eventos;
        _inicio = filho.dataNascimento;
        _fim = datas.isNotEmpty
            ? datas.last.add(const Duration(days: 30))
            : DateTime.now().add(const Duration(days: 365));
        _focusedDay = _inicio!;
        _selectedDay = _inicio!;
      });
    }
  }

  // ===============================
  // UTIL
  // ===============================
  DateTime _calcularDataVacina(DateTime nasc, int meses) {
    final total = (nasc.month - 1) + meses;
    final ano = nasc.year + (total ~/ 12);
    final mes = (total % 12) + 1;
    final ultimoDia = DateTime(ano, mes + 1, 0).day;
    final dia = nasc.day > ultimoDia ? ultimoDia : nasc.day;
    return DateTime(ano, mes, dia);
  }

  String _idadeFormatada(DateTime nasc, DateTime data) {
    int anos = data.year - nasc.year;
    int meses = data.month - nasc.month;
    if (data.day < nasc.day) meses--;
    if (meses < 0) {
      anos--;
      meses += 12;
    }

    if (anos <= 0) {
      if (meses <= 1) return '$meses mês${meses == 1 ? '' : 'es'}';
      return '$meses meses';
    } else {
      if (meses == 0) return '$anos ano${anos == 1 ? '' : 's'}';
      return '$anos ano${anos == 1 ? '' : 's'} e $meses mês${meses == 1 ? '' : 'es'}';
    }
  }

  Color _statusColor(DateTime dataVacina, bool tomada) {
    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);
    final dataLimpa = DateTime(dataVacina.year, dataVacina.month, dataVacina.day);

    if (tomada) return Colors.blueAccent;
    if (isSameDay(dataLimpa, hojeLimpo)) return Colors.green;
    if (dataLimpa.isBefore(hojeLimpo)) return Colors.red;
    return Colors.amber.shade700;
  }

  String _statusText(DateTime dataVacina, bool tomada) {
    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);
    final dataLimpa = DateTime(dataVacina.year, dataVacina.month, dataVacina.day);

    if (tomada) return 'Tomada';
    if (isSameDay(dataLimpa, hojeLimpo)) return 'Hoje';
    if (dataLimpa.isBefore(hojeLimpo)) return 'Atrasada';
    return 'Futura';
  }

  Widget _statusBadge(EventoVacina v) {
    final color = _statusColor(v.data, v.tomada);
    final text = _statusText(v.data, v.tomada);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  // mostra modal com a lista de vacinas de um grupo (idade/data)
  Future<void> _showVacinasDoGrupo(BuildContext ctx, String titulo, List<EventoVacina> vacinas) {
    return showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Wrap(
            children: [
              Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.pink)),
              const SizedBox(height: 12),
              ...vacinas.map((v) {
                final dataFmt = DateFormat('dd/MM/yyyy').format(v.data);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.vaccines, color: Colors.green, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(dataFmt, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar', style: TextStyle(color: Colors.pink)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===============================
  // UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Datas Importantes', style: TextStyle(color: Colors.pink)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.pink),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // filtro de filho
          if (_filhos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<Filho>(
                value: _filhoSelecionado,
                decoration: const InputDecoration(
                  labelText: 'Selecione o filho',
                  border: OutlineInputBorder(),
                ),
                items: _filhos
                    .map((f) => DropdownMenuItem<Filho>(value: f, child: Text(f.nome)))
                    .toList(),
                onChanged: (novo) async {
                  if (novo == null) return;
                  setState(() => _loading = true);
                  _filhoSelecionado = novo;
                  await _carregarEventosDoFilho(novo);
                  if (mounted) setState(() => _loading = false);
                },
              ),
            ),

          // ChoiceChips para os dois modos
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Calendário'),
                  selected: _modoSelecionado == 'Calendário',
                  selectedColor: Colors.pink.shade100,
                  onSelected: (s) => setState(() => _modoSelecionado = 'Calendário'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Datas Importantes'),
                  selected: _modoSelecionado == 'Datas Importantes',
                  selectedColor: Colors.pink.shade100,
                  onSelected: (s) => setState(() => _modoSelecionado = 'Datas Importantes'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // conteúdo principal
          Expanded(
            child: _modoSelecionado == 'Calendário' ? _buildCalendario() : _buildDatasImportantesList(),
          ),
        ],
      ),
    );
  }

  // ===============================
  // BUILD: CALENDÁRIO
  // ===============================
  Widget _buildCalendario() {
    final eventosDia = _selectedDay != null
        ? _eventos[DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day)] ?? []
        : [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: TableCalendar<EventoVacina>(
            locale: 'pt_BR',
            firstDay: _inicio ?? DateTime.now().subtract(const Duration(days: 365)),
            lastDay: _fim ?? DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: (day) => _eventos[DateTime(day.year, day.month, day.day)] ?? [],
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              leftChevronIcon: Icon(Icons.chevron_left, color: Colors.pink),
              rightChevronIcon: Icon(Icons.chevron_right, color: Colors.pink),
            ),
            calendarStyle: const CalendarStyle(
              outsideDaysVisible: false,
              todayDecoration: BoxDecoration(color: Colors.transparent, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(color: Colors.pink, shape: BoxShape.circle),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return const SizedBox.shrink();
                final itens = events.cast<EventoVacina>();
                final markers = itens.map((ev) {
                  final color = _statusColor(ev.data, ev.tomada);
                  return Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  );
                }).toList();

                return Positioned(
                  bottom: 6,
                  child: Row(mainAxisSize: MainAxisSize.min, children: markers.take(4).toList()),
                );
              },
              todayBuilder: (context, day, focusedDay) {
                return Container(
                  margin: const EdgeInsets.all(6.0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: Text('${day.day}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                );
              },
            ),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
            },
            onPageChanged: (focused) {
              _focusedDay = focused;
            },
          ),
        ),
        const SizedBox(height: 8),
        // Área rosa abaixo do calendário (apresenta vacinas do dia selecionado)
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.pink.shade100,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: _selectedDay == null
                  ? const Center(child: Text('Selecione um dia para ver as vacinas', style: TextStyle(color: Colors.pinkAccent, fontSize: 16)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat("d 'de' MMMM yyyy", 'pt_BR').format(_selectedDay!),
                          style: const TextStyle(color: Colors.pink, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('${eventosDia.length} vacina(s)', style: TextStyle(color: Colors.pink.shade700)),
                        const SizedBox(height: 12),
                        Expanded(
                          child: eventosDia.isEmpty
                              ? const Center(child: Text('Nenhuma vacina neste dia', style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: eventosDia.length,
                                  itemBuilder: (context, i) {
                                    final e = eventosDia[i];
                                    final idadeTexto = _filhoSelecionado != null
                                        ? _idadeFormatada(_filhoSelecionado!.dataNascimento, e.data)
                                        : '';
                                    final dataFormatada = DateFormat('dd/MM/yyyy').format(e.data);

                                    return Card(
                                      color: Colors.white,
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                                              child: const Icon(Icons.vaccines, color: Colors.green, size: 26),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(e.nome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Text(idadeTexto, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                                                      const SizedBox(width: 8),
                                                      const Text('•', style: TextStyle(color: Colors.grey)),
                                                      const SizedBox(width: 8),
                                                      Text(dataFormatada, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  e.descricao.isNotEmpty ? Text(e.descricao, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)) : const SizedBox(),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              children: [
                                                _statusBadge(e),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ===============================
  // BUILD: DATAS IMPORTANTES (LISTA)
  // ===============================
  Widget _buildDatasImportantesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filhos.length,
      itemBuilder: (context, index) {
        final filho = _filhos[index];
        final vacinas = _vacinasPorFilho[filho.id] ?? [];

        // Agrupa vacinas por rótulo de idade + data (ex: "4 anos - Data prevista: dd/mm/yyyy")
        final Map<String, List<EventoVacina>> grupos = {};
        for (final v in vacinas) {
          final idade = _idadeFormatada(filho.dataNascimento, v.data);
          final dataFmt = DateFormat('dd/MM/yyyy').format(v.data);
          final chave = '$idade - Data prevista: $dataFmt';
          grupos.putIfAbsent(chave, () => []).add(v);
        }

        // ordenar por data da primeira vacina de cada grupo
        final List<MapEntry<String, List<EventoVacina>>> entradas = grupos.entries.toList()
          ..sort((a, b) {
            final da = a.value.first.data;
            final db = b.value.first.data;
            return da.compareTo(db);
          });

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filho.nome, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 4),
                Text('Nascimento: ${DateFormat('dd/MM/yyyy').format(filho.dataNascimento)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
            children: entradas.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Nenhuma vacina encontrada para esse filho.', style: TextStyle(color: Colors.grey)),
                    )
                  ]
                : entradas.map((entry) {
                    final label = entry.key;
                    final listaVacinas = entry.value;
                    final primeiraDataFmt = DateFormat('dd/MM/yyyy').format(listaVacinas.first.data);

                    return ListTile(
                      onTap: () => _showVacinasDoGrupo(context, 'Vacinas - ${label.split(' - ').first}', listaVacinas),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.calendar_today, color: Colors.blue),
                      ),
                      title: Text(label.split(' - ').first, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Data prevista: $primeiraDataFmt'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // badge do primeiro item do grupo (exibe Atrasada/Hoje/Futura/Tomada)
                          _statusBadge(listaVacinas.first),
                          const SizedBox(width: 8),
                          const Icon(Icons.keyboard_arrow_right),
                        ],
                      ),
                    );
                  }).toList(),
          ),
        );
      },
    );
  }
}