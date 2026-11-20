import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'package:uuid/uuid.dart';

class AdicionarProdutosView extends StatefulWidget {
  final String lojaSelecionada;
  final DocumentSnapshot? produto;
  const AdicionarProdutosView({
    super.key,
    this.produto,
    required this.lojaSelecionada,
  });

  @override
  State<AdicionarProdutosView> createState() => _AdicionarProdutoPageState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _numero = NumberFormat.decimalPattern('pt_BR');

class _AdicionarProdutoPageState extends State<AdicionarProdutosView> {
  final _db = FirebaseFirestore.instance;
  final _formulario = GlobalKey<FormState>();
  final _rolagem = ScrollController();
  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  final _custo = TextEditingController();
  final _precoVenda = TextEditingController();
  final _quantidade = TextEditingController();
  final _picker = ImagePicker();
  final _grade = <String, Map<String, int>>{};
  final _proporcoes = <String, Map<String, int>>{};
  final _totaisPorTamanho = <String, TextEditingController>{};

  String _tipoUsuario = '';
  String _nomeUsuario = '';
  String? _categoria;
  String _corOriginal = '';
  String _codigo = '';
  String _fotoAtual = '';
  Uint8List? _fotoSelecionada;
  String? _nomeNovaFoto;
  String? _tipoNovaFoto;
  bool _removerFoto = false;
  String? _urlFotoEnviada;
  Map<String, dynamic> _original = const {};
  late bool _usavaQuantidadeSimples;
  bool _estoqueAlterado = false;
  bool _selecionandoFoto = false;
  bool _salvando = false;
  bool _enviandoFoto = false;
  bool _saindo = false;
  DocumentReference<Map<String, dynamic>>? _novoDocumento;

  String get _loja => widget.lojaSelecionada.trim();
  bool get _editando => widget.produto != null;
  bool get _semGrade => categoriasSemTamanho.contains(_categoria);
  bool get _ocupado => _salvando || _selecionandoFoto || _saindo;
  bool get _temFoto =>
      _fotoSelecionada != null || (!_removerFoto && _fotoAtual.isNotEmpty);

  bool get _podeAbrirCamera =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static const coresDisponiveis = {
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
    'CASTANHA': Color.fromARGB(255, 83, 46, 16),
    'BEGE': Color(0xFFF5F5DC),
    'ESTAMPA': Color(0xFFD8BFD8),
    'CORES VARIADAS': Color.fromARGB(255, 102, 201, 132),
  };

