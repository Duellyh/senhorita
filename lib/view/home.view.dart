import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/estoque.view.dart';
import 'package:senhorita/view/financeiro.especifico.dart';
import 'package:senhorita/view/financeiro.view.dart';
import 'package:senhorita/view/historico.vendas.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'login.view.dart';

class HomeView extends StatefulWidget {
  final String lojaSelecionada;
  const HomeView({super.key, required this.lojaSelecionada});

  @override
  State<HomeView> createState() => _HomeViewState();
}

typedef _Documento = QueryDocumentSnapshot<Map<String, dynamic>>;
typedef _PaginaDaLoja = Widget Function(String loja);

class _HomeViewState extends State<HomeView> {
  static const _fundo = Color(0xFFFAF7F9);
  static const _texto = Color(0xFF301F2C);
  static const _suave = Color(0xFF695763);
  static const _marca = Color(0xFF832958);
  static const _rosaClaro = Color(0xFFF8EAF2);
  static const _borda = Color(0xFFEADDE5);
  static const _aviso = Color(0xFF8C500F);
  static const _avisoClaro = Color(0xFFFFF1DE);

  final _db = FirebaseFirestore.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dataHora = DateFormat('dd/MM/yyyy • HH:mm');
  final _numero = NumberFormat.decimalPattern('pt_BR');

  String _tipoUsuario = '';
  String _nomeUsuario = '';
  String _lojaDoPerfil = '';
  String? _lojaDoPainel;
  bool _carregandoPerfil = true;
  bool _erroPerfil = false;
  bool _saindo = false;
  int _versaoPainel = 0;

  Stream<_ResumoProdutos>? _produtos;
  Stream<List<_VendaRecente>>? _vendasRecentes;
  Future<int?>? _totalVendas;
  Future<int?>? _totalClientes;

  String get _lojaAtual {
    final loja = widget.lojaSelecionada.trim();
    return loja.isNotEmpty ? loja : _lojaDoPerfil;
  }

  @override
  void initState() {
    super.initState();
    _prepararPainel();
    _carregarPerfil();
  }

  @override
  void didUpdateWidget(covariant HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepararPainel();
  }

  Future<void> _carregarPerfil() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final perfil = uid == null
          ? null
          : (await _db.collection('usuarios').doc(uid).get()).data();
      if (!mounted) return;

