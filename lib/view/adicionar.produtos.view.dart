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

  // no _SeuState:
  final Map<String, TextEditingController> _qtdCtrlPorTam = {};

  void _sincronizarQtdTotalComCores(String tam) {
    final mapCores = tamanhosCoresSelecionados[tam] ?? <String, int>{};
    final total = mapCores.values.fold<int>(0, (a, v) => a + (v < 0 ? 0 : v));
    // garante controller e atualiza texto
    final ctrl = _qtdCtrlPorTam.putIfAbsent(tam, () => TextEditingController());
    // evita loop de setState desnecessário
    if (ctrl.text != total.toString()) {
      ctrl.text = total.toString();
    }
  }

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
                    child: _gradeTamanhoCorCompacta(context),
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
              onPressed: () => Navigator.of(context).pop(),
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

  Widget _gradeTamanhoCorCompacta(BuildContext context) {
    // garante as chaves
    for (final t in tamanhosDisponiveis) {
      tamanhosCoresSelecionados.putIfAbsent(t, () => <String, int>{});
    }

    int somaCores(Map<String, int> m) =>
        m.values.fold<int>(0, (acc, v) => acc + (v < 0 ? 0 : v));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tamanhos, Quantidade e Cores',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color.fromARGB(255, 194, 131, 178),
          ),
        ),
        const SizedBox(height: 8),

        // Cabeçalho
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: const [
              SizedBox(
                width: 64,
                child: Text(
                  'Tam.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 120, // +10px
                child: Text(
                  'Quantidade total',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 160, // botão mais largo
                child: Text(
                  '       Cores',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Text(
                  'Resumo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        ...tamanhosDisponiveis.map((tam) {
          final mapCores = tamanhosCoresSelecionados[tam]!;
          final total = somaCores(mapCores);

          // garante controller e sincroniza texto inicial
          final qtdCtrl = _qtdCtrlPorTam.putIfAbsent(
            tam,
            () => TextEditingController(text: total.toString()),
          );
          _sincronizarQtdTotalComCores(tam);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Tamanho
                  SizedBox(
                    width: 64,
                    child: Text(
                      tam,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),

                  // Quantidade total (editável ou somente leitura)
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      controller: qtdCtrl, // <-- agora usa controller
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '0',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (v) {
                        final novo = int.tryParse(v) ?? 0;
                        setState(() {
                          if (mapCores.isEmpty) {
                            mapCores['SEM COR'] = novo;
                          } else {
                            final somaAtual = somaCores(mapCores);
                            if (somaAtual <= 0) {
                              final primeira = mapCores.keys.first;
                              mapCores[primeira] = novo;
                            } else {
                              final fator = novo / somaAtual;
                              final chaves = mapCores.keys.toList();
                              int acumulado = 0;
                              for (var i = 0; i < chaves.length; i++) {
                                final k = chaves[i];
                                int novaQtd = (mapCores[k]! * fator).round();
                                if (i == chaves.length - 1) {
                                  novaQtd =
                                      novo -
                                      acumulado; // corrige arredondamento
                                }
                                mapCores[k] = novaQtd < 0 ? 0 : novaQtd;
                                acumulado += mapCores[k]!;
                              }
                            }
                          }
                          // garante que o campo permanece sincronizado
                          _sincronizarQtdTotalComCores(tam);
                        });
                      },
                    ),
                  ),

                  // Botão "Cores" (MAIOR)
                  SizedBox(
                    width: 160, // mais largo
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(160, 44), // altura maior
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        // você pode ajustar o background se quiser:
                        // backgroundColor: const Color(0xFFec407a),
                      ),
                      icon: const Icon(Icons.palette_outlined, size: 20),
                      label: const Text(
                        'Selecionar cor',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () async {
                        final atualizado = await _abrirSeletorCores(
                          context: context,
                          titulo: 'Cores para $tam',
                          coresDisponiveis: coresDisponiveis,
                          mapaAtual: Map<String, int>.from(mapCores),
                        );
                        if (atualizado != null) {
                          setState(() {
                            atualizado.removeWhere((_, qtd) => (qtd <= 0));
                            tamanhosCoresSelecionados[tam] = atualizado;

                            // >>> ATUALIZA O TOTAL DO TAMANHO ASSIM QUE SELECIONAR AS CORES
                            _sincronizarQtdTotalComCores(tam);
                          });
                        }
                      },
                    ),
                  ),

                  // Resumo: bolinhas + contagem
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: mapCores.entries.where((e) => e.value > 0).map((
                        e,
                      ) {
                        final corNome = e.key;
                        final qtd = e.value;
                        final cor =
                            coresDisponiveis[corNome] ??
                            const Color(0xFFEEEEEE);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: cor,
                                  border: Border.all(color: Colors.black26),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              Text(
                                '$corNome ($qtd)',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),

        const SizedBox(height: 4),

        // Rodapé opcional: aplicar a todas / limpar zeros
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Aplicar cores do 1º tamanho para todos'),
              onPressed: tamanhosDisponiveis.isEmpty
                  ? null
                  : () {
                      setState(() {
                        final t0 = tamanhosDisponiveis.first;
                        final base = Map<String, int>.from(
                          tamanhosCoresSelecionados[t0]!,
                        );
                        for (final t in tamanhosDisponiveis.skip(1)) {
                          tamanhosCoresSelecionados[t] = Map<String, int>.from(
                            base,
                          );
                          _sincronizarQtdTotalComCores(
                            t,
                          ); // mantém total em sincronia
                        }
                      });
                    },
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Remover cores com 0'),
              onPressed: () {
                setState(() {
                  for (final t in tamanhosDisponiveis) {
                    tamanhosCoresSelecionados[t]!.removeWhere(
                      (_, qtd) => qtd <= 0,
                    );
                    _sincronizarQtdTotalComCores(t);
                  }
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<Map<String, int>?> _abrirSeletorCores({
    required BuildContext context,
    required String titulo,
    required Map<String, Color> coresDisponiveis,
    required Map<String, int> mapaAtual,
  }) async {
    return showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // estado local para +/-
        final ValueNotifier<Map<String, int>> selecao =
            ValueNotifier<Map<String, int>>(Map<String, int>.from(mapaAtual));

        void inc(String cor) {
          final m = Map<String, int>.from(selecao.value);
          m[cor] = (m[cor] ?? 0) + 1;
          selecao.value = m;
        }

        void dec(String cor) {
          final m = Map<String, int>.from(selecao.value);
          final atual = (m[cor] ?? 0) - 1;
          m[cor] = atual < 0 ? 0 : atual;
          selecao.value = m;
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Flexible(
                child: ValueListenableBuilder<Map<String, int>>(
                  valueListenable: selecao,
                  builder: (_, mapa, __) {
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: coresDisponiveis.entries.map((e) {
                          final corNome = e.key;
                          final color = e.value;
                          final qtd = mapa[corNome] ?? 0;

                          return Container(
                            width: 170,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: color,
                                        border: Border.all(
                                          color: Colors.black26,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        corNome,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: () => dec(corNome),
                                    ),
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        '$qtd',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                      onPressed: () => inc(corNome),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        final resultado = Map<String, int>.from(selecao.value);
                        // normaliza zeros
                        resultado.removeWhere((_, qtd) => qtd <= 0);
                        Navigator.of(ctx).pop(resultado);
                      },
                      label: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
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