  static const categorias = [
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

  static const categoriasSemTamanho = [
    'ACESSÓRIOS',
    'CHEIRO PARA AMBIENTE',
    'BOLSAS',
    'OUTROS',
  ];

  static const tamanhosDisponiveis = [
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

  @override
  void initState() {
    super.initState();
    final dados = widget.produto?.data();
    if (dados is Map<String, dynamic>) {
      _original = dados;
      _nome.text = _campo(dados['nome']).toUpperCase();
      _descricao.text = _campo(dados['descricao']);
      _categoria = _campo(dados['categoria']);
      if (_categoria!.isEmpty) _categoria = null;
      _corOriginal = _campo(dados['cor']);
      _codigo = _campo(dados['codigoBarras']);
      _fotoAtual = _campo(dados['foto']);
      if (dados['quantidade'] != null) {
        _quantidade.text = _lerQuantidade(dados['quantidade']).toString();
      }
      _custo.text = _precoParaCampo(dados['valorReal']);
      _precoVenda.text = _precoParaCampo(dados['precoVenda']);

      final coresPorTamanho = dados['tamanhosCores'];
      if (coresPorTamanho is Map) {
        for (final item in coresPorTamanho.entries) {
          final cores = _lerQuantidades(item.value);
          if (cores.isNotEmpty) _grade[item.key.toString()] = cores;
        }
      }
      // Os cadastros antigos podem ter somente quantidades por tamanho.
      if (_grade.isEmpty) {
        final corBase = _corOriginal.isEmpty
            ? 'CORES VARIADAS'
            : _corOriginal.toUpperCase();
        for (final item in _lerQuantidades(dados['tamanhos']).entries) {
          _grade[item.key] = {corBase: item.value};
        }
      }
    }
    _usavaQuantidadeSimples = _semGrade;
    _proporcoes.addAll(_grade);
    for (final tamanho in _tamanhos) {
      _totaisPorTamanho[tamanho] = TextEditingController(
        text: _somar(_grade[tamanho]).toString(),
      );
    }
    _carregarPerfil();
  }

  @override
  void dispose() {
    _rolagem.dispose();
    for (final controller in <TextEditingController>[
      _nome,
      _descricao,
      _custo,
      _precoVenda,
      _quantidade,
      ..._totaisPorTamanho.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarPerfil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final perfil = (await _db.collection('usuarios').doc(uid).get()).data();
      if (!mounted) return;
      setState(() {
        _tipoUsuario = _campo(perfil?['tipo'], 'funcionario');
        _nomeUsuario = _campo(perfil?['nome'], 'Usuário');
      });
    } catch (erro) {
      debugPrint('Cadastro • perfil: $erro');
      if (mounted) _mensagem('Não foi possível carregar o perfil do usuário.');
    }
  }

  List<String> get _tamanhos =>
      {...tamanhosDisponiveis, ..._grade.keys}.toList();

  void _mensagem(String aviso) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
  }

  Future<void> _selecionarFoto(ImageSource origem) async {
    if (_ocupado) return;
    final pelaCamera = origem == ImageSource.camera;
    if (pelaCamera && !_podeAbrirCamera) {
      _mensagem('No computador, use a Galeria para adicionar uma foto.');
      return;
    }

    setState(() => _selecionandoFoto = true);
    try {
      final arquivo = await _picker.pickImage(
        source: origem,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (arquivo == null || !mounted) return;
      final bytes = await arquivo.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        _mensagem('A foto selecionada está vazia.');
        return;
      }

      try {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 64,
          allowUpscaling: false,
        );
        try {
          final quadro = await codec.getNextFrame();
          quadro.image.dispose();
        } finally {
          codec.dispose();
        }
      } catch (erro) {
        debugPrint('Cadastro • formato da foto: $erro');
        if (mounted) _mensagem('Não foi possível ler a imagem. Tente outra foto.');
        return;
      }
      if (!mounted) return;

      final extensao = RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false)
          .firstMatch(arquivo.name)
          ?.group(0)
          ?.toLowerCase();
      final nome = '${const Uuid().v4()}${extensao ?? '.jpg'}';
      setState(() {
        _fotoSelecionada = bytes;
        _nomeNovaFoto = nome;
        _tipoNovaFoto = arquivo.mimeType;
        _urlFotoEnviada = null;
        _removerFoto = false;
      });
    } catch (erro) {
      debugPrint('Cadastro • seleção de foto: $erro');
      if (!mounted) return;
      _mensagem(
        pelaCamera
            ? 'Não foi possível abrir a câmera. Confira a permissão do dispositivo ou use a Galeria.'
            : 'Não foi possível abrir a Galeria. Confira a permissão e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _selecionandoFoto = false);
    }
  }

  void _alterarRemocaoFoto({required bool remover}) {
    setState(() {
      _fotoSelecionada = null;
      _nomeNovaFoto = null;
      _tipoNovaFoto = null;
      _urlFotoEnviada = null;
      _removerFoto = remover && _fotoAtual.isNotEmpty;
    });
  }

  Future<String> _enviarFoto(String id, String nome, Uint8List bytes) async {
    final urlEnviada = _urlFotoEnviada;
    if (urlEnviada != null) return urlEnviada;

    final referencia =
        FirebaseStorage.instance.ref().child('produtos/$id-$nome');
    final tipo = _tipoNovaFoto;
    final metadados = tipo == null ? null : SettableMetadata(contentType: tipo);
    final tarefa = referencia.putData(bytes, metadados);
    await tarefa.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        unawaited(_cancelarEnvioFoto(tarefa));
        throw TimeoutException('O envio da foto excedeu o tempo limite.');
      },
    );
    final url = await referencia.getDownloadURL().timeout(
      const Duration(seconds: 15),
    );
    _urlFotoEnviada = url;
    return url;
  }

  Future<void> _cancelarEnvioFoto(UploadTask tarefa) async {
    try {
      await tarefa.cancel();
    } catch (erro) {
      debugPrint('Cadastro • cancelamento do envio da foto: $erro');
    }
  }

  String _mensagemErroFoto(Object erro) {
    if (erro is TimeoutException) {
      return 'O envio da foto demorou demais. Verifique a conexão e tente salvar novamente.';
    }
    if (erro is FirebaseException) {
      switch (erro.code) {
        case 'unauthenticated':
          return 'A sessão expirou ao enviar a foto.';
        case 'unauthorized':
          return 'Sua conta não tem permissão para enviar a foto no Firebase Storage.';
        case 'bucket-not-found':
        case 'no-default-bucket':
        case 'quota-exceeded':
          return 'O Firebase Storage está indisponível para enviar a foto (${erro.code}).';
        default:
          return 'Não foi possível enviar a foto (${erro.code}). Tente salvar novamente.';
      }
    }
    return 'Não foi possível enviar a foto. Confira o arquivo e tente salvar novamente.';
  }

  Future<String> _gerarCodigo() async {
    const caracteres = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final aleatorio = Random.secure();
    while (true) {
      final sufixo = List.generate(
        6,
        (_) => caracteres[aleatorio.nextInt(caracteres.length)],
      ).join();
      final codigo = 'PROD$sufixo';
      final encontrados = await _db
          .collection('produtos')
          .where('codigoBarras', isEqualTo: codigo)
          .limit(1)
          .get();
      if (encontrados.docs.isEmpty) return codigo;
    }
  }

