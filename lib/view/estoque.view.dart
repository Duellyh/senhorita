import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class EstoqueView extends StatefulWidget {
  final String lojaSelecionada;

  const EstoqueView({super.key, required this.lojaSelecionada});

  @override
  State<EstoqueView> createState() => _EstoqueViewState();
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
const _erroClaro = Color(0xFFFBE9ED);
const _limiteBaixo = 1;

final _numero = NumberFormat.decimalPattern('pt_BR');

class _EstoqueViewState extends State<EstoqueView> {
  final _db = FirebaseFirestore.instance;
  final _busca = TextEditingController();
  Stream<_ListaEstoque>? _estoque;

  String _termo = '';
  String _tipoUsuario = '';
  String _nomeUsuario = '';
  bool _saindo = false;

  String get _loja => widget.lojaSelecionada.trim();

  @override
  void initState() {
    super.initState();
    _estoque = _observarEstoque(_loja);
    _carregarPerfil();
  }

  @override
  void didUpdateWidget(covariant EstoqueView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lojaSelecionada.trim() != _loja) {
      _estoque = _observarEstoque(_loja);
    }
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Stream<_ListaEstoque>? _observarEstoque(String loja) {
    if (loja.isEmpty) return null;

    final indice = <String, _ProdutoBaixo>{};
    return _db
        .collection('produtos')
        .where('loja', isEqualTo: loja)
        .snapshots()
        .map((snapshot) {
          for (final mudanca in snapshot.docChanges) {
            final id = mudanca.doc.id;
            indice.remove(id);
            final dados = mudanca.doc.data();
            if (mudanca.type == DocumentChangeType.removed || dados == null)
              continue;
            final produto = _ProdutoBaixo(dados, id);
            if (produto.temEstoqueBaixo) indice[id] = produto;
          }
          final produtos = indice.values.toList()
            ..sort((a, b) {
              if (a.esgotado != b.esgotado) return a.esgotado ? -1 : 1;
              return a.nomeBusca.compareTo(b.nomeBusca);
            });
          return _ListaEstoque(produtos);
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
      debugPrint('Estoque • perfil: $erro');
      if (mounted) _avisar('Não foi possível carregar o perfil do usuário.');
    }
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  void _recarregar() {
    if (!_saindo) setState(() => _estoque = _observarEstoque(_loja));
  }

  void _alterarBusca(String valor) {
    final termo = _normalizar(valor);
    if (_termo != termo) setState(() => _termo = termo);
  }

  void _limparBusca() {
    _busca.clear();
    _alterarBusca('');
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
      debugPrint('Estoque • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      _avisar('Não foi possível sair.');
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
              'Estoque baixo',
              style: TextStyle(
                color: _texto,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.storefront_outlined, color: _marca, size: 16),
                const SizedBox(width: 6),
                Flexible(
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
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar estoque',
            onPressed: _saindo || loja.isEmpty ? null : _recarregar,
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
        child: AbsorbPointer(
          absorbing: _saindo,
          child: loja.isEmpty
              ? const Center(
                  child: Text('Selecione uma loja para consultar o estoque.'),
                )
              : LayoutBuilder(
                  builder: (context, limites) {
                    final margem = limites.maxWidth >= 720 ? 32.0 : 14.0;
                    final largura = (limites.maxWidth - margem * 2)
                        .clamp(0.0, 1180.0)
                        .toDouble();
                    return Center(
                      child: SizedBox(
                        width: largura,
                        child: StreamBuilder<_ListaEstoque>(
                          key: ValueKey(loja),
                          stream: _estoque,
                          builder: (context, snapshot) =>
                              _conteudo(snapshot, largura),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _conteudo(AsyncSnapshot<_ListaEstoque> snapshot, double largura) {
    final estoque = snapshot.data;
    final produtos = estoque?.buscar(_termo) ?? const <_ProdutoBaixo>[];
    final colunas = largura >= 800 ? 2 : 1;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: _barraBusca(estoque?.produtos.length, produtos.length),
        ),
        if (snapshot.hasError)
          SliverToBoxAdapter(
            child: _estado(
              'Não foi possível consultar o estoque.',
              acao: TextButton(
                onPressed: _recarregar,
                child: const Text('Tentar novamente'),
              ),
            ),
          )
        else if (estoque == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(color: _marca)),
            ),
          )
        else if (produtos.isEmpty)
          SliverToBoxAdapter(
            child: _estado(
              _termo.isEmpty
                  ? 'Nenhum produto com estoque baixo nesta loja.'
                  : 'Nenhum produto encontrado com essa busca.',
              acao: _termo.isEmpty
                  ? null
                  : TextButton(
                      onPressed: _limparBusca,
                      child: const Text('Limpar busca'),
                    ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, linha) {
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
                              ? _produto(produtos[inicio + coluna])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              }, childCount: (produtos.length + colunas - 1) ~/ colunas),
            ),
          ),
      ],
    );
  }

  Widget _barraBusca(int? total, int encontrados) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _busca,
            textInputAction: TextInputAction.search,
            onChanged: _alterarBusca,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              labelText: 'Buscar produto, código ou categoria',
              prefixIcon: const Icon(Icons.search, color: _marca),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _busca,
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
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _borda),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _marca, width: 1.5),
              ),
            ),
          ),
          if (total != null) ...[
            const SizedBox(height: 12),
            Text(
              _termo.isEmpty
                  ? (total == 1
                        ? '1 produto com estoque baixo'
                        : '${_numero.format(total)} produtos com estoque baixo')
                  : '${_numero.format(encontrados)} de ${_numero.format(total)} produtos com estoque baixo',
              style: const TextStyle(
                color: _suave,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _estado(String texto, {Widget? acao}) {
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _suave),
            ),
            if (acao != null) acao,
          ],
        ),
      ),
    );
  }

  Widget _produto(_ProdutoBaixo produto) {
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 3),
                      Text(
                        produto.categoria,
                        style: const TextStyle(color: _suave),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Código: ${produto.codigo}',
                        style: const TextStyle(color: _suave, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _selo(
              produto.quantidade == null
                  ? 'Saldo total não informado'
                  : 'Saldo total · ${_numero.format(produto.quantidade)}',
              critico: produto.quantidade != null && produto.quantidade! <= 0,
              atencao: _baixo(produto.quantidade),
            ),
            if (produto.alertas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final alerta in produto.alertas.take(6))
                    _seloAlerta(alerta),
                ],
              ),
              if (produto.alertas.length > 6)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: _marca),
                  onPressed: () => _mostrarAlertas(produto),
                  child: Text(
                    'Ver todos os alertas (${produto.alertas.length})',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _foto(String endereco) {
    const vazia = ColoredBox(
      color: _rosaClaro,
      child: Center(child: Icon(Icons.checkroom, color: _marca)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 60,
        child: endereco.isEmpty
            ? vazia
            : Image.network(
                endereco,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (context, erro, pilha) => vazia,
              ),
      ),
    );
  }

  void _mostrarAlertas(_ProdutoBaixo produto) {
    showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        scrollable: true,
        title: Text(produto.nome),
        content: SizedBox(
          width: 400,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: produto.alertas.map(_seloAlerta).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(),
            child: const Text('Fechar'),
          ),
        ],
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
              _link(
                Icons.dashboard_outlined,
                'Início',
                () => HomeView(lojaSelecionada: loja),
              ),
            _link(
              Icons.point_of_sale,
              'Nova venda',
              () => VendasView(lojaSelecionada: loja),
            ),
            _link(
              Icons.checkroom,
              'Produtos',
              () => ProdutosView(lojaSelecionada: loja),
            ),
            _link(
              Icons.add_box_outlined,
              'Adicionar produto',
              () => AdicionarProdutosView(lojaSelecionada: loja),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Estoque baixo'),
              selected: true,
              selectedColor: _marca,
              selectedTileColor: _rosaClaro,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
            _link(
              Icons.people_outline,
              'Clientes',
              () => ClientesView(lojaSelecionada: loja),
            ),
            if (_tipoUsuario == 'funcionario')
              _link(
                Icons.receipt_long_outlined,
                'Vendas realizadas',
                () => VendasRealizadasView(lojaSelecionada: loja),
              ),
            if (_tipoUsuario == 'admin') ...[
              _link(
                Icons.bar_chart,
                'Relatórios',
                () => RelatoriosView(lojaSelecionada: loja),
              ),
              _link(
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

  Widget _link(IconData icone, String nome, Widget Function() abrir) {
    return ListTile(
      leading: Icon(icone, color: _suave),
      title: Text(nome),
      onTap: () {
        if (_saindo) return;
        final navegador = Navigator.of(context);
        navegador.pop();
        navegador.pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => abrir()),
        );
      },
    );
  }
}

class _ProdutoBaixo {
  factory _ProdutoBaixo(Map<String, dynamic> dados, String id) {
    final quantidade = dados['quantidade'];
    final alertas = <_AlertaEstoque>[];
    final tamanhosComVariacaoBaixa = <String>{};
    final grade = dados['tamanhosCores'];
    if (grade is Map) {
      for (final entrada in grade.entries) {
        final cores = entrada.value;
        if (cores is! Map) continue;
        final tamanho = entrada.key.toString();
        for (final cor in cores.entries) {
          final qtd = cor.value;
          if (qtd is num && _baixo(qtd)) {
            tamanhosComVariacaoBaixa.add(tamanho);
            alertas.add(_AlertaEstoque('$tamanho · ${cor.key}', qtd));
          }
        }
      }
    }

    final tamanhos = dados['tamanhos'];
    if (tamanhos is Map) {
      for (final entrada in tamanhos.entries) {
        final tamanho = entrada.key.toString();
        final qtd = entrada.value;
        if (qtd is num &&
            _baixo(qtd) &&
            !tamanhosComVariacaoBaixa.contains(tamanho)) {
          alertas.add(_AlertaEstoque(tamanho, qtd));
        }
      }
    }
    alertas.sort((a, b) {
      final porQuantidade = a.quantidade.compareTo(b.quantidade);
      return porQuantidade == 0 ? a.rotulo.compareTo(b.rotulo) : porQuantidade;
    });

    final nome = _campo(dados['nome'], 'Produto sem nome');
    final categoria = _campo(dados['categoria'], 'Sem categoria');
    final codigo = _campo(dados['codigoBarras'], id);
    return _ProdutoBaixo._(
      nome,
      categoria,
      codigo,
      _campo(dados['foto']),
      quantidade is num ? quantidade : null,
      alertas,
      _normalizar(nome),
      _normalizar('$nome $categoria $codigo $id'),
    );
  }

  const _ProdutoBaixo._(
    this.nome,
    this.categoria,
    this.codigo,
    this.foto,
    this.quantidade,
    this.alertas,
    this.nomeBusca,
    this.textoBusca,
  );

  final String nome;
  final String categoria;
  final String codigo;
  final String foto;
  final num? quantidade;
  final List<_AlertaEstoque> alertas;
  final String nomeBusca;
  final String textoBusca;

  bool get temEstoqueBaixo => _baixo(quantidade) || alertas.isNotEmpty;
  bool get esgotado =>
      (quantidade != null && quantidade! <= 0) ||
      alertas.any((alerta) => alerta.quantidade <= 0);
}

class _AlertaEstoque {
  const _AlertaEstoque(this.rotulo, this.quantidade);

  final String rotulo;
  final num quantidade;
}

class _ListaEstoque {
  _ListaEstoque(this.produtos);

  final List<_ProdutoBaixo> produtos;
  String? _ultimaBusca;
  List<_ProdutoBaixo> _resultado = const [];

  List<_ProdutoBaixo> buscar(String termo) {
    if (termo.isEmpty) return produtos;
    if (termo == _ultimaBusca) return _resultado;

    final partes = termo.split(' ');
    _resultado = produtos
        .where((produto) => partes.every(produto.textoBusca.contains))
        .toList();
    _ultimaBusca = termo;
    return _resultado;
  }
}

// Mesmo limite usado pelo indicador de estoque baixo na Home.
bool _baixo(Object? quantidade) =>
    quantidade is num && quantidade <= _limiteBaixo;

Widget _seloAlerta(_AlertaEstoque alerta) => _selo(
  '${alerta.rotulo} · ${_numero.format(alerta.quantidade)}',
  critico: alerta.quantidade <= 0,
  atencao: true,
);

Widget _selo(String texto, {bool critico = false, bool atencao = false}) {
  final cor = critico ? _erro : (atencao ? _aviso : _marca);
  final fundo = critico ? _erroClaro : (atencao ? _avisoClaro : _rosaClaro);
  return DecoratedBox(
    decoration: BoxDecoration(
      color: fundo,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

Widget _cartao(Widget filho) {
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

String _campo(Object? valor, [String padrao = '']) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}

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