      setState(() {
        _tipoUsuario = _textoCampo(perfil?['tipo']);
        if (uid != null && _tipoUsuario.isEmpty) _tipoUsuario = 'funcionario';
        _nomeUsuario = _textoCampo(perfil?['nome']);
        _lojaDoPerfil = _textoCampo(perfil?['lojaSelecionada']);
        _carregandoPerfil = false;
        _erroPerfil = false;
        _prepararPainel();
      });
    } catch (erro) {
      debugPrint('Home • perfil: $erro');
      if (!mounted) return;
      setState(() {
        _carregandoPerfil = false;
        _erroPerfil = true;
      });
    }
  }

  void _prepararPainel({bool recarregar = false}) {
    final loja = _lojaAtual;
    if (loja.isEmpty) {
      _versaoPainel++;
      _lojaDoPainel = null;
      _produtos = null;
      _vendasRecentes = null;
      _totalVendas = null;
      _totalClientes = null;
      return;
    }
    if (!recarregar && _lojaDoPainel == loja) return;

    _lojaDoPainel = loja;
    // A mesma leitura alimenta os indicadores e a lista de produtos recentes.
    _produtos = _db
        .collection('produtos')
        .where('loja', isEqualTo: loja)
        .snapshots()
        .map(_ResumoProdutos.daConsulta);
    _vendasRecentes = _observarVendasRecentes(loja, ++_versaoPainel);
    _atualizarContadores(loja);
  }

  void _atualizarContadores(String loja) {
    _totalVendas = _contar(
      'vendas',
      _db.collection('vendas').where('loja', isEqualTo: loja),
    );
    // O cadastro é compartilhado. Conte os mesmos registros da tela Clientes.
    _totalClientes = _contar(
      'clientes',
      _db.collection('clientes').orderBy('nome'),
    );
  }

  Future<int?> _contar(
    String colecao,
    Query<Map<String, dynamic>> consulta,
  ) async {
    try {
      return (await consulta.count().get()).count;
    } catch (erro) {
      debugPrint('Home • contagem de $colecao: $erro');
      return null;
    }
  }

  void _recarregar() {
    setState(() => _prepararPainel(recarregar: true));
    if (_erroPerfil) _carregarPerfil();
  }

  Stream<List<_VendaRecente>> _observarVendasRecentes(String loja, int versao) {
    final porData = _db
        .collection('vendas')
        .orderBy('dataVenda', descending: true);
    final pagina = porData.limit(25);
    // A primeira página acompanha novas vendas. Páginas anteriores são
    // consultadas conforme a necessidade para encontrar cinco da loja.
    return pagina.snapshots().asyncMap(
      (snapshot) => _buscarVendasRecentes(pagina, snapshot.docs, loja, versao),
    );
  }

  Future<List<_VendaRecente>> _buscarVendasRecentes(
    Query<Map<String, dynamic>> pagina,
    List<_Documento> documentos,
    String loja,
    int versao,
  ) async {
    final resultado = <_VendaRecente>[];
    final codigosConsultados = <String>{};
    final codigosDaLoja = <String>{};

    while (documentos.isNotEmpty && mounted && _versaoPainel == versao) {
      final vendas = documentos.map((doc) => _VendaRecente(doc.data(), loja));
      final pendentes = <_VendaRecente>[];
      var confirmadas = resultado.length;

      for (final venda in vendas) {
        pendentes.add(venda);
        if (venda.pertenceALoja) confirmadas++;
        if (confirmadas == 5) break;
      }

      final codigos = <String>{
        for (final venda in pendentes)
          if (!venda.pertenceALoja) ...venda.codigosLegados,
      }.difference(codigosConsultados).toList();

      // Somente os itens antigos sem loja gravada consultam o catálogo.
      for (var inicio = 0; inicio < codigos.length; inicio += 10) {
        final lote = codigos.skip(inicio).take(10).toList();
        final produtos = await _db
            .collection('produtos')
            .where('codigoBarras', whereIn: lote)
            .get();
        codigosConsultados.addAll(lote);
        for (final produto in produtos.docs) {
          final dados = produto.data();
          if (_textoCampo(dados['loja']) == loja) {
            codigosDaLoja.add(_textoCampo(dados['codigoBarras']));
          }
        }
      }

      for (final venda in pendentes) {
        // Os códigos legados só são usados para definir inclusão quando a
        // venda ainda não está associada ao caixa ou a um item da loja.
        if (!venda.pertenceALoja) {
          venda.temItemDaLoja = venda.codigosLegados.any(
            codigosDaLoja.contains,
          );
        }
        if (venda.pertenceALoja) resultado.add(venda);
        if (resultado.length == 5) return resultado;
      }

      if (documentos.length < 25 || !mounted || _versaoPainel != versao) {
        break;
      }
      documentos =
          (await pagina.startAfterDocument(documentos.last).get()).docs;
    }

    return resultado;
  }

  Future<void> _abrir(_PaginaDaLoja pagina, {bool peloMenu = false}) async {
    final loja = _lojaAtual;
    final navigator = Navigator.of(context);
    if (peloMenu) navigator.pop();
    if (loja.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma loja primeiro.')),
      );
      return;
    }

    final rota = MaterialPageRoute<void>(builder: (_) => pagina(loja));
    if (peloMenu) {
      navigator.pushReplacement<void, void>(rota);
      return;
    }

    await navigator.push<void>(rota);
    if (!mounted || _lojaAtual != loja) return;
    setState(() => _atualizarContadores(loja));
  }

  Future<void> _sair() async {
    if (_saindo) return;
    setState(() => _saindo = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    } catch (erro) {
      debugPrint('Home • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível sair. Tente novamente.'),
        ),
      );
    }
  }

  Widget _novaVenda(String loja) => VendasView(lojaSelecionada: loja);
  Widget _paginaProdutos(String loja) => ProdutosView(lojaSelecionada: loja);
  Widget _estoqueBaixo(String loja) => EstoqueView(lojaSelecionada: loja);
  Widget _clientes(String loja) => ClientesView(lojaSelecionada: loja);

  Widget _historico(String loja) {
    return HistoricoVendasView(lojaSelecionada: loja);
  }

  @override
  Widget build(BuildContext context) {
    final loja = _lojaAtual;
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
              'Senhorita Cintas Modeladores',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
                      loja.isNotEmpty
                          ? loja
                          : _carregandoPerfil
                          ? 'Carregando loja…'
                          : 'Nenhuma loja selecionada',
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
            tooltip: 'Atualizar painel',
            onPressed: loja.isNotEmpty || _erroPerfil ? _recarregar : null,
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
      drawer: _menu(),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final margem = viewport.maxWidth >= 720 ? 32.0 : 16.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(margem, 28, margem, 36),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: SizedBox(
                    width: double.infinity,
                    child: _conteudo(loja),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _menu() {
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
              subtitle: _lojaAtual.isEmpty ? null : Text(_lojaAtual),
            ),
            const Divider(color: _borda),
            if (_tipoUsuario == 'admin')
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Início'),
                selected: true,
                selectedColor: _marca,
                selectedTileColor: _rosaClaro,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
            _linkMenu(Icons.point_of_sale, 'Nova venda', _novaVenda),
            _linkMenu(Icons.checkroom, 'Produtos', _paginaProdutos),
            _linkMenu(
              Icons.add_box_outlined,
              'Adicionar produto',
              (loja) => AdicionarProdutosView(lojaSelecionada: loja),
            ),
            _linkMenu(Icons.people_outline, 'Clientes', _clientes),
            if (_tipoUsuario == 'funcionario')
              _linkMenu(
                Icons.receipt_long_outlined,
                'Vendas realizadas',
                (loja) => VendasRealizadasView(lojaSelecionada: loja),
              ),
            if (_tipoUsuario == 'admin') ...[
              _linkMenu(
                Icons.bar_chart,
                'Relatórios',
                (loja) => RelatoriosView(lojaSelecionada: loja),
              ),
              _linkMenu(
                Icons.settings_outlined,
                'Configurações',
                (loja) => ConfiguracoesView(lojaSelecionada: loja),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linkMenu(IconData icone, String texto, _PaginaDaLoja pagina) {
    return ListTile(
      leading: Icon(icone, color: _suave),
      title: Text(texto),
      onTap: () => _abrir(pagina, peloMenu: true),
    );
  }

  Widget _conteudo(String loja) {
    if (loja.isEmpty) {
      return _superficie(
        _carregandoPerfil
            ? _carregamento()
            : _mensagem(
                _erroPerfil
                    ? 'Não foi possível carregar a loja do seu perfil.'
                    : 'Selecione uma loja para abrir o painel.',
                tentarNovamente: _erroPerfil,
              ),
      );
    }

    return StreamBuilder<_ResumoProdutos>(
      key: ValueKey('catalogo-$loja'),
      stream: _produtos,
      builder: (context, snapshot) => _painelDaLoja(loja, snapshot),
    );
  }

  Widget _painelDaLoja(String loja, AsyncSnapshot<_ResumoProdutos> catalogo) {
    final resumo = catalogo.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Painel da loja',
          style: TextStyle(
            color: _texto,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        if (_nomeUsuario.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Olá, $_nomeUsuario', style: const TextStyle(color: _suave)),
        ],
        const SizedBox(height: 22),
        _faixaResponsiva(
          larguraMinima: 218,
          maxColunas: 3,
          filhos: [
            _atalho(
              Icons.point_of_sale,
              'Nova venda',
              _novaVenda,
              principal: true,
            ),
            _atalho(Icons.checkroom, 'Produtos', _paginaProdutos),
            _atalho(Icons.inventory_2_outlined, 'Estoque baixo', _estoqueBaixo),
          ],
        ),
        const SizedBox(height: 28),
        _titulo('Indicadores'),
        const SizedBox(height: 12),
        _faixaResponsiva(
          larguraMinima: 144,
          maxColunas: 4,
          filhos: [
            _indicador(
              Icons.checkroom,
              'Produtos',
              resumo?.total,
              _paginaProdutos,
              falha: catalogo.hasError,
            ),
            _contador(
              Icons.receipt_long_outlined,
              'Vendas',
              _totalVendas,
              _historico,
            ),
            _contador(
              Icons.people_outline,
              'Clientes',
              _totalClientes,
              _clientes,
            ),
            _indicador(
              Icons.inventory_2_outlined,
              'Estoque baixo',
              resumo?.estoqueBaixo,
              _estoqueBaixo,
              falha: catalogo.hasError,
              aviso: (resumo?.estoqueBaixo ?? 0) > 0,
            ),
          ],
        ),
        const SizedBox(height: 28),
        _faixaResponsiva(
          larguraMinima: 390,
          maxColunas: 2,
          filhos: [
            _painel(
              'Últimas vendas',
              'Histórico',
              _historico,
              _listaVendas(loja),
            ),
            _painel(
              'Produtos recentes',
              'Ver produtos',
              _paginaProdutos,
              _listaProdutos(catalogo),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _titulo('Financeiro'),
        const SizedBox(height: 12),
        _faixaResponsiva(
          larguraMinima: 248,
          maxColunas: 2,
          filhos: [
            _atalho(
              Icons.insights,
              'Financeiro geral',
              (loja) => FinanceiroView(lojaSelecionada: loja),
            ),
            _atalho(
              Icons.analytics_outlined,
              'Financeiro específico',
              (loja) => FinanceiroEspecificoView(lojaSelecionada: loja),
            ),
          ],
        ),
      ],
    );
  }

  Widget _faixaResponsiva({
    required double larguraMinima,
    required int maxColunas,
    required List<Widget> filhos,
  }) {
    const espaco = 12.0;
    return LayoutBuilder(
      builder: (context, limites) {
        final colunas = ((limites.maxWidth + espaco) / (larguraMinima + espaco))
            .floor()
            .clamp(1, maxColunas)
            .toInt();
        final largura = (limites.maxWidth - espaco * (colunas - 1)) / colunas;
        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            for (final filho in filhos) SizedBox(width: largura, child: filho),
          ],
        );
      },
    );
  }

  Widget _atalho(
    IconData icone,
    String rotulo,
    _PaginaDaLoja pagina, {
    bool principal = false,
  }) {
    final cor = principal ? Colors.white : _marca;
    return _superficie(
      InkWell(
        onTap: () => _abrir(pagina),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _icone(
                icone,
                cor,
                principal ? const Color(0xFF9C4875) : _rosaClaro,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    color: principal ? Colors.white : _texto,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cor, size: 20),
            ],
          ),
        ),
      ),
      cor: principal ? _marca : Colors.white,
    );
  }

  Widget _contador(
    IconData icone,
    String rotulo,
    Future<int?>? consulta,
    _PaginaDaLoja pagina,
  ) {
    return FutureBuilder<int?>(
      future: consulta,
      builder: (context, snapshot) => _indicador(
        icone,
        rotulo,
        snapshot.data,
        pagina,
        falha:
            snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                snapshot.data == null),
      ),
    );
  }

  Widget _indicador(
    IconData icone,
    String rotulo,
    int? valor,
    _PaginaDaLoja pagina, {
    bool aviso = false,
    bool falha = false,
  }) {
    return _superficie(
      InkWell(
        onTap: () => _abrir(pagina),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _icone(
                icone,
                aviso ? _aviso : _marca,
                aviso ? _avisoClaro : _rosaClaro,
              ),
              const SizedBox(height: 10),
              Text(
                valor == null ? (falha ? '—' : '…') : _numero.format(valor),
                semanticsLabel: falha ? 'Indisponível' : null,
                style: TextStyle(
                  color: aviso ? _aviso : _texto,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(rotulo, style: const TextStyle(color: _suave, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _painel(
    String titulo,
    String acao,
    _PaginaDaLoja pagina,
    Widget conteudo,
  ) {
    return _superficie(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(child: _titulo(titulo)),
                const SizedBox(width: 8),
                Flexible(
                  child: TextButton(
                    onPressed: () => _abrir(pagina),
                    style: TextButton.styleFrom(foregroundColor: _marca),
                    child: Text(acao, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _borda),
          conteudo,
        ],
      ),
    );
  }

  Widget _listaVendas(String loja) {
    return StreamBuilder<List<_VendaRecente>>(
      key: ValueKey('vendas-$loja'),
      stream: _vendasRecentes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _mensagem(
            'Não foi possível carregar as vendas.',
            tentarNovamente: true,
          );
        }

        final vendas = snapshot.data;
        if (vendas == null) return _carregamento();
        if (vendas.isEmpty) {
          return _mensagem('Nenhuma venda encontrada para esta loja.');
        }

        return _linhas([
          for (final venda in vendas)
            _linha(
              icone: Icons.receipt_long_outlined,
              titulo: 'Venda de ${_formatarValor(venda.dados['totalVenda'])}',
              detalhe: _formatarData(venda.dados['dataVenda']),
              observacao: [
                if (venda.ehDoCaixa) 'Caixa da loja',
                if (venda.temItemDaLoja) 'Itens da loja',
                if (venda.cancelada) 'Cancelada',
              ].join(' · '),
              aviso: venda.cancelada,
            ),
        ]);
      },
    );
  }

  Widget _listaProdutos(AsyncSnapshot<_ResumoProdutos> snapshot) {
    if (snapshot.hasError) {
      return _mensagem(
        'Não foi possível carregar os produtos.',
        tentarNovamente: true,
      );
    }

    final produtos = snapshot.data?.recentes;
    if (produtos == null) return _carregamento();
    if (produtos.isEmpty) {
      return _mensagem('Nenhum produto recente cadastrado.');
    }

    return _linhas([
      for (final produto in produtos)
        _linha(
          icone: Icons.checkroom,
          titulo: _textoCampo(produto['nome'], padrao: 'Produto sem nome'),
          detalhe: _textoCampo(produto['categoria'], padrao: 'Sem categoria'),
          observacao: _formatarValor(produto['precoVenda']),
        ),
    ]);
  }

  String _formatarValor(Object? valor) {
    final numero = valor is num
        ? valor
        : double.tryParse(_textoCampo(valor).replaceFirst(',', '.'));
    return numero == null || !numero.isFinite ? '—' : _moeda.format(numero);
  }

  String _formatarData(Object? valor) {
    return valor is Timestamp ? _dataHora.format(valor.toDate()) : 'Sem data';
  }

  Widget _linhas(List<Widget> linhas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < linhas.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, indent: 16, endIndent: 16, color: _borda),
          linhas[i],
        ],
      ],
    );
  }

  Widget _linha({
    required IconData icone,
    required String titulo,
    required String detalhe,
    required String observacao,
    bool aviso = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _icone(
            icone,
            aviso ? _aviso : _marca,
            aviso ? _avisoClaro : _rosaClaro,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: _texto,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detalhe,
                  style: const TextStyle(color: _suave, fontSize: 13),
                ),
                if (observacao.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    observacao,
                    style: TextStyle(
                      color: aviso ? _aviso : _marca,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _superficie(Widget filho, {Color cor = Colors.white}) {
    return Material(
      color: cor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cor == _marca ? _marca : _borda),
      ),
      clipBehavior: Clip.antiAlias,
      child: filho,
    );
  }

  Widget _titulo(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        color: _texto,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _icone(IconData icone, Color cor, Color fundo) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icone, color: cor, size: 20),
      ),
    );
  }

  Widget _mensagem(String texto, {bool tentarNovamente = false}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: const TextStyle(color: _suave)),
          if (tentarNovamente)
            TextButton(
              onPressed: _recarregar,
              style: TextButton.styleFrom(foregroundColor: _marca),
              child: const Text('Tentar novamente'),
            ),
        ],
      ),
    );
  }

  Widget _carregamento() {
    return const Padding(
      padding: EdgeInsets.all(22),
      child: Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: _marca),
        ),
      ),
    );
  }
}

