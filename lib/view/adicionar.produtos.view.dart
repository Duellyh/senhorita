import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'dart:math';

class AdicionarProdutosView extends StatefulWidget {
  final DocumentSnapshot? produto;
  const AdicionarProdutosView({super.key, this.produto});

  @override
  State<AdicionarProdutosView> createState() => _AdicionarProdutoPageState();
}

class _AdicionarProdutoPageState extends State<AdicionarProdutosView> {
  final _formKey = GlobalKey<FormState>();
  final nomeController = TextEditingController();
  final descricaoController = TextEditingController();
  final valorRealController = TextEditingController();
  final precoVendaController = TextEditingController();
  final quantidadeController = TextEditingController();
  final codigoBarrasController = TextEditingController();
  File? imagemSelecionada;
  String? urlImagem;
  String? corSelecionada;
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';
  String? lojaSelecionada;
  List<String> lojas = [
    'Senhorita Modeladores (Matriz)',
    'Senhorita Jalecos (Filial)',
  ]; // Coloque aqui os nomes das lojas disponíveis

  Future<void> buscarTipoUsuario() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user!.uid)
          .get();
      setState(() {
        tipoUsuario = doc['tipo'] ?? 'funcionario';
        nomeUsuario = doc['nome'] ?? 'Usuário';
      });
    }
  }

  final coresDisponiveis = {
    'PRETO': Colors.black,
    'BRANCO': Colors.white,
    'VERMELHO': Colors.red,
    'AZUL': Colors.blue,
    'VERDE': Colors.green,
    'AMARELO': Colors.yellow,
    'ROSA': Colors.pink,
    'ROXO': Colors.purple,
    'CINZA': Colors.grey,
    'LARANJA': Colors.orange,
    'MARROM': Colors.brown,
    'CASTANHA': const Color.fromARGB(255, 83, 46, 16),
    'BEGE': const Color(0xFFF5F5DC),
    'ESTAMPA': const Color(0xFFD8BFD8),
    'CORES VARIADAS': const Color.fromARGB(255, 102, 201, 132),
  };

  final categorias = [
    'CINTA',
    'MODELADORES',
    'PÓS-CIRÚRGICO',
    'BOLSAS',
    'CHEIRO PARA AMBIENTE',
    'CINTAS MODELADORES',
    'MODA ÍNTIMAS',
    'MODA PRAIA',
    'ACESSÓRIOS',
    'JALECOS',
    'SUTIÃ MODELADORES',
    'OUTROS',
  ];

  final categoriasSemTamanho = [
    'ACESSÓRIOS',
    'CHEIRO PARA AMBIENTE',
    'BOLSAS',
    'OUTROS',
  ];

  String? categoriaSelecionada;
  final tamanhosDisponiveis = [
    'EPP',
    'PP',
    'P',
    'M',
    'G',
    'GG',
    'XG',
    '50',
    '52',
    '54',
  ];

  // Grade Tamanho × Cor (inicialização preguiçosa)
  Map<String, Map<String, int>> tamanhosCoresSelecionados = {};

  // Helpers para grade
  int _calcularTotalGrade(Map<String, Map<String, int>> grade) {
    var total = 0;
    for (final cores in grade.values) {
      for (final q in cores.values) {
        total += (q);
      }
    }
    return total;
  }

  Map<String, Map<String, int>> _compactarGrade(
    Map<String, Map<String, int>> grade,
  ) {
    final saida = <String, Map<String, int>>{};
    grade.forEach((tam, cores) {
      final filtradas = <String, int>{};
      cores.forEach((cor, q) {
        if ((q) > 0) filtradas[cor] = q;
      });
      if (filtradas.isNotEmpty) saida[tam] = filtradas;
    });
    return saida;
  }

  @override
  void initState() {
    super.initState();
    buscarTipoUsuario();
    if (widget.produto != null) {
      final data = widget.produto!.data() as Map<String, dynamic>;
      nomeController.text = data['nome'] ?? '';
      descricaoController.text = data['descricao'] ?? '';
      corSelecionada = data['cor'];
      valorRealController.text = (data['valorReal'] != null)
          ? 'R\$ ${(data['valorReal'] as num).toStringAsFixed(2).replaceAll('.', ',')}'
          : '';

      precoVendaController.text = (data['precoVenda'] != null)
          ? 'R\$ ${(data['precoVenda'] as num).toStringAsFixed(2).replaceAll('.', ',')}'
          : '';
      quantidadeController.text = data['quantidade']?.toString() ?? '';
      urlImagem = data['foto'];
      categoriaSelecionada = data['categoria'];
      codigoBarrasController.text = data['codigoBarras'] ?? '';

      // 1) Tenta ler o novo formato: tamanhosCores
      final Map<String, dynamic>? tcDbRaw =
          data['tamanhosCores'] as Map<String, dynamic>?;
      if (tcDbRaw != null) {
        // Converte p/ Map<String, Map<String,int>>
        tcDbRaw.forEach((tam, coresRaw) {
          final coresMap = <String, int>{};
          if (coresRaw is Map) {
            coresRaw.forEach((cor, q) {
              final qtd = (q is num)
                  ? q.toInt()
                  : int.tryParse(q.toString()) ?? 0;
              if (qtd > 0) coresMap[cor.toString()] = qtd;
            });
          }
          if (coresMap.isNotEmpty) {
            tamanhosCoresSelecionados[tam.toString()] = coresMap;
          }
        });
      } else {
        // 2) Retrocompat: se existir apenas 'tamanhos', migra p/ uma cor base
        final Map<String, dynamic>? tamanhosAntigos =
            data['tamanhos'] as Map<String, dynamic>?;
        if (tamanhosAntigos != null) {
          final corBase =
              (data['cor'] as String?)?.toUpperCase() ?? 'CORES VARIADAS';
          tamanhosAntigos.forEach((tam, q) {
            final qtd = (q is num)
                ? q.toInt()
                : int.tryParse(q.toString()) ?? 0;
            if (qtd > 0) {
              final m = (tamanhosCoresSelecionados[tam] ??= <String, int>{});
              m[corBase] = qtd;
            }
          });
        }
      }
    }
  }

  Future<void> selecionarImagem({required ImageSource source}) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() => imagemSelecionada = File(pickedFile.path));
    }
  }

  double _converterParaDouble(String valor) {
    final somenteNumeros = valor.replaceAll(RegExp(r'[^0-9]'), '');
    final convertido = double.tryParse(somenteNumeros);
    if (convertido == null) return 0.0;
    return convertido / 100;
  }

  Future<String?> uploadImagem(String id) async {
    if (imagemSelecionada == null) return urlImagem;
    try {
      final ref = FirebaseStorage.instance.ref().child('produtos/$id.jpg');
      await ref.putFile(imagemSelecionada!);
      return await ref.getDownloadURL();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao enviar imagem: $e')));
      return null;
    }
  }

  /// Gera um código aleatório com prefixo, exemplo: 'PROD9K2X3A'
  String gerarCodigoComPrefixo(String prefixo, {int tamanho = 6}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();

    final sufixo = List.generate(
      tamanho,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();

    return '$prefixo$sufixo'; // Ou só return sufixo;
  }

  /// Verifica se o código já existe no Firestore
  Future<bool> codigoJaExiste(String codigo) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('produtos')
        .where('codigoBarras', isEqualTo: codigo)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  /// Gera um código único que ainda não existe no Firebase
  Future<String> gerarCodigoUnico({String prefixo = 'PROD'}) async {
    String codigo;
    bool existe;

    do {
      codigo = gerarCodigoComPrefixo(prefixo);
      existe = await codigoJaExiste(codigo);
    } while (existe);

    return codigo;
  }

  Future<void> salvarProduto() async {
    if (!_formKey.currentState!.validate()) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final bool novoProduto = widget.produto == null;

    final docRef = novoProduto
        ? FirebaseFirestore.instance.collection('produtos').doc()
        : FirebaseFirestore.instance
              .collection('produtos')
              .doc(widget.produto!.id);

    String codigoCurto;

    if (novoProduto) {
      codigoCurto = await gerarCodigoUnico(prefixo: 'PROD');
    } else {
      final dados = widget.produto!.data() as Map<String, dynamic>;
      codigoCurto =
          (dados['codigoBarras'] as String?) ??
          await gerarCodigoUnico(prefixo: 'PROD');
    }

    try {
      final fotoUrl = await uploadImagem(docRef.id);
      final bool semTamanho =
          categoriaSelecionada != null &&
          categoriasSemTamanho.contains(categoriaSelecionada!);

      final gradeCompacta = _compactarGrade(tamanhosCoresSelecionados);

      final int quantidadeTotal = semTamanho
          ? int.tryParse(quantidadeController.text) ?? 0
          : _calcularTotalGrade(gradeCompacta);

      final nome = nomeController.text.trim().toUpperCase();
      final descricao = descricaoController.text.trim().toUpperCase();
      final categoria = categoriaSelecionada ?? 'Não definido';

      final produtoAtualizado = {
        'nome': nome,
        'descricao': descricao,
        'cor': corSelecionada ?? '',
        'loja': lojaSelecionada,
        'foto': fotoUrl ?? '',
        if (tipoUsuario !=
            'funcionario') // ⬅️ Condicional para não salvar valorReal
          'valorReal': _converterParaDouble(valorRealController.text),
        'precoVenda': _converterParaDouble(
          precoVendaController.text,
        ), // permanece obrigatório
        'categoria': categoria,
        'dataCadastro': FieldValue.serverTimestamp(),
        'horaCadastro': FieldValue.serverTimestamp(),
        if (semTamanho) ...{
          'quantidade': quantidadeTotal,
          // opcional: limpar campos antigos
          'tamanhos': FieldValue.delete(),
          'tamanhosCores': FieldValue.delete(),
        } else ...{
          'quantidade': quantidadeTotal,
          // mantém 'tamanhos' como somatório por tamanho (retrocompat)
          'tamanhos': {
            for (final e in gradeCompacta.entries)
              e.key: e.value.values.fold<int>(0, (a, b) => a + b),
          },
          // NOVO: grade Tamanho × Cor
          'tamanhosCores': gradeCompacta,
        },

        'codigoBarras': codigoCurto,

        'busca': [
          nome.toLowerCase(),
          categoria.toLowerCase(),
          codigoCurto.toLowerCase(),
        ],
      };

      await docRef.set(produtoAtualizado);

      // 🔁 Atualização do estoque com merge: true
      final estoqueRef = FirebaseFirestore.instance
          .collection('estoque')
          .doc(docRef.id);
      final estoqueAtualizado = {
        'idProduto': docRef.id,
        'nome': nome,
        'categoria': categoria,
        'cor': corSelecionada ?? '',
        'foto': fotoUrl ?? '',
        'quantidade': quantidadeTotal,
        if (!semTamanho) ...{
          'tamanhos': {
            for (final e in gradeCompacta.entries)
              e.key: e.value.values.fold<int>(0, (a, b) => a + b),
          },
          'tamanhosCores': gradeCompacta,
          // opcional: chave “achatada” p/ buscas
          'estoqueVariantes': {
            for (final e in gradeCompacta.entries)
              for (final c in e.value.entries) '${e.key}#${c.key}': c.value,
          },
        },
      };

      await estoqueRef.set(estoqueAtualizado, SetOptions(merge: true));

      Navigator.of(context).pop(); // fecha o loader
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Sucesso'),
          content: const Text('O produto foi salvo com sucesso.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // fecha o AlertDialog
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ProdutosView()),
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // fecha o loader
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar produto: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Senhorita Cintas Modeladores',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
            const Center(
              child: Text(
                'ADICIONAR PRODUTO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginView()),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: Container(
          color: primaryColor,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: accentColor),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.store, color: Colors.white, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'Olá, ${nomeUsuario.toUpperCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.dashboard, 'Home', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeView()),
                  );
                }),
              _menuItem(Icons.attach_money, 'Vender', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const VendasView()),
                );
              }),
              _menuItem(Icons.checkroom, 'Produtos', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ProdutosView()),
                );
              }),
              _menuItem(Icons.add_box, 'Adicionar Produto', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdicionarProdutosView(),
                  ),
                );
              }),
              _menuItem(Icons.people, 'Clientes', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ClientesView()),
                );
              }),
              if (tipoUsuario == 'funcionario')
                _menuItem(Icons.bar_chart, 'Vendas Realizadas', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VendasRealizadasView(),
                    ),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.show_chart, 'Relatórios', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const RelatoriosView()),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.settings, 'Configurações', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConfiguracoesView(),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: nomeController,
                        decoration: const InputDecoration(labelText: 'Nome'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Informe o nome'
                            : null,
                        onChanged: (value) {
                          nomeController.value = nomeController.value.copyWith(
                            text: value.toUpperCase(),
                            selection: TextSelection.collapsed(
                              offset: value.length,
                            ),
                          );
                        },
                      ),
                      TextFormField(
                        controller: descricaoController,
                        decoration: const InputDecoration(
                          labelText: 'Descrição',
                        ),
                        maxLines: 2,
                        onChanged: (value) {
                          descricaoController.value = descricaoController.value
                              .copyWith(
                                text: value.toUpperCase(),
                                selection: TextSelection.collapsed(
                                  offset: value.length,
                                ),
                              );
                        },
                      ),
                      DropdownButtonFormField<String>(
                        value: categoriaSelecionada,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                        ),
                        items: categorias
                            .map(
                              (cat) => DropdownMenuItem(
                                value: cat,
                                child: Text(cat),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => categoriaSelecionada = v),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Selecione uma categoria'
                            : null,
                      ),

                      DropdownButtonFormField<String>(
                        value: lojaSelecionada,
                        decoration: const InputDecoration(labelText: 'Loja'),
                        items: lojas
                            .map(
                              (loja) => DropdownMenuItem(
                                value: loja,
                                child: Text(loja),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => lojaSelecionada = v),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Selecione uma loja';
                          }
                          return null;
                        },
                      ),
                      if (tipoUsuario != 'funcionario') ...[
                        TextFormField(
                          controller: valorRealController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Valor Real (custo)',
                          ),
                          inputFormatters: [
                            MoneyInputFormatter(leadingSymbol: 'R\$'),
                          ],
                        ),
                      ],
                      TextFormField(
                        controller: precoVendaController,
                        decoration: const InputDecoration(
                          labelText: 'Preço de Venda',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          MoneyInputFormatter(leadingSymbol: 'R\$'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selecionar foto ou tirar foto:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 194, 131, 178),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  selecionarImagem(source: ImageSource.gallery),
                              icon: const Icon(
                                Icons.image,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Galeria',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color.fromARGB(
                                  255,
                                  194,
                                  131,
                                  178,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  selecionarImagem(source: ImageSource.camera),
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Câmera',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color.fromARGB(
                                  255,
                                  194,
                                  131,
                                  178,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (imagemSelecionada != null)
                        Image.file(
                          imagemSelecionada!,
                          height: 100,
                          fit: BoxFit.cover,
                        )
                      else if (urlImagem != null)
                        Image.network(
                          urlImagem!,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (categoriaSelecionada != null &&
                  categoriasSemTamanho.contains(categoriaSelecionada!))
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextFormField(
                      controller: quantidadeController,
                      decoration: const InputDecoration(
                        labelText: 'Quantidade',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                )
              else
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _gradeTamanhoCor(),
                  ),
                ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () => ProdutosView(),
              icon: const Icon(Icons.cancel),
              label: const Text('Cancelar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: salvarProduto,
              icon: const Icon(Icons.save),
              label: const Text('Salvar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 196, 50, 99),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradeTamanhoCor() {
    // garante que todos os tamanhos existem no mapa
    for (final t in tamanhosDisponiveis) {
      tamanhosCoresSelecionados.putIfAbsent(t, () => <String, int>{});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Selecionar Tamanhos e Cores',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color.fromARGB(255, 194, 131, 178),
          ),
        ),
        const SizedBox(height: 8),

        ...tamanhosDisponiveis.map((tam) {
          final coresMap = tamanhosCoresSelecionados[tam]!;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tamanho: $tam',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: coresDisponiveis.entries.map((entry) {
                      final cor = entry.key;
                      final qtd = coresMap[cor] ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: entry.value,
                                border: Border.all(color: Colors.black26),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Text(cor, style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: () {
                                setState(() {
                                  final atual = coresMap[cor] ?? 0;
                                  if (atual > 0) coresMap[cor] = atual - 1;
                                });
                              },
                            ),
                            Text('$qtd'),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: () {
                                setState(() {
                                  final atual = coresMap[cor] ?? 0;
                                  coresMap[cor] = atual + 1;
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }
}

Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
  return ListTile(
    leading: Icon(icon, color: Colors.white),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    onTap: onTap,
  );
}
