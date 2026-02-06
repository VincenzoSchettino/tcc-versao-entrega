import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:tcc_3/models/filho_model.dart';
import 'package:tcc_3/services/filho_service.dart';

class CadastroFilhoScreen extends StatefulWidget {
  final Filho? filhoExistente;

  const CadastroFilhoScreen({super.key, this.filhoExistente});

  @override
  State<CadastroFilhoScreen> createState() => _CadastroFilhoScreenState();
}

class _CadastroFilhoScreenState extends State<CadastroFilhoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();

  DateTime _dataNascimento = DateTime.now();
  String _genero = 'Masculino';

  final FilhoService _filhoService = FilhoService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  File? _imagemSelecionada;
  String? _fotoUrl;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    if (widget.filhoExistente != null) {
      _nomeController.text = widget.filhoExistente!.nome;
      _dataNascimento = widget.filhoExistente!.dataNascimento;
      _genero = widget.filhoExistente!.genero;
      _fotoUrl = widget.filhoExistente!.fotoUrl;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    super.dispose();
  }

  // ====
  // 📷 SELECIONAR IMAGEM
  // ====
  Future<void> _selecionarImagem() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (picked != null) {
        setState(() => _imagemSelecionada = File(picked.path));
      }
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao selecionar imagem')),
        );
      }
    }
  }

  // ====
  // ☁️ UPLOAD IMAGEM (FIREBASE STORAGE)
  // ====
  Future<String?> _uploadImagem(String filhoId) async {
    if (_imagemSelecionada == null) return _fotoUrl;

    try {
      final user = _auth.currentUser;
      if (user == null) return _fotoUrl;

      final ref = FirebaseStorage.instance
          .ref()
          .child('fotos_filhos')
          .child(user.uid)
          .child('$filhoId.jpg');

      await ref.putFile(_imagemSelecionada!);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      debugPrint('Erro no upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao enviar foto, salvando sem foto')),
        );
      }
      return _fotoUrl;
    }
  }

  // ====
  // 💾 SALVAR FILHO
  // ====
  Future<void> _salvarFilho() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _salvando = true);

    try {
      final filhoId = widget.filhoExistente?.id ?? _uuid.v4();
      String? fotoFinal = _fotoUrl;

      if (_imagemSelecionada != null) {
        fotoFinal = await _uploadImagem(filhoId);
      }

      // ✏️ EDIÇÃO
      if (widget.filhoExistente != null) {
        final atualizado = widget.filhoExistente!.copyWith(
          nome: _nomeController.text.trim(),
          dataNascimento: _dataNascimento,
          genero: _genero,
          fotoUrl: fotoFinal,
        );

        await _filhoService.atualizarFilho(user.uid, atualizado);

        if (!mounted) return;
        Navigator.pop(context);
        return;
      }

      // ➕ NOVO FILHO
      final novo = Filho(
        id: 'TEMP',
        nome: _nomeController.text.trim(),
        dataNascimento: _dataNascimento,
        genero: _genero,
        usuarioId: user.uid,
        fotoUrl: fotoFinal,
      );

      final novoFilhoId = await _filhoService.adicionarFilho(user.uid, novo);

      await _filhoService.inicializarStatusVacinas(
        usuarioId: user.uid,
        filhoId: novoFilhoId,
      );

      final filhoCriado = await _filhoService.buscarFilhoPorId(
        usuarioId: user.uid,
        filhoId: novoFilhoId,
      );

      if (!mounted) return;
      
      // ✅ RETORNA O FILHO CRIADO PARA O FLUXO CONTINUAR
      Navigator.pop(context, filhoCriado);
    } catch (e) {
      debugPrint('Erro ao salvar filho: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ====
  // 🧱 UI
  // ====
  @override
  Widget build(BuildContext context) {
    final avatar = _imagemSelecionada != null
        ? CircleAvatar(
            radius: 50,
            backgroundImage: FileImage(_imagemSelecionada!),
          )
        : (_fotoUrl != null && _fotoUrl!.isNotEmpty)
            ? CircleAvatar(
                radius: 50,
                backgroundImage: NetworkImage(_fotoUrl!),
              )
            : const CircleAvatar(
                radius: 50,
                backgroundColor: Colors.pink,
                child: Icon(Icons.person, size: 50, color: Colors.white),
              );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.pink,
        title: Text(
          widget.filhoExistente == null ? 'Cadastrar Filho' : 'Editar Filho',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const SizedBox(height: 16),
              
              // 📷 FOTO
              Center(
                child: GestureDetector(
                  onTap: _selecionarImagem,
                  child: Stack(
                    children: [
                      avatar,
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Toque para adicionar foto',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              
              const SizedBox(height: 24),

              // 📝 NOME
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome completo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Digite o nome' : null,
              ),

              const SizedBox(height: 16),

              // 📅 DATA DE NASCIMENTO
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey[400]!),
                ),
                leading: const Icon(Icons.calendar_today, color: Colors.pink),
                title: const Text('Data de Nascimento'),
                subtitle: Text(
                  DateFormat('dd/MM/yyyy').format(_dataNascimento),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _dataNascimento,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() => _dataNascimento = date);
                  }
                },
              ),

              const SizedBox(height: 16),

              // 👤 GÊNERO
              DropdownButtonFormField<String>(
                value: _genero,
                items: const [
                  DropdownMenuItem(value: 'Masculino', child: Text('Masculino')),
                  DropdownMenuItem(value: 'Feminino', child: Text('Feminino')),
                ],
                onChanged: (v) => setState(() => _genero = v!),
                decoration: const InputDecoration(
                  labelText: 'Gênero',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wc),
                ),
              ),

              const SizedBox(height: 32),

              // 💾 BOTÃO SALVAR
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _salvando ? null : _salvarFilho,
                  child: _salvando
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Salvar',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}