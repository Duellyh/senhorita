import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class ProdutosView extends StatefulWidget {
  const ProdutosView({super.key, required this.lojaSelecionada});

  final String lojaSelecionada;

  @override
  State<ProdutosView> createState() => _ProdutosViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);
const _aviso = Color(0xFF8C500F);
const _avisoClaro = Color(0xFFFFF1DE);
const _erro = Color(0xFF9E2940);

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _numero = NumberFormat.decimalPattern('pt_BR');

class _ProdutosViewState extends State<ProdutosView> {
  final _db = FirebaseFirestore.instance;
  final _buscaController = TextEditingController();
  final _excluindo = <String>{};
  final _imprimindo = <String>{};
  late Stream<_Catalogo> _catalogo;

  String _busca = '';
  String _tipoUsuario = '';
  String _nomeUsuario = '';
  bool _saindo = false;
  Timer? _debounce;

  String get _loja => widget.lojaSelecionada.trim();

  @override
  void initState() {
    super.initState();
    _catalogo = _observarProdutos(_loja);
    _carregarPerfil();
  }

  @override
  void didUpdateWidget(covariant ProdutosView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lojaSelecionada.trim() != _loja) {
      _catalogo = _observarProdutos(_loja);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaController.dispose();
    super.dispose();
  }