  Future<void> _salvar() async {
    if (_ocupado) return;
    if (_loja.isEmpty) {
      _mensagem('Selecione uma loja antes de salvar o produto.');
      return;
    }
    final lojaOriginal = _campo(_original['loja']);
    if (_editando && lojaOriginal.isNotEmpty && lojaOriginal != _loja) {
      _mensagem('Abra o produto pela loja em que ele foi cadastrado.');
      return;
    }
    if (!(_formulario.currentState?.validate() ?? false)) {
      if (_rolagem.hasClients) {
        _rolagem.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _salvando = true);
    final nome = _nome.text.trim().toUpperCase();
    final preco = _lerMoedaDoCampo(_precoVenda.text);
    final loja = _loja;
    final categoria = _categoria!;
    final semGrade = _semGrade;
    final alterarEstoque =
        !_editando || _estoqueAlterado || semGrade != _usavaQuantidadeSimples;
    final grade = _gradePositiva(_grade);
    final tamanhos = {
      for (final item in grade.entries) item.key: _somar(item.value),
    };
    final quantidade = semGrade
        ? _lerQuantidade(_quantidade.text)
        : _somar(tamanhos);
    final dados = <String, dynamic>{
      'nome': nome,
      'descricao': _descricao.text.trim().toUpperCase(),
      'cor': _corOriginal,
      'loja': loja,
      if (_tipoUsuario.isNotEmpty && _tipoUsuario != 'funcionario')
        'valorReal': _lerMoedaDoCampo(_custo.text),
      'precoVenda': preco,
      'categoria': categoria,
      if (_original['dataCadastro'] == null)
        'dataCadastro': FieldValue.serverTimestamp(),
      if (_original['horaCadastro'] == null)
        'horaCadastro': FieldValue.serverTimestamp(),
      if (alterarEstoque) 'quantidade': quantidade,
      if (alterarEstoque && !semGrade) ...{
        'tamanhos': tamanhos,
        'tamanhosCores': grade,
      },
      if (_editando && alterarEstoque && semGrade) ...{
        'tamanhos': FieldValue.delete(),
        'tamanhosCores': FieldValue.delete(),
      },
    };

    try {
      final produtos = _db.collection('produtos');
      final referencia = _editando
          ? produtos.doc(widget.produto!.id)
          : (_novoDocumento ??= produtos.doc());
      if (_codigo.isEmpty) _codigo = await _gerarCodigo();
      dados['codigoBarras'] = _codigo;
      dados['busca'] = [nome.toLowerCase(), _codigo.toLowerCase()];
      final bytes = _fotoSelecionada;
      final nomeFoto = _nomeNovaFoto;
      if (bytes != null && nomeFoto != null) {
        if (mounted) setState(() => _enviandoFoto = true);
        dados['foto'] = await _enviarFoto(referencia.id, nomeFoto, bytes);
        if (mounted) setState(() => _enviandoFoto = false);
      } else if (_removerFoto || !_editando) {
        dados['foto'] = '';
      }

      if (_editando) {
        await referencia.update(dados);
      } else {
        await referencia.set(dados);
      }
    } catch (erro) {
      final etapa = _enviandoFoto ? 'envio da foto' : 'gravação do produto';
      debugPrint('Cadastro • $etapa: $erro');
      if (mounted) {
        final aviso = _enviandoFoto
            ? _mensagemErroFoto(erro)
            : 'Não foi possível salvar o produto. Confira a conexão e tente novamente.';
        setState(() {
          _salvando = false;
          _enviandoFoto = false;
        });
        _mensagem(aviso);
      }
      return;
    }

    if (!mounted) return;
    // Usa os dados já gravados, sem uma nova leitura só para imprimir.
    final etiqueta = _DadosEtiqueta(
      nome: nome,
      codigo: _codigo,
      preco: preco,
      grade: semGrade ? const {} : grade,
      tamanhos: semGrade ? const {} : tamanhos,
    );
    await _confirmarSalvamento(etiqueta);
    if (!mounted) return;
    setState(() => _salvando = false);
    _voltarAoCatalogo(loja);
  }

  Future<void> _confirmarSalvamento(_DadosEtiqueta etiqueta) async {
    final imprimir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogo) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, color: _marca),
        title: const Text('Produto salvo'),
        content: Text(etiqueta.nome),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Imprimir etiqueta'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _marca),
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Ver produtos'),
          ),
        ],
      ),
    );
    if (imprimir != true || !mounted) return;

    try {
      Barcode.code128().verify(etiqueta.codigo);
      final pedido = await showDialog<_PedidoEtiqueta>(
        context: context,
        builder: (_) => _DialogoEtiqueta(produto: etiqueta),
      );
      if (!mounted || pedido == null) return;
      final enviado = await _imprimirEtiquetaDupla(etiqueta, pedido);
      if (mounted) {
        _mensagem(
          enviado
              ? 'Etiqueta enviada à impressora.'
              : 'A impressão não foi concluída.',
        );
      }
    } catch (erro) {
      debugPrint('Cadastro • etiqueta: $erro');
      if (mounted)
        _mensagem('O produto foi salvo. Não foi possível imprimir a etiqueta.');
    }
  }

  void _voltarAoCatalogo(String loja) {
    final navegador = Navigator.of(context);
    if (_editando && navegador.canPop()) {
      navegador.pop();
      return;
    }
    navegador.pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => ProdutosView(lojaSelecionada: loja),
      ),
    );
  }

  void _cancelar() {
    final navegador = Navigator.of(context);
    if (navegador.canPop()) {
      navegador.pop();
    } else {
      _voltarAoCatalogo(_loja);
    }
  }

  Future<void> _sair() async {
    if (_ocupado) return;
    setState(() => _saindo = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    } catch (erro) {
      debugPrint('Cadastro • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      _mensagem('Não foi possível sair. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loja = _loja;
    return PopScope(
      canPop: !_ocupado,
      child: Scaffold(
        backgroundColor: _fundo,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _marca,
          elevation: 0,
          toolbarHeight: 76,
          titleSpacing: 4,
          leading: Builder(
            builder: (contexto) => IconButton(
              tooltip: 'Abrir menu',
              icon: const Icon(Icons.menu),
              onPressed: _ocupado
                  ? null
                  : () => Scaffold.of(contexto).openDrawer(),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editando ? 'Editar produto' : 'Adicionar produto',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _texto,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 16,
                    color: _marca,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Tooltip(
                      message: loja.isEmpty
                          ? 'Loja ativa'
                          : 'Loja ativa: $loja',
                      child: Text(
                        loja.isEmpty ? 'Nenhuma loja selecionada' : loja,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _marca,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: _ocupado ? null : _sair,
            ),
            const SizedBox(width: 4),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: _borda),
          ),
        ),
        drawer: _menu(loja),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _ocupado,
            child: LayoutBuilder(
              builder: (context, limites) {
                final margem = limites.maxWidth >= 720 ? 32.0 : 16.0;
                return SingleChildScrollView(
                  controller: _rolagem,
                  padding: EdgeInsets.fromLTRB(margem, 20, margem, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Form(
                        key: _formulario,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _dadosEFoto(),
                            const SizedBox(height: 14),
                            _estoque(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        bottomNavigationBar: _rodape(),
      ),
    );
  }

  Widget _dadosEFoto() {
    return LayoutBuilder(
      builder: (context, limites) {
        final dados = _painel('Dados do produto', _camposProduto());
        final foto = _painel('Foto do produto', _campoFoto());
        if (limites.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: dados),
              const SizedBox(width: 14),
              Expanded(child: foto),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [dados, const SizedBox(height: 14), foto],
        );
      },
    );
  }

  Widget _camposProduto() {
    final opcoes = {...categorias, if (_categoria != null) _categoria!};
    final venda = _campoMoeda(_precoVenda, 'Preço de venda');
    final podeVerCusto =
        _tipoUsuario.isNotEmpty && _tipoUsuario != 'funcionario';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _nome,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          decoration: _decoracao('Nome do produto'),
          inputFormatters: const [_NomeEmMaiusculas()],
          validator: (valor) => (valor?.trim().isEmpty ?? true)
              ? 'Informe o nome do produto.'
              : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _categoria,
          isExpanded: true,
          decoration: _decoracao('Categoria'),
          items: [
            for (final categoria in opcoes)
              DropdownMenuItem(
                value: categoria,
                child: Text(categoria, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (categoria) => setState(() => _categoria = categoria),
          validator: (valor) => valor == null ? 'Selecione a categoria.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descricao,
          textCapitalization: TextCapitalization.characters,
          minLines: 2,
          maxLines: 3,
          decoration: _decoracao('Descrição'),
        ),
        const SizedBox(height: 12),
        if (podeVerCusto)
          LayoutBuilder(
            builder: (context, limites) {
              final custo = _campoMoeda(_custo, 'Valor real (custo)');
              if (limites.maxWidth >= 440) {
                return Row(
                  children: [
                    Expanded(child: custo),
                    const SizedBox(width: 12),
                    Expanded(child: venda),
                  ],
                );
              }
              return Column(
                children: [custo, const SizedBox(height: 12), venda],
              );
            },
          )
        else
          venda,
        if (_editando && _codigo.isNotEmpty) ...[
          const SizedBox(height: 12),
          SelectableText(
            'Código de barras: $_codigo',
            style: const TextStyle(color: _suave, fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _campoMoeda(TextEditingController controller, String rotulo) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: _decoracao(rotulo),
      inputFormatters: [
        MoneyInputFormatter(
          leadingSymbol: 'R\$',
          mantissaLength: 2,
          thousandSeparator: ThousandSeparator.Period,
        ),
      ],
    );
  }

  Widget _campoFoto() {
    final arquivo = _fotoSelecionada;
    final Widget imagem;
    if (arquivo != null) {
      imagem = Image.memory(
        arquivo,
        fit: BoxFit.contain,
        errorBuilder: (context, erro, pilha) => _estadoFoto(
          Icons.broken_image_outlined,
          'A foto selecionada é inválida.',
        ),
      );
    } else if (!_removerFoto && _fotoAtual.isNotEmpty) {
      imagem = Image.network(
        _fotoAtual,
        fit: BoxFit.contain,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (context, erro, pilha) => _estadoFoto(
          Icons.broken_image_outlined,
          'Não foi possível carregar a foto salva.',
        ),
      );
    } else {
      imagem = _estadoFoto(
        Icons.image_outlined,
        _removerFoto
            ? 'A foto será removida ao salvar o produto.'
            : 'Nenhuma foto cadastrada',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(height: 176, child: imagem),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: _marca),
              onPressed: _ocupado
                  ? null
                  : () => _selecionarFoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Galeria'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: _marca),
              onPressed: _ocupado
                  ? null
                  : () => _selecionarFoto(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_temFoto ? 'Refazer foto' : 'Câmera'),
            ),
            if (_temFoto)
              TextButton.icon(
                onPressed: _ocupado
                    ? null
                    : () => _alterarRemocaoFoto(remover: true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir foto'),
              ),
            if (_fotoAtual.isNotEmpty && (arquivo != null || _removerFoto))
              TextButton(
                onPressed: _ocupado
                    ? null
                    : () => _alterarRemocaoFoto(remover: false),
                child: const Text('Restaurar foto anterior'),
              ),
          ],
        ),
        if (_selecionandoFoto) const LinearProgressIndicator(color: _marca),
      ],
    );
  }

  Widget _estadoFoto(IconData icone, String mensagem) {
    return ColoredBox(
      color: _rosaClaro,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, color: _marca, size: 32),
              const SizedBox(height: 8),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _suave),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estoque() {
    if (_categoria == null) {
      return _painel(
        'Estoque',
        const Text(
          'Selecione uma categoria para configurar o estoque.',
          style: TextStyle(color: _suave),
        ),
      );
    }
    if (_semGrade) {
      return _painel(
        'Estoque',
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: TextFormField(
              controller: _quantidade,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _estoqueAlterado = true,
              decoration: _decoracao('Quantidade'),
            ),
          ),
        ),
      );
    }

    final tamanhos = _tamanhos;
    final total = _grade.values.fold<int>(
      0,
      (soma, cores) => soma + _somar(cores),
    );
    return _painel(
      'Grade de tamanhos e cores',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              _selo('Total em estoque: ${_numero.format(total)}'),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _marca),
                onPressed: _somar(_grade[tamanhos.first]) == 0
                    ? null
                    : () => _copiarGrade(tamanhos.first),
                icon: const Icon(Icons.copy_all_outlined),
                label: Text('Copiar grade de ${tamanhos.first} para os demais'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final tamanho in tamanhos) _linhaDaGrade(tamanho),
        ],
      ),
    );
  }

  Widget _linhaDaGrade(String tamanho) {
    final cores = _grade[tamanho] ?? const <String, int>{};
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _fundo,
          border: Border.all(color: _borda),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: LayoutBuilder(
            builder: (context, limites) {
              final campo = TextFormField(
                controller: _totaisPorTamanho[tamanho],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _decoracao('Qtd. total', densa: true),
                onChanged: (valor) =>
                    _alterarTotal(tamanho, _lerQuantidade(valor)),
              );
              final botao = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: _marca),
                onPressed: () => _editarCores(tamanho),
                icon: const Icon(Icons.palette_outlined, size: 18),
                label: const Text('Cores'),
              );
              final controle = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      tamanho,
                      style: const TextStyle(
                        color: _texto,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 84, child: campo),
                  botao,
                ],
              );
              final resumo = Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in cores.entries)
                    if (item.value > 0)
                      _selo(
                        '${item.key} · ${_numero.format(item.value)}',
                        cor:
                            coresDisponiveis[item.key] ??
                            const Color(0xFFE6DCE2),
                      ),
                ],
              );
              if (limites.maxWidth >= 560) {
                return Row(
                  children: [
                    SizedBox(width: 258, child: controle),
                    const SizedBox(width: 12),
                    Expanded(child: resumo),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  controle,
                  if (cores.isNotEmpty) ...[const SizedBox(height: 8), resumo],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _alterarTotal(String tamanho, int novoTotal) {
    setState(() {
      _estoqueAlterado = true;
      final base = _proporcoes[tamanho] ?? const <String, int>{};
      _grade[tamanho] = _redistribuir(base, novoTotal);
    });
  }

  void _atualizarGrade(String tamanho, Map<String, int> cores) {
    _grade[tamanho] = cores;
    _proporcoes[tamanho] = cores;
    _totaisPorTamanho[tamanho]!.text = _somar(cores).toString();
    _estoqueAlterado = true;
  }

  Future<void> _editarCores(String tamanho) async {
    final atual = _grade[tamanho] ?? const <String, int>{};
    final cores = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => _DialogoCores(
        tamanho: tamanho,
        cores: {
          ...coresDisponiveis,
          for (final cor in atual.keys)
            if (!coresDisponiveis.containsKey(cor))
              cor: const Color(0xFFE6DCE2),
        },
        atual: atual,
      ),
    );
    if (mounted && cores != null) {
      setState(() => _atualizarGrade(tamanho, cores));
    }
  }

  Future<void> _copiarGrade(String origem) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text('Copiar grade de $origem?'),
        content: const Text(
          'As cores e quantidades dos demais tamanhos serão substituídas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _marca),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Copiar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmou != true) return;
    final base = _grade[origem]!;
    setState(() {
      for (final tamanho in _tamanhos) {
        if (tamanho != origem) _atualizarGrade(tamanho, Map.of(base));
      }
    });
  }

  Widget _rodape() {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_salvando)
              const LinearProgressIndicator(color: _marca)
            else
              const Divider(height: 1, color: _borda),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Align(
                  alignment: Alignment.centerRight,
                  heightFactor: 1,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      OutlinedButton(
                        onPressed: _ocupado ? null : _cancelar,
                        child: const Text('Cancelar'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _marca),
                        onPressed: _ocupado || _loja.isEmpty ? null : _salvar,
                        icon: const Icon(Icons.save_outlined, size: 19),
                        label: Text(
                          _enviandoFoto
                              ? 'Enviando foto…'
                              : _salvando
                              ? 'Salvando…'
                              : 'Salvar produto',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(String loja) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined, color: _marca),
              title: Text(_nomeUsuario.isEmpty ? 'Senhorita' : _nomeUsuario),
              subtitle: loja.isEmpty ? null : Text(loja),
            ),
            const Divider(color: _borda),
            if (_tipoUsuario == 'admin')
              _linkMenu(
                Icons.dashboard_outlined,
                'Início',
                () => HomeView(lojaSelecionada: loja),
              ),
            _linkMenu(
              Icons.point_of_sale,
              'Nova venda',
              () => VendasView(lojaSelecionada: loja),
            ),
            _linkMenu(
              Icons.checkroom,
              'Produtos',
              () => ProdutosView(lojaSelecionada: loja),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: Text(_editando ? 'Editar produto' : 'Adicionar produto'),
              selected: true,
              selectedColor: _marca,
              selectedTileColor: _rosaClaro,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
            _linkMenu(
              Icons.people_outline,
              'Clientes',
              () => ClientesView(lojaSelecionada: loja),
            ),
            if (_tipoUsuario == 'funcionario')
              _linkMenu(
                Icons.receipt_long_outlined,
                'Vendas realizadas',
                () => VendasRealizadasView(lojaSelecionada: loja),
              ),
            if (_tipoUsuario == 'admin') ...[
              _linkMenu(
                Icons.bar_chart,
                'Relatórios',
                () => RelatoriosView(lojaSelecionada: loja),
              ),
              _linkMenu(
                Icons.settings_outlined,
                'Configurações',
                () => ConfiguracoesView(lojaSelecionada: loja),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linkMenu(IconData icone, String rotulo, Widget Function() pagina) {
    return ListTile(
      leading: Icon(icone, color: _suave),
      title: Text(rotulo),
      onTap: () {
        if (_ocupado) return;
        final navegador = Navigator.of(context);
        navegador.pop();
        if (_loja.isEmpty) {
          _mensagem('Selecione uma loja primeiro.');
          return;
        }
        if (_editando && rotulo == 'Produtos' && navegador.canPop()) {
          navegador.pop();
          return;
        }
        navegador.pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => pagina()),
        );
      },
    );
  }
}

class _NomeEmMaiusculas extends TextInputFormatter {
  const _NomeEmMaiusculas();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue antigo,
    TextEditingValue novo,
  ) {
    if (novo.composing.isValid && !novo.composing.isCollapsed) return novo;
    final original = novo.text;
    final maiusculo = original.toUpperCase();
    if (original == maiusculo) return novo;

    final selecao = novo.selection;
    int deslocamento(int posicao) {
      return original
          .substring(0, posicao.clamp(0, original.length).toInt())
          .toUpperCase()
          .length;
    }

    return novo.copyWith(
      text: maiusculo,
      selection: selecao.isValid
          ? selecao.copyWith(
              baseOffset: deslocamento(selecao.baseOffset),
              extentOffset: deslocamento(selecao.extentOffset),
            )
          : selecao,
      composing: TextRange.empty,
    );
  }
}

InputDecoration _decoracao(String rotulo, {bool densa = false}) {
  return InputDecoration(
    labelText: rotulo,
    filled: true,
    fillColor: Colors.white,
    isDense: densa,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _borda),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _borda),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _marca, width: 1.5),
    ),
  );
}