String _textoCampo(Object? valor, {String padrao = ''}) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}

class _ResumoProdutos {
  const _ResumoProdutos(this.total, this.estoqueBaixo, this.recentes);

  final int total;
  final int estoqueBaixo;
  final List<Map<String, dynamic>> recentes;

  factory _ResumoProdutos.daConsulta(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    var estoqueBaixo = 0;
    final recentes = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final dados = doc.data();
      if (_ehEstoqueBaixo(dados)) estoqueBaixo++;
      final data = dados['dataCadastro'];
      if (data is! Timestamp) continue;

      final indice = recentes.indexWhere(
        (produto) => data.compareTo(produto['dataCadastro'] as Timestamp) > 0,
      );
      if (indice >= 0) {
        recentes.insert(indice, dados);
      } else if (recentes.length < 5) {
        recentes.add(dados);
      }
      if (recentes.length > 5) recentes.removeLast();
    }
    return _ResumoProdutos(snapshot.size, estoqueBaixo, recentes);
  }

  static bool _ehEstoqueBaixo(Map<String, dynamic> dados) {
    bool baixo(Object? quantidade) => quantidade is num && quantidade <= 1;

    final tamanhos = dados['tamanhos'];
    final grade = dados['tamanhosCores'];
    return baixo(dados['quantidade']) ||
        (tamanhos is Map && tamanhos.values.any(baixo)) ||
        (grade is Map &&
            grade.values.any(
              (cores) => cores is Map && cores.values.any(baixo),
            ));
  }
}