  Stream<_Catalogo> _observarProdutos(String loja) {
    if (loja.isEmpty) return const Stream.empty();

    final indice = <String, _Produto>{};
    return _db
        .collection('produtos')
        .where('loja', isEqualTo: loja)
        .orderBy('dataCadastro', descending: true)
        .snapshots()
        .map((snapshot) {
          // Só refaz o índice de busca dos documentos que mudaram.
          for (final alteracao in snapshot.docChanges) {
            indice.remove(alteracao.doc.id);
          }
          return _Catalogo([
            for (final documento in snapshot.docs)
              indice.putIfAbsent(documento.id, () => _Produto(documento)),
          ]);
        });
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
      debugPrint('Produtos • perfil: $erro');
      if (mounted) {
        _mensagem('Não foi possível carregar o perfil do usuário.');
      }
    }
  }

  void _alterarBusca(String valor) {
    _debounce?.cancel();
    final busca = _normalizar(valor);
    if (busca == _busca) return;
    if (busca.isEmpty) {
      setState(() => _busca = '');
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _busca = busca);
    });
  }

  void _limparBusca() {
    _buscaController.clear();
    _alterarBusca('');
  }

  void _recarregar() {
    setState(() => _catalogo = _observarProdutos(_loja));
  }

  void _mensagem(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  void _abrirCadastro([_Produto? produto]) {
    if (_loja.isEmpty) {
      _mensagem('Selecione uma loja primeiro.');
      return;
    }
    FocusScope.of(context).unfocus();
    final loja = _loja;
    final navegador = Navigator.of(context);
    final rota = MaterialPageRoute<void>(
      builder: (_) => AdicionarProdutosView(
        produto: produto?.documento,
        lojaSelecionada: loja,
      ),
    );
    if (produto == null) {
      navegador.pushReplacement<void, void>(rota);
    } else {
      navegador.push<void>(rota);
    }
  }

  Future<void> _sair() async {
    if (_saindo) return;

    setState(() => _saindo = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    } catch (erro) {
      debugPrint('Produtos • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      _mensagem('Não foi possível sair. Tente novamente.');
    }
  }

  Future<void> _excluirProduto(_Produto produto) async {
    if (_excluindo.contains(produto.id)) return;
    final loja = _loja;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Excluir produto?'),
        content: Text('Deseja excluir o produto “${produto.nome}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _erro),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (!mounted || confirmou != true || _loja != loja) return;
    setState(() => _excluindo.add(produto.id));
    try {
      await produto.documento.reference.delete();
      if (mounted) _mensagem('Produto excluído.');
    } catch (erro) {
      debugPrint('Produtos • exclusão: $erro');
      if (mounted) _mensagem('Não foi possível excluir o produto.');
    } finally {
      if (mounted) setState(() => _excluindo.remove(produto.id));
    }
  }

  Future<void> _mostrarEtiqueta(_Produto produto) async {
    if (_imprimindo.contains(produto.id)) return;
    final codigo = produto.codigo;
    if (codigo.isEmpty) {
      _mensagem('Este produto ainda não tem código de barras.');
      return;
    }

    try {
      Barcode.code128().verify(codigo);
    } catch (erro) {
      debugPrint('Produtos • código de barras: $erro');
      _mensagem('O código de barras deste produto é inválido.');
      return;
    }

    setState(() => _imprimindo.add(produto.id));
    try {
      final pedido = await showDialog<_PedidoEtiqueta>(
        context: context,
        builder: (_) => _DialogoEtiqueta(produto: produto),
      );
      if (!mounted || pedido == null) return;

      final enviado = await _imprimirEtiquetaDupla(produto, pedido);
      if (mounted) {
        _mensagem(
          enviado
              ? 'Etiqueta enviada à impressora.'
              : 'A impressora não concluiu o envio.',
        );
      }
    } catch (erro) {
      debugPrint('Produtos • impressão: $erro');
      if (mounted) _mensagem('Não foi possível imprimir a etiqueta.');
    } finally {
      if (mounted) setState(() => _imprimindo.remove(produto.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loja = _loja;
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _marca,
        elevation: 0,
        toolbarHeight: 76,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Produtos',
              style: TextStyle(
                color: _texto,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 16, color: _marca),
                const SizedBox(width: 6),
                Flexible(
                  child: Tooltip(
                    message: loja.isEmpty ? 'Loja ativa' : 'Loja ativa: $loja',
                    child: Text(
                      loja.isEmpty ? 'Nenhuma loja selecionada' : loja,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _marca,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
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
            tooltip: 'Atualizar catálogo',
            onPressed: loja.isEmpty ? null : _recarregar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _saindo ? null : _sair,
            icon: const Icon(Icons.logout),
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
        child: loja.isEmpty
            ? const Center(
                child: Text('Selecione uma loja para ver os produtos.'),
              )
            : LayoutBuilder(
                builder: (context, limites) {
                  final margem = limites.maxWidth >= 720 ? 32.0 : 16.0;
                  final largura = (limites.maxWidth - margem * 2)
                      .clamp(0.0, 1280.0)
                      .toDouble();
                  return Center(
                    child: SizedBox(
                      width: largura,
                      child: StreamBuilder<_Catalogo>(
                        key: ValueKey(loja),
                        stream: _catalogo,
                        builder: (context, snapshot) {
                          return _lista(snapshot, largura);
                        },
                      ),
                    ),
                  );
                },
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
              title: Text(
                _nomeUsuario.isEmpty ? 'Senhorita' : _nomeUsuario,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: loja.isEmpty ? null : Text(loja),
            ),
            const Divider(color: _borda),
            if (_tipoUsuario == 'admin')
              _linkMenu(Icons.dashboard_outlined, 'Início', () {
                return HomeView(lojaSelecionada: loja);
              }),
            _linkMenu(Icons.point_of_sale, 'Nova venda', () {
              return VendasView(lojaSelecionada: loja);
            }),
            ListTile(
              leading: const Icon(Icons.checkroom),
              title: const Text('Produtos'),
              selected: true,
              selectedColor: _marca,
              selectedTileColor: _rosaClaro,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
            _linkMenu(Icons.add_box_outlined, 'Adicionar produto', () {
              return AdicionarProdutosView(lojaSelecionada: loja);
            }),
            _linkMenu(Icons.people_outline, 'Clientes', () {
              return ClientesView(lojaSelecionada: loja);
            }),
            if (_tipoUsuario == 'funcionario')
              _linkMenu(Icons.receipt_long_outlined, 'Vendas realizadas', () {
                return VendasRealizadasView(lojaSelecionada: loja);
              }),
            if (_tipoUsuario == 'admin') ...[
              _linkMenu(Icons.bar_chart, 'Relatórios', () {
                return RelatoriosView(lojaSelecionada: loja);
              }),
              _linkMenu(Icons.settings_outlined, 'Configurações', () {
                return ConfiguracoesView(lojaSelecionada: loja);
              }),
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
        final navegador = Navigator.of(context);
        navegador.pop();
        if (_loja.isEmpty) {
          _mensagem('Selecione uma loja primeiro.');
          return;
        }
        navegador.pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => pagina()),
        );
      },
    );
  }

  Widget _lista(AsyncSnapshot<_Catalogo> snapshot, double largura) {
    final catalogo = snapshot.data;
    final produtos = catalogo?.filtrar(_busca) ?? const <_Produto>[];
    final colunas = largura >= 1100 ? 3 : (largura >= 700 ? 2 : 1);

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: _painelBusca(largura, catalogo, produtos.length),
        ),
        if (snapshot.hasError)
          SliverToBoxAdapter(
            child: _estado(
              'Não foi possível carregar os produtos.',
              acao: TextButton(
                onPressed: _recarregar,
                child: const Text('Tentar novamente'),
              ),
            ),
          )
        else if (catalogo == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: _marca)),
            ),
          )
        else if (produtos.isEmpty)
          SliverToBoxAdapter(
            child: _estado(
              _busca.isEmpty
                  ? 'Nenhum produto cadastrado nesta loja.'
                  : 'Nenhum produto encontrado para essa busca.',
              acao: _busca.isEmpty
                  ? null
                  : TextButton(
                      onPressed: _limparBusca,
                      child: const Text('Limpar busca'),
                    ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, linha) => _linhaDeProdutos(produtos, linha, colunas),
                childCount: (produtos.length + colunas - 1) ~/ colunas,
              ),
            ),
          ),
      ],
    );
  }

  Widget _painelBusca(double largura, _Catalogo? catalogo, int resultados) {
    final campoBusca = TextField(
      controller: _buscaController,
      onChanged: _alterarBusca,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: 'Buscar produtos',
        hintText: 'Nome, código, categoria, tamanho ou cor',
        prefixIcon: const Icon(Icons.search, color: _marca),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _buscaController,
          builder: (context, valor, _) => valor.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Limpar busca',
                  onPressed: _limparBusca,
                  icon: const Icon(Icons.clear),
                ),
        ),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _borda),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _marca, width: 1.5),
        ),
      ),
    );
    final adicionar = FilledButton.icon(
      onPressed: () => _abrirCadastro(),
      style: FilledButton.styleFrom(
        backgroundColor: _marca,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Adicionar produto'),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (largura >= 600)
            Row(
              children: [
                Expanded(child: campoBusca),
                const SizedBox(width: 12),
                adicionar,
              ],
            )
          else ...[
            campoBusca,
            const SizedBox(height: 10),
            adicionar,
          ],
          if (catalogo != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tag(
                  '${_numero.format(catalogo.produtos.length)} cadastrados',
                  icone: Icons.checkroom,
                ),
                _tag(
                  '${_numero.format(catalogo.estoqueBaixo)} com estoque baixo',
                  aviso: catalogo.estoqueBaixo > 0,
                  icone: Icons.inventory_2_outlined,
                ),
                if (_busca.isNotEmpty)
                  _tag('${_numero.format(resultados)} na busca'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _estado(String texto, {Widget? acao}) {
    return _superficie(
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(texto, textAlign: TextAlign.center),
            if (acao != null) acao,
          ],
        ),
      ),
    );
  }

  Widget _linhaDeProdutos(List<_Produto> produtos, int linha, int colunas) {
    final inicio = linha * colunas;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var coluna = 0; coluna < colunas; coluna++) ...[
            if (coluna > 0) const SizedBox(width: 12),
            Expanded(
              child: inicio + coluna < produtos.length
                  ? _cartao(produtos[inicio + coluna])
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cartao(_Produto produto) {
    return _superficie(
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _foto(produto.foto),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        produto.nome,
                        style: const TextStyle(
                          color: _texto,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        produto.categoria,
                        style: const TextStyle(color: _suave),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Código: ${produto.codigo.isEmpty ? produto.id : produto.codigo}',
                        style: const TextStyle(color: _suave, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tag('Venda ${_preco(produto.preco)}'),
                if (_tipoUsuario == 'admin')
                  _tag('Custo ${_preco(produto.custo)}'),
                _tag(
                  '${produto.estoqueBaixo ? 'Estoque baixo' : 'Estoque'} · '
                  '${_numero.format(produto.quantidade)}',
                  aviso: produto.estoqueBaixo,
                  icone: produto.estoqueBaixo ? Icons.warning_amber : null,
                ),
              ],
            ),
            if (produto.grade.isNotEmpty || produto.tamanhos.isNotEmpty) ...[
              const SizedBox(height: 4),
              ExpansionTile(
                key: PageStorageKey('grade-${produto.id}'),
                title: const Text('Tamanhos e estoque'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 10),
                expandedAlignment: Alignment.centerLeft,
                children: [_variantes(produto)],
              ),
            ],
            const Divider(color: _borda, height: 22),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 2,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: _marca),
                  onPressed: () => _abrirCadastro(produto),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: _marca),
                  onPressed: _imprimindo.contains(produto.id)
                      ? null
                      : () => _mostrarEtiqueta(produto),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Etiqueta'),
                ),
                IconButton(
                  tooltip: 'Excluir produto',
                  onPressed: _excluindo.contains(produto.id)
                      ? null
                      : () => _excluirProduto(produto),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: _erro,
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _variantes(_Produto produto) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (produto.grade.isNotEmpty)
          for (final tamanho in produto.grade.entries)
            for (final cor in tamanho.value.entries)
              _tag(
                '${tamanho.key} · ${cor.key}: ${cor.value}',
                aviso: cor.value <= 2,
              )
        else
          for (final tamanho in produto.tamanhos.entries)
            _tag('${tamanho.key}: ${tamanho.value}', aviso: tamanho.value <= 2),
      ],
    );
  }

  Widget _foto(String endereco) {
    const placeholder = ColoredBox(
      color: _rosaClaro,
      child: Center(child: Icon(Icons.checkroom, color: _marca)),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 64,
        child: endereco.isEmpty
            ? placeholder
            : Image.network(
                endereco,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                cacheWidth: kIsWeb
                    ? null
                    : (64 * MediaQuery.of(context).devicePixelRatio).ceil(),
                errorBuilder: (context, erro, pilha) => const Tooltip(
                  message: 'Não foi possível carregar a foto salva',
                  child: ColoredBox(
                    color: _rosaClaro,
                    child: Center(
                      child: Icon(Icons.broken_image_outlined, color: _marca),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

Widget _superficie(Widget filho) {
  return Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _borda),
    ),
    clipBehavior: Clip.antiAlias,
    child: filho,
  );
}

Widget _tag(String texto, {bool aviso = false, IconData? icone}) {
  final cor = aviso ? _aviso : _marca;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: aviso ? _avisoClaro : _rosaClaro,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, color: cor, size: 14),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              texto,
              style: TextStyle(
                color: cor,
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

class _Catalogo {
  _Catalogo(this.produtos)
    : estoqueBaixo = produtos.where((produto) => produto.estoqueBaixo).length;

  final List<_Produto> produtos;
  final int estoqueBaixo;
  String? _ultimaBusca;
  List<_Produto> _resultado = const [];

  List<_Produto> filtrar(String busca) {
    if (busca.isEmpty) return produtos;
    if (_ultimaBusca == busca) return _resultado;

    final termos = busca.split(' ');
    _resultado = produtos
        .where((produto) => termos.every(produto.textoBusca.contains))
        .toList();
    _ultimaBusca = busca;
    return _resultado;
  }
}

class _Produto {
  factory _Produto(QueryDocumentSnapshot<Map<String, dynamic>> documento) {
    final dados = documento.data();
    final tamanhos = _quantidades(dados['tamanhos']);
    final grade = <String, Map<String, int>>{};
    final dadosGrade = dados['tamanhosCores'];
    if (dadosGrade is Map) {
      for (final tamanho in dadosGrade.entries) {
        final cores = _quantidades(tamanho.value);
        if (cores.isNotEmpty) grade[tamanho.key.toString()] = cores;
      }
    }

    final nome = _campo(dados['nome'], 'Produto sem nome');
    final categoria = _campo(dados['categoria'], 'Sem categoria');
    final codigo = _campo(dados['codigoBarras']);
    final quantidade = _valor(dados['quantidade'])?.toInt() ?? 0;
    final estoqueBaixo = grade.isNotEmpty
        ? grade.values.any((cores) => cores.values.any((qtd) => qtd <= 2))
        : tamanhos.isNotEmpty
        ? tamanhos.values.any((qtd) => qtd <= 0)
        : quantidade <= 1;

    return _Produto._(
      documento: documento,
      nome: nome,
      categoria: categoria,
      codigo: codigo,
      foto: _campo(dados['foto']),
      preco: _valor(dados['precoVenda']),
      custo: _valor(dados['valorReal']),
      quantidade: quantidade,
      tamanhos: tamanhos,
      grade: grade,
      estoqueBaixo: estoqueBaixo,
      textoBusca: _normalizar(
        [
          nome,
          codigo,
          documento.id,
          categoria,
          dados['descricao'],
          dados['cor'],
          dados['loja'],
          ...tamanhos.keys,
          for (final tamanho in grade.entries) ...[
            tamanho.key,
            ...tamanho.value.keys,
          ],
        ].whereType<Object>().join(' '),
      ),
    );
  }

  const _Produto._({
    required this.documento,
    required this.nome,
    required this.categoria,
    required this.codigo,
    required this.foto,
    required this.preco,
    required this.custo,
    required this.quantidade,
    required this.tamanhos,
    required this.grade,
    required this.estoqueBaixo,
    required this.textoBusca,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> documento;
  final String nome;
  final String categoria;
  final String codigo;
  final String foto;
  final num? preco;
  final num? custo;
  final int quantidade;
  final Map<String, int> tamanhos;
  final Map<String, Map<String, int>> grade;
  final bool estoqueBaixo;
  final String textoBusca;

  String get id => documento.id;
}

Map<String, int> _quantidades(Object? dados) {
  if (dados is! Map) return const {};
  return {
    for (final entrada in dados.entries)
      entrada.key.toString(): _valor(entrada.value)?.toInt() ?? 0,
  };
}

String _campo(Object? valor, [String padrao = '']) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}

num? _valor(Object? valor) {
  if (valor is num) return valor.isFinite ? valor : null;
  final texto = _campo(valor).replaceAll('R\$', '').trim();
  final numero = num.tryParse(
    texto.contains(',')
        ? texto.replaceAll('.', '').replaceAll(',', '.')
        : texto,
  );
  return numero != null && numero.isFinite ? numero : null;
}

String _preco(num? valor) => valor == null ? '—' : _moeda.format(valor);

final _espacos = RegExp(r'\s+');

String _normalizar(String texto) {
  const acentos = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const letras = 'aaaaaeeeeiiiiooooouuuucn';
  var resultado = texto.toLowerCase().trim();
  for (var i = 0; i < acentos.length; i++) {
    resultado = resultado.replaceAll(acentos[i], letras[i]);
  }
  return resultado.replaceAll(_espacos, ' ');
}

class _PedidoEtiqueta {
  const _PedidoEtiqueta(this.impressora, this.tamanho, this.cor);

  final Printer impressora;
  final String? tamanho;
  final String? cor;
}

class _DialogoEtiqueta extends StatefulWidget {
  const _DialogoEtiqueta({required this.produto});

  final _Produto produto;

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
  _Produto produto,
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
            'R\$ ${produto.preco?.toStringAsFixed(2) ?? '-'}',
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