Widget _painel(String titulo, Widget conteudo) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _borda),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: _texto,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          conteudo,
        ],
      ),
    ),
  );
}

Widget _selo(String texto, {Color? cor}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: _rosaClaro,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cor != null) ...[_amostraDeCor(cor), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              texto,
              style: const TextStyle(
                color: _marca,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _amostraDeCor(Color cor) {
  return Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: cor,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black26),
    ),
  );
}

String _campo(Object? valor, [String padrao = '']) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}

String _precoParaCampo(Object? valor) {
  final texto = _campo(valor).replaceAll('R\$', '').trim();
  final preco = valor is num
      ? valor
      : num.tryParse(
          texto.contains(',')
              ? texto.replaceAll('.', '').replaceAll(',', '.')
              : texto,
        );
  return preco == null || !preco.isFinite ? '' : _moeda.format(preco);
}

String _preco(num? valor) => valor == null ? '—' : _moeda.format(valor);

double _lerMoedaDoCampo(String texto) {
  return (double.tryParse(texto.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) / 100;
}

int _lerQuantidade(Object? valor) {
  final quantidade = valor is num ? valor : num.tryParse(_campo(valor));
  return quantidade == null || !quantidade.isFinite
      ? 0
      : max(0, quantidade.toInt());
}

Map<String, int> _lerQuantidades(Object? dados) {
  if (dados is! Map) return {};
  final resultado = <String, int>{};
  for (final item in dados.entries) {
    final quantidade = _lerQuantidade(item.value);
    if (quantidade > 0) resultado[item.key.toString()] = quantidade;
  }
  return resultado;
}

int _somar(Map<String, int>? quantidades) {
  return quantidades?.values.fold<int>(0, (total, atual) => total + atual) ?? 0;
}

Map<String, Map<String, int>> _gradePositiva(
  Map<String, Map<String, int>> grade,
) {
  final resultado = <String, Map<String, int>>{};
  for (final tamanho in grade.entries) {
    final positivas = _lerQuantidades(tamanho.value);
    if (positivas.isNotEmpty) resultado[tamanho.key] = positivas;
  }
  return resultado;
}

Map<String, int> _redistribuir(Map<String, int> cores, int novoTotal) {
  final totalAtual = _somar(cores);
  if (totalAtual == 0) {
    final cor = cores.isEmpty ? 'SEM COR' : cores.keys.first;
    return {cor: novoTotal};
  }

  // Arredonda a soma acumulada para distribuir exatamente o total digitado.
  var originalAcumulado = 0;
  var novoAcumulado = 0;
  final resultado = <String, int>{};
  for (final cor in cores.entries) {
    originalAcumulado += cor.value;
    final ateAgora = (originalAcumulado * novoTotal) ~/ totalAtual;
    resultado[cor.key] = ateAgora - novoAcumulado;
    novoAcumulado = ateAgora;
  }
  return resultado;
}

class _DialogoCores extends StatefulWidget {
  const _DialogoCores({
    required this.tamanho,
    required this.cores,
    required this.atual,
  });

  final String tamanho;
  final Map<String, Color> cores;
  final Map<String, int> atual;

  @override
  State<_DialogoCores> createState() => _DialogoCoresState();
}

class _DialogoCoresState extends State<_DialogoCores> {
  final _busca = TextEditingController();
  final _campos = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    // Destaca primeiro as cores que já têm unidades neste tamanho.
    final nomes = {
      ...widget.atual.keys.where((nome) => (widget.atual[nome] ?? 0) > 0),
      ...widget.cores.keys,
    };
    for (final nome in nomes) {
      _campos[nome] = TextEditingController(text: '${widget.atual[nome] ?? 0}');
    }
  }

  @override
  void dispose() {
    _busca.dispose();
    for (final campo in _campos.values) {
      campo.dispose();
    }
    super.dispose();
  }

  Map<String, int> _selecionadas() => _lerQuantidades({
    for (final item in _campos.entries) item.key: item.value.text,
  });

  void _ajustarQuantidade(TextEditingController campo, int delta) {
    final quantidade = max(0, _lerQuantidade(campo.text) + delta);
    final texto = quantidade.toString();
    setState(() {
      campo.value = TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final termo = _busca.text.trim().toLowerCase();
    final visiveis = _campos.keys
        .where((nome) => nome.toLowerCase().contains(termo))
        .toList();
    final selecionadas = _selecionadas();
    final rodape = _rodape(selecionadas);

    // Dialog recebe limites da janela, sem medir o tamanho intrínseco da lista.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 540,
        height: 580,
        child: LayoutBuilder(
          builder: (context, limites) {
            final compacto = limites.maxHeight < 220;
            return Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _cabecalho()),
                      if (visiveis.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Nenhuma cor encontrada.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _suave),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              indice,
                            ) {
                              final nome = visiveis[indice];
                              return _linhaDeCor(
                                nome,
                                selecionada: selecionadas.containsKey(nome),
                              );
                            }, childCount: visiveis.length),
                          ),
                        ),
                      if (compacto) SliverToBoxAdapter(child: rodape),
                    ],
                  ),
                ),
                if (!compacto) rodape,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cores para ${widget.tamanho}',
                  style: const TextStyle(
                    color: _texto,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fechar sem aplicar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _busca,
            onChanged: (_) => setState(() {}),
            decoration: _decoracao('Buscar cor').copyWith(
              prefixIcon: const Icon(Icons.search, color: _marca),
              suffixIcon: _busca.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_busca.clear),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaDeCor(String nome, {required bool selecionada}) {
    final campo = _campos[nome]!;
    final cor = widget.cores[nome] ?? const Color(0xFFE6DCE2);
    return Container(
      key: ValueKey(nome),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selecionada ? _rosaClaro : _fundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borda),
      ),
      child: Row(
        children: [
          _amostraDeCor(cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nome,
              style: TextStyle(
                color: _texto,
                fontWeight: selecionada ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Diminuir: $nome',
            onPressed: selecionada ? () => _ajustarQuantidade(campo, -1) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
          SizedBox(
            width: 60,
            child: TextField(
              controller: campo,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: _decoracao('Qtd.', densa: true).copyWith(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Aumentar: $nome',
            onPressed: () => _ajustarQuantidade(campo, 1),
            icon: const Icon(Icons.add_circle_outline, color: _marca, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _rodape(Map<String, int> selecionadas) {
    final total = _numero.format(_somar(selecionadas));
    final qtdCores = selecionadas.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borda)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Total: $total · ${qtdCores == 1 ? '1 cor' : '$qtdCores cores'}',
              style: const TextStyle(
                color: _marca,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _marca),
                  onPressed: () => Navigator.of(context).pop(selecionadas),
                  child: const Text('Aplicar cores'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DadosEtiqueta {
  const _DadosEtiqueta({
    required this.nome,
    required this.codigo,
    required this.preco,
    required this.tamanhos,
    required this.grade,
  });

  final String nome;
  final String codigo;
  final double preco;
  final Map<String, int> tamanhos;
  final Map<String, Map<String, int>> grade;
}

class _PedidoEtiqueta {
  const _PedidoEtiqueta(this.impressora, this.tamanho, this.cor);

  final Printer impressora;
  final String? tamanho;
  final String? cor;
}

class _DialogoEtiqueta extends StatefulWidget {
  const _DialogoEtiqueta({required this.produto});

  final _DadosEtiqueta produto;

  @override
  State<_DialogoEtiqueta> createState() => _DialogoEtiquetaState();
}

class _DialogoEtiquetaState extends State<_DialogoEtiqueta> {
  late Future<List<Printer>> _impressoras;
  Printer? _impressora;
  String? _tamanho;
  String? _cor;

  @override
  void initState() {
    super.initState();
    _impressoras = _listarImpressoras();
  }

  Future<List<Printer>> _listarImpressoras() async {
    final impressoras = await Printing.listPrinters();
    if (impressoras.isNotEmpty) {
      _impressora = impressoras.firstWhere(
        (item) => item.name == 'ELGIN L42PRO ETIQUETA',
        orElse: () => impressoras.first,
      );
    }
    return impressoras;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Printer>>(
      future: _impressoras,
      builder: (context, snapshot) {
        final impressoras = snapshot.data ?? const <Printer>[];
        final pronto =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError &&
            impressoras.isNotEmpty;
        final grade = widget.produto.grade;
        final tamanhos = grade.isNotEmpty
            ? grade.keys
            : widget.produto.tamanhos.keys;
        final cores = grade[_tamanho]?.keys ?? const <String>[];
        final podeImprimir =
            pronto &&
            _impressora != null &&
            (tamanhos.isEmpty || _tamanho != null) &&
            (grade.isEmpty || _cor != null);

        return AlertDialog(
          title: const Text('Imprimir etiqueta'),
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: !pronto
                ? _estadoImpressoras(snapshot)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.produto.nome,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(_preco(widget.produto.preco)),
                      const SizedBox(height: 12),
                      if (tamanhos.isNotEmpty) ...[
                        _seletor<String>(
                          'Tamanho',
                          _tamanho,
                          tamanhos,
                          (valor) => setState(() {
                            _tamanho = valor;
                            _cor = null;
                          }),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (grade.isNotEmpty) ...[
                        _seletor<String>(
                          'Cor',
                          _cor,
                          cores,
                          cores.isEmpty
                              ? null
                              : (valor) => setState(() => _cor = valor),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _seletor<Printer>(
                        'Impressora',
                        _impressora,
                        impressoras,
                        (valor) => setState(() => _impressora = valor),
                        legenda: (item) => item.name,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 60,
                        child: BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: widget.produto.codigo,
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _marca),
              onPressed: !podeImprimir
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(_PedidoEtiqueta(_impressora!, _tamanho, _cor)),
              child: const Text('Imprimir'),
            ),
          ],
        );
      },
    );
  }

  Widget _estadoImpressoras(AsyncSnapshot<List<Printer>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(color: _marca)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          snapshot.hasError
              ? 'Não foi possível consultar as impressoras.'
              : 'Nenhuma impressora encontrada.',
        ),
        TextButton(
          onPressed: () => setState(() {
            _impressora = null;
            _impressoras = _listarImpressoras();
          }),
          child: const Text('Tentar novamente'),
        ),
      ],
    );
  }

  Widget _seletor<T>(
    String rotulo,
    T? selecionado,
    Iterable<T> valores,
    ValueChanged<T?>? aoAlterar, {
    String Function(T)? legenda,
  }) {
    return InputDecorator(
      isEmpty: selecionado == null,
      decoration: InputDecoration(
        labelText: rotulo,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: selecionado,
          isDense: true,
          isExpanded: true,
          hint: const Text('Selecionar'),
          items: [
            for (final valor in valores)
              DropdownMenuItem<T>(
                value: valor,
                child: Text(
                  legenda?.call(valor) ?? valor.toString(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: aoAlterar,
        ),
      ),
    );
  }
}

Future<bool> _imprimirEtiquetaDupla(
  _DadosEtiqueta produto,
  _PedidoEtiqueta pedido,
) async {
  final documento = pw.Document();
  const largura = 36 * PdfPageFormat.mm;
  const altura = 25 * PdfPageFormat.mm;
  final nome = produto.nome.length > 20
      ? '${produto.nome.substring(0, 20)}…'
      : produto.nome;
  final variante = [
    if (pedido.tamanho != null) 'Tam: ${pedido.tamanho}',
    if (pedido.cor != null) pedido.cor!,
  ].join(' / ');

  pw.Widget etiqueta() {
    return pw.Container(
      width: largura,
      height: altura,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            nome,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            maxLines: 1,
            textAlign: pw.TextAlign.center,
          ),
          if (variante.isNotEmpty)
            pw.Text(
              variante,
              style: const pw.TextStyle(fontSize: 6),
              maxLines: 1,
              textAlign: pw.TextAlign.center,
            ),
          pw.Text(
            'R\$ ${produto.preco.toStringAsFixed(2)}',
            style: const pw.TextStyle(fontSize: 6),
          ),
          pw.BarcodeWidget(
            barcode: Barcode.code128(),
            data: produto.codigo,
            width: 100,
            height: 30,
            drawText: false,
          ),
          pw.Text(produto.codigo, style: const pw.TextStyle(fontSize: 6)),
        ],
      ),
    );
  }

  documento.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(90 * PdfPageFormat.mm, altura),
      margin: const pw.EdgeInsets.symmetric(horizontal: 4 * PdfPageFormat.mm),
      build: (_) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [etiqueta(), pw.SizedBox(width: 10), etiqueta()],
      ),
    ),
  );

  return await Printing.directPrintPdf(
    printer: pedido.impressora,
    onLayout: (_) => documento.save(),
  );
}
