import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/estoque.view.dart';
import 'package:senhorita/view/historico.vendas.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/financeiro.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class RelatoriosView extends StatefulWidget {
  final String lojaSelecionada;

  const RelatoriosView({super.key, required this.lojaSelecionada});

  @override
  State<RelatoriosView> createState() => _RelatoriosViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);
const _verde = Color(0xFF23603B);
const _verdeClaro = Color(0xFFE8F3EC);

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _numero = NumberFormat.decimalPattern('pt_BR');

class _RelatoriosViewState extends State<RelatoriosView> {
  final _db = FirebaseFirestore.instance;
  Future<_ResumoVendas>? _vendas;
  late Future<int> _clientes;

  String _tipoUsuario = '';
  String _nomeUsuario = '';
  bool _saindo = false;
  bool _atualizando = false;

  String get _loja => widget.lojaSelecionada.trim();

  @override
  void initState() {
    super.initState();
    final loja = _loja;
    _vendas = loja.isEmpty ? null : _consultarVendas(loja);
    _clientes = _contarClientes();
    _carregarPerfil();
  }

  @override
  void didUpdateWidget(covariant RelatoriosView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loja = _loja;
    if (oldWidget.lojaSelecionada.trim() != loja) {
      _vendas = loja.isEmpty ? null : _consultarVendas(loja);
    }
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
      debugPrint('Relatórios • perfil: $erro');
      if (mounted) _avisar('Não foi possível carregar o perfil do usuário.');
    }
  }

  Future<_ResumoVendas> _consultarVendas(String loja) async {
    final consulta = _db.collection('vendas').where('loja', isEqualTo: loja);
    try {
      // Consultas separadas mantêm vendas antigas sem totalPago na contagem.
      final resultados = await Future.wait<AggregateQuerySnapshot>([
        consulta.count().get(),
        consulta.aggregate(sum('totalPago')).get(),
      ]);
      final quantidade = resultados.first.count;
      final totalPago = resultados.last.getSum('totalPago');
      if (quantidade == null || totalPago == null || !totalPago.isFinite) {
        throw StateError('O Firestore não retornou o resumo completo.');
      }
      return _ResumoVendas(quantidade, totalPago);
    } catch (erro) {
      debugPrint('Relatórios • agregação de vendas: $erro');
      // A consulta original cobre SDKs sem soma e índices ainda indisponíveis.
      final dados = await consulta.get();
      return _ResumoVendas.daConsulta(dados);
    }
  }

  Future<int> _contarClientes() async {
    // Mesmos documentos exibidos na tela Clientes e contados na Home.
    final consulta = _db.collection('clientes').orderBy('nome');
    try {
      final contagem = (await consulta.count().get()).count;
      if (contagem != null) return contagem;
    } catch (erro) {
      debugPrint('Relatórios • contagem de clientes: $erro');
    }
    return (await consulta.get()).size;
  }

  Future<void> _recarregar() async {
    if (_atualizando || _saindo) return;
    final loja = _loja;
    final vendas = loja.isEmpty ? null : _consultarVendas(loja);
    final clientes = _contarClientes();
    setState(() {
      _atualizando = true;
      _vendas = vendas;
      _clientes = clientes;
    });
    try {
      await Future.wait<Object>([if (vendas != null) vendas, clientes]);
    } catch (erro) {
      debugPrint('Relatórios • atualização: $erro');
    } finally {
      if (mounted) setState(() => _atualizando = false);
    }
  }

  void _avisar(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
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
      debugPrint('Relatórios • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      _avisar('Não foi possível sair.');
    }
  }

  void _abrirRelatorio(Widget Function(String) abrir) {
    final loja = _loja;
    if (loja.isEmpty || _saindo) return;
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => abrir(loja)));
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
              'Relatórios',
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
            tooltip: 'Atualizar relatórios',
            onPressed: _saindo || _atualizando ? null : _recarregar,
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
          child: LayoutBuilder(
            builder: (context, limites) {
              final margem = limites.maxWidth >= 720 ? 32.0 : 14.0;
              return RefreshIndicator(
                color: _marca,
                onRefresh: _recarregar,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(margem, 24, margem, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: SizedBox(
                          width: double.infinity,
                          child: _conteudo(loja),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _conteudo(String loja) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('Visão geral'),
        const SizedBox(height: 12),
        _indicadores(loja),
        const SizedBox(height: 26),
        _titulo('Relatórios detalhados'),
        const SizedBox(height: 12),
        if (loja.isEmpty)
          const Text(
            'Selecione uma loja para acessar os relatórios.',
            style: TextStyle(color: _suave),
          )
        else
          _grade([
            _atalho(
              Icons.inventory_2_outlined,
              'Produtos com estoque baixo',
              (loja) => EstoqueView(lojaSelecionada: loja),
            ),
            _atalho(
              Icons.history,
              'Histórico de vendas',
              (loja) => HistoricoVendasView(lojaSelecionada: loja),
            ),
            _atalho(
              Icons.insights,
              'Dashboard financeiro',
              (loja) => FinanceiroView(lojaSelecionada: loja),
            ),
          ], larguraMinima: 245),
      ],
    );
  }

  Widget _indicadores(String loja) {
    return FutureBuilder<_ResumoVendas>(
      key: ValueKey(loja),
      future: _vendas,
      builder: (context, vendas) {
        final resumo = vendas.data;
        final vazio = loja.isEmpty;
        final carregando =
            !vazio && vendas.connectionState == ConnectionState.waiting;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _grade([
              _indicador(
                Icons.receipt_long_outlined,
                'Vendas registradas',
                resumo == null ? null : _numero.format(resumo.quantidade),
                'Unidade ativa · inclui canceladas',
                carregando: carregando,
              ),
              _indicador(
                Icons.payments_outlined,
                'Total pago registrado',
                resumo == null ? null : _moeda.format(resumo.totalPago),
                'Unidade ativa · antes do troco, inclui canceladas',
                carregando: carregando,
                financeiro: true,
              ),
              FutureBuilder<int>(
                future: _clientes,
                builder: (context, clientes) => _indicador(
                  Icons.people_outline,
                  'Clientes cadastrados',
                  clientes.data == null ? null : _numero.format(clientes.data),
                  'Cadastro compartilhado entre as lojas',
                  carregando:
                      clientes.connectionState == ConnectionState.waiting,
                  falha: clientes.hasError,
                ),
              ),
            ], larguraMinima: 210),
            if (vendas.hasError) ...[
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  const Text(
                    'Não foi possível carregar as vendas.',
                    style: TextStyle(color: _suave),
                  ),
                  TextButton(
                    onPressed: _recarregar,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _indicador(
    IconData icone,
    String nome,
    String? valor,
    String detalhe, {
    required bool carregando,
    bool financeiro = false,
    bool falha = false,
  }) {
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _icone(icone, financeiro: financeiro),
            const SizedBox(height: 10),
            Text(
              valor ?? (carregando ? '…' : '—'),
              semanticsLabel: valor == null
                  ? (carregando ? 'Carregando' : 'Indisponível')
                  : null,
              style: TextStyle(
                color: financeiro ? _verde : _texto,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              nome,
              style: const TextStyle(
                color: _texto,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(detalhe, style: const TextStyle(color: _suave, fontSize: 12)),
            if (falha)
              TextButton(
                onPressed: _recarregar,
                child: const Text('Recarregar clientes'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _atalho(IconData icone, String rotulo, Widget Function(String) abrir) {
    return _cartao(
      InkWell(
        onTap: () => _abrirRelatorio(abrir),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _icone(icone),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rotulo,
                  style: const TextStyle(
                    color: _texto,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: _marca),
            ],
          ),
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
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('Relatórios'),
                selected: true,
                selectedColor: _marca,
                selectedTileColor: _rosaClaro,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => Navigator.of(context).pop(),
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

class _ResumoVendas {
  const _ResumoVendas(this.quantidade, this.totalPago);

  factory _ResumoVendas.daConsulta(QuerySnapshot<Map<String, dynamic>> dados) {
    var total = 0.0;
    for (final documento in dados.docs) {
      final valor = documento.data()['totalPago'];
      if (valor is num && valor.isFinite) total += valor.toDouble();
    }
    return _ResumoVendas(dados.size, total);
  }

  final int quantidade;
  final double totalPago;
}

Widget _grade(List<Widget> filhos, {required double larguraMinima}) {
  return LayoutBuilder(
    builder: (context, limites) {
      const espaco = 12.0;
      final colunas = ((limites.maxWidth + espaco) / (larguraMinima + espaco))
          .floor()
          .clamp(1, filhos.length)
          .toInt();
      final largura = ((limites.maxWidth - espaco * (colunas - 1)) / colunas)
          .floorToDouble();
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

Widget _cartao(Widget filho) {
  return Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _borda),
    ),
    child: filho,
  );
}

Widget _titulo(String texto) => Text(
  texto,
  style: const TextStyle(
    color: _texto,
    fontSize: 20,
    fontWeight: FontWeight.w800,
  ),
);

Widget _icone(IconData icone, {bool financeiro = false}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: financeiro ? _verdeClaro : _rosaClaro,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(9),
      child: Icon(icone, color: financeiro ? _verde : _marca, size: 21),
    ),
  );
}

String _campo(Object? valor, [String padrao = '']) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}