class _VendaRecente {
  _VendaRecente(this.dados, String loja) {
    final lojaCaixa = _textoCampo(
      dados['lojaCaixa'],
      padrao: _textoCampo(dados['loja']),
    );
    ehDoCaixa = lojaCaixa == loja;

    final lojasRegistradas = dados['lojaProdutoOficial'];
    final lojasDosProdutos = lojasRegistradas is Iterable
        ? lojasRegistradas
              .map((valor) => _textoCampo(valor))
              .where((valor) => valor.isNotEmpty)
              .toSet()
        : <String>{
            if (_textoCampo(lojasRegistradas).isNotEmpty)
              _textoCampo(lojasRegistradas),
          };

    temItemDaLoja = lojasDosProdutos.contains(loja);
    final itens = dados['itens'];
    final itensValidos = itens is Iterable
        ? itens.whereType<Map>()
        : const <Map>[];
    var temItens = false;

    for (final item in itensValidos) {
      temItens = true;
      final lojaItem = _textoCampo(
        item['lojaProduto'],
        padrao: _textoCampo(item['loja']),
      );
      if (lojaItem == loja) temItemDaLoja = true;
      if (lojaItem.isEmpty && lojasDosProdutos.isEmpty) _adicionarCodigo(item);
    }

    if (!temItens && lojasDosProdutos.isEmpty) _adicionarCodigo(dados);
  }

  final Map<String, dynamic> dados;
  final codigosLegados = <String>{};
  late final bool ehDoCaixa;
  late bool temItemDaLoja;

  bool get pertenceALoja => ehDoCaixa || temItemDaLoja;
  bool get cancelada =>
      dados['cancelada'] == true ||
      _textoCampo(dados['status']).toLowerCase() == 'cancelada';

  void _adicionarCodigo(Map item) {
    for (final campo in const [
      'codigoBarras',
      'codigo',
      'barcode',
      'produtoId',
    ]) {
      final codigo = _textoCampo(item[campo]);
      if (codigo.isNotEmpty) {
        codigosLegados.add(codigo);
        return;
      }
    }
  }
}
