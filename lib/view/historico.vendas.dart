import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'adicionar.produtos.view.dart';
import 'clientes.view.dart';
import 'configuracoes.view.dart';
import 'home.view.dart';
import 'login.view.dart';
import 'produtos.view.dart';
import 'relatorios.view.dart';
import 'vendas.realizadas.view.dart';
import 'vendas.view.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:diacritic/diacritic.dart';

class HistoricoVendasView extends StatefulWidget {
  final String lojaSelecionada;
  const HistoricoVendasView({super.key, required this.lojaSelecionada});

  @override
  State<HistoricoVendasView> createState() => _HistoricoVendasViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);

class _HistoricoVendasViewState extends State<HistoricoVendasView> {
  static const _periodos = {
    'dia': 'Hoje',
    'semana': 'Semana atual',
    'mes': 'Mês atual',
    'semanaPassada': 'Semana passada',
    'mesPassado': 'Mês passado',
    'ano': 'Ano atual',
  };

  final _vendas = FirebaseFirestore.instance.collection('vendas');
  final _data = DateFormat('dd/MM/yyyy');
  final _dataHora = DateFormat('dd/MM/yyyy · HH:mm');
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  late DateTimeRange _intervalo;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  String _periodo = 'dia';
  String? _funcionario;
  String? _pagamento;
  final _busca = TextEditingController();
  String _buscaCliente = '';
  String tipoUsuario = '';
  String nomeUsuario = '';
  bool _cancelando = false;
  bool _saindo = false;

  User? get user => FirebaseAuth.instance.currentUser;
  bool get _ocupado => _cancelando || _saindo;

  @override
  void initState() {
    super.initState();
    _intervalo = _intervaloRapido(_periodo);
    _stream = _consultarVendas(_intervalo);
    _carregarPerfil();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregarPerfil() async {
    final uid = user?.uid;
    if (uid == null) return;
    try {
      final dados =
          (await FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .get())
              .data();
      if (!mounted) return;
      setState(() {
        tipoUsuario = _campo(dados?['tipo'], 'funcionario');
        nomeUsuario = _campo(dados?['nome']);
      });
    } catch (erro) {
      debugPrint('Histórico de vendas • perfil: $erro');
    }
  }

  DateTimeRange _intervaloRapido(String periodo) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final segunda = hoje.day - hoje.weekday + DateTime.monday;
    var inicio = hoje;
    var fim = hoje;

    switch (periodo) {
      case 'semana':
        inicio = DateTime(hoje.year, hoje.month, segunda);
        break;
      case 'mes':
        inicio = DateTime(hoje.year, hoje.month);
        break;
      case 'semanaPassada':
        inicio = DateTime(hoje.year, hoje.month, segunda - 7);
        fim = DateTime(hoje.year, hoje.month, segunda - 1);
        break;
      case 'mesPassado':
        inicio = DateTime(hoje.year, hoje.month - 1);
        fim = DateTime(hoje.year, hoje.month, 0);
        break;
      case 'ano':
        inicio = DateTime(hoje.year);
        break;
    }
    return DateTimeRange(start: inicio, end: fim);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _consultarVendas(
    DateTimeRange periodo,
  ) {
    final fim = periodo.end;
    final diaSeguinte = DateTime(fim.year, fim.month, fim.day + 1);
    return _vendas
        .where('dataVenda', isGreaterThanOrEqualTo: periodo.start)
        .where('dataVenda', isLessThan: diaSeguinte)
        .orderBy('dataVenda', descending: true)
        .snapshots();
  }

  void _aplicarPeriodo(
    String periodo, {
    DateTimeRange? personalizado,
    bool atualizar = false,
  }) {
    if (_ocupado) return;
    final intervalo =
        personalizado ??
        (periodo == 'personalizado' ? _intervalo : _intervaloRapido(periodo));
    final mudouIntervalo =
        _intervalo.start != intervalo.start || _intervalo.end != intervalo.end;
    if (periodo == _periodo && !mudouIntervalo && !atualizar) return;
    setState(() {
      _periodo = periodo;
      _intervalo = intervalo;
      if (mudouIntervalo || atualizar) _stream = _consultarVendas(intervalo);
    });
  }

  Future<void> _selecionarDatas() async {
    final hoje = _intervaloRapido('dia').end;
    final primeiroDia = DateTime(2023);
    var inicio =
        _intervalo.start.isBefore(primeiroDia) || _intervalo.start.isAfter(hoje)
        ? hoje
        : _intervalo.start;
    var fim = _intervalo.end.isAfter(hoje) || _intervalo.end.isBefore(inicio)
        ? inicio
        : _intervalo.end;
    var selecionandoInicio = true;
    final periodo = await showDialog<DateTimeRange>(
      context: context,
      builder: (dialogo) => Localizations.override(
        context: dialogo,
        locale: const Locale('pt', 'BR'),
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        child: StatefulBuilder(
          builder: (context, atualizar) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            backgroundColor: Colors.white,
            child: SizedBox(
              width: 390,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _titulo('Selecionar período'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          selected: selecionandoInicio,
                          selectedColor: _rosaClaro,
                          label: Text('Início · ${_data.format(inicio)}'),
                          onSelected: (_) =>
                              atualizar(() => selecionandoInicio = true),
                        ),
                        ChoiceChip(
                          selected: !selecionandoInicio,
                          selectedColor: _rosaClaro,
                          label: Text('Fim · ${_data.format(fim)}'),
                          onSelected: (_) =>
                              atualizar(() => selecionandoInicio = false),
                        ),
                      ],
                    ),
                    Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: _marca,
                          onPrimary: Colors.white,
                        ),
                      ),
                      child: SizedBox(
                        height:
                            346.0 +
                            (MediaQuery.textScalerOf(context).scale(56) - 56)
                                .clamp(0.0, 112.0),
                        child: CalendarDatePicker(
                          key: ValueKey(selecionandoInicio),
                          initialDate: selecionandoInicio ? inicio : fim,
                          firstDate: selecionandoInicio ? primeiroDia : inicio,
                          lastDate: hoje,
                          currentDate: hoje,
                          onDateChanged: (data) => atualizar(() {
                            if (selecionandoInicio) {
                              inicio = data;
                              if (fim.isBefore(inicio)) fim = inicio;
                            } else {
                              fim = data;
                            }
                          }),
                        ),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogo).pop(),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _marca,
                          ),
                          onPressed: () => Navigator.of(
                            dialogo,
                          ).pop(DateTimeRange(start: inicio, end: fim)),
                          child: const Text('Aplicar período'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || periodo == null) return;
    _aplicarPeriodo('personalizado', personalizado: periodo);
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
      debugPrint('Histórico de vendas • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      _aviso('Não foi possível sair.');
    }
  }

  void _aviso(String mensagem) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Iterable<String> _formasDaVenda(Map<String, dynamic> venda) sync* {
    final pagamentos = venda['pagamentos'];
    final formas = venda['formasPagamento'];
    if (pagamentos is List) {
      for (final pagamento in pagamentos.whereType<Map>()) {
        final nome = _campo(pagamento['forma'] ?? pagamento['tipo']);
        if (nome.isNotEmpty) yield nome;
      }
    }
    if (formas is List) {
      for (final forma in formas) {
        final nome = _campo(forma);
        if (nome.isNotEmpty) yield nome;
      }
    }
    final forma = _campo(venda['formaPagamento']);
    if (forma.isNotEmpty) yield forma;
  }

  String _chave(String texto) => removeDiacritics(texto.trim().toLowerCase());

  String _chavePagamento(String texto) {
    final chave = _chave(texto);
    if (chave.contains('credito')) return 'credito';
    if (chave.contains('debito')) return 'debito';
    return chave;
  }

  bool _estaCancelada(Map<String, dynamic> venda) =>
      venda['cancelada'] == true ||
      _chave(_campo(venda['status'])) == 'cancelada';

  List<Map<String, dynamic>> _itensDaVenda(Map<String, dynamic> venda) {
    final itens = venda['itens'];
    return itens is List
        ? [
            for (final item in itens.whereType<Map>())
              Map<String, dynamic>.from(item),
          ]
        : const [];
  }

  String _formasExibidas(Map<String, dynamic> venda) {
    final formas = <String, String>{};
    for (final forma in _formasDaVenda(venda)) {
      formas.putIfAbsent(_chavePagamento(forma), () => forma);
    }
    return formas.isEmpty ? 'Não informado' : formas.values.join(' / ');
  }

  String _cliente(
    Map<String, dynamic> venda, [
    String padrao = 'Cliente não informado',
  ]) {
    final cliente = venda['cliente'];
    return _campo(cliente is Map ? cliente['nome'] : cliente, padrao);
  }

  String _telefone(Map<String, dynamic> venda) {
    final cliente = venda['cliente'];
    return cliente is Map ? _campo(cliente['telefone']) : '';
  }

  DateTime? _dataVenda(Object? valor) =>
      valor is Timestamp ? valor.toDate() : DateTime.tryParse(_campo(valor));

  double _valor(Object? valor) {
    if (valor is num) return valor.isFinite ? valor.toDouble() : 0;
    final texto = _campo(valor).replaceAll(RegExp(r'[^0-9,.-]'), '');
    final numero = texto.contains(',')
        ? texto.replaceAll('.', '').replaceAll(',', '.')
        : texto;
    final convertido = double.tryParse(numero);
    return convertido != null && convertido.isFinite ? convertido : 0;
  }

  String _normKey(String s) =>
      removeDiacritics(s.trim().toUpperCase()).replaceAll(RegExp(r'\s+'), '');

  String _sanitizeField(String s) =>
      s.replaceAll(RegExp(r'[./\[\]*]'), '_').trim();

  String? _resolveCorBruto(Map<String, dynamic> item) {
    final cands = <dynamic>[item['cor'], item['color'], item['corSelecionada']];
    for (final v in cands) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  String? _resolverChaveNormalizada(Map<String, dynamic> mapa, String valor) {
    // tenta match exato
    if (mapa.containsKey(valor)) return valor;
    // case-insensitive
    final up = valor.trim().toUpperCase();
    for (final k in mapa.keys) {
      if (k.toString().trim().toUpperCase() == up) return k.toString();
    }
    // fuzzy (sem acentos/espaços)
    final alvo = _normKey(valor);
    for (final k in mapa.keys) {
      if (_normKey(k.toString()) == alvo) return k.toString();
    }
    return null;
  }

  void _mostrarDetalhesVenda(Map<String, dynamic> venda, String vendaId) {
    final itens = _itensDaVenda(venda);
    final cliente = _cliente(venda, 'Não informado');
    final telefone = _telefone(venda);
    final dataVenda = _dataVenda(venda['dataVenda']);
    final jaCancelada = _estaCancelada(venda);

    showDialog(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(jaCancelada ? 'Venda (CANCELADA)' : 'Detalhes da Venda'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cliente: $cliente'),
                if (telefone.isNotEmpty) Text('Telefone: $telefone'),
                Text(
                  'Data: ${dataVenda == null ? 'Não informada' : _dataHora.format(dataVenda)}',
                ),
                Text("Atendente: ${venda['funcionario'] ?? 'Não informado'}"),
                const SizedBox(height: 10),
                const Text(
                  'Itens:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                ...itens.map((item) {
                  final precoFinal = _valor(item['precoFinal']);
                  final quantidade = _valor(item['quantidade'] ?? 1).toInt();
                  final desconto = _valor(item['desconto']);
                  final precoPromocional = _valor(item['precoPromocional']);
                  final totalItem = precoFinal * quantidade;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['produtoNome'] ?? 'Produto'}'
                        ' ${item['tamanho']?.toString().isNotEmpty == true ? '(${item['tamanho']})' : ''}'
                        '${(item['cor'] ?? '').toString().isNotEmpty ? ' - Cor: ${item['cor']}' : ''}',
                      ),
                      Text(
                        'Quantidade: $quantidade | Unitário: R\$ ${precoFinal.toStringAsFixed(2)}'
                        '${desconto > 0 ? ' | Desconto: R\$ ${desconto.toStringAsFixed(2)}' : ''}'
                        '${precoPromocional > 0 ? ' | Promo: R\$ ${precoPromocional.toStringAsFixed(2)}' : ''}',
                      ),
                      Text('Subtotal: R\$ ${totalItem.toStringAsFixed(2)}'),
                      const Divider(),
                    ],
                  );
                }),
                const SizedBox(height: 10),
                Text('Frete: R\$ ${_valor(venda['frete']).toStringAsFixed(2)}'),

                Text(
                  'Total da Venda: R\$ ${_valor(venda['totalVenda']).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Total com Frete: R\$ ${((_valor(venda['totalVenda'])) + (_valor(venda['frete']))).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Total Pago: R\$ ${_valor(venda['totalPago']).toStringAsFixed(2)}',
                ),
                Text('Troco: R\$ ${_valor(venda['troco']).toStringAsFixed(2)}'),
                Text('Forma de Pagamento: ${_formasExibidas(venda)}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(),
            child: const Text('Voltar'),
          ),
          if (!jaCancelada)
            TextButton(
              onPressed: () {
                Navigator.of(dialogo).pop();
                _confirmarCancelamento(vendaId, venda);
              },
              child: const Text(
                'Cancelar venda',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogo).pop();
              _imprimirNotaVenda(venda);
            },
            child: const Text('Imprimir 2ª Via'),
          ),
        ],
      ),
    );
  }

  Future<void> _imprimirNotaVenda(Map<String, dynamic> venda) async {
    try {
      final pdf = pw.Document();
      final cliente = _cliente(venda, 'CONSUMIDOR');
      final telefone = _telefone(venda);
      final dataVenda = _dataVenda(venda['dataVenda']);
      final itens = _itensDaVenda(venda);
      final formasPagamento = _formasExibidas(venda);
      final frete = _valor(venda['frete']);
      final total = _valor(venda['totalVenda']);

      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(165, double.infinity), // 58mm largura
          margin: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  "SENHORITA CINTAS",
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  "COMPROVANTE DE VENDA",
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                "Atendente: ${venda['funcionario']}",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.Text("Cliente: $cliente", style: pw.TextStyle(fontSize: 8)),
              if (telefone.isNotEmpty)
                pw.Text(
                  "Telefone: $telefone",
                  style: pw.TextStyle(fontSize: 8),
                ),
              pw.Text(
                "Data: ${dataVenda == null ? 'Não informada' : _dataHora.format(dataVenda)}",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                "Itens:",
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
              pw.Divider(height: 1),
              ...itens.map((item) {
                final quantidade = _valor(item['quantidade'] ?? 1).toInt();
                final precoFinal = _valor(item['precoFinal']);
                final desconto = _valor(item['desconto']);
                final precoPromocional = _valor(item['precoPromocional']);
                final totalItem = precoFinal * quantidade;

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (desconto > 0 || precoPromocional > 0)
                      pw.Text(
                        ">> PRODUTO EM PROMOÇÃO <<",
                        style: pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.red,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    pw.Text(
                      "${item['produtoNome']} ${item['tamanho']?.toString().isNotEmpty == true ? '(${item['tamanho']})' : ''}",
                      style: pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      "Qtd: $quantidade - Unit: R\$ ${precoFinal.toStringAsFixed(2)}"
                      "${desconto > 0 ? ' | Desc: R\$ ${desconto.toStringAsFixed(2)}' : ''}"
                      "${precoPromocional > 0 ? ' | Promo: R\$ ${precoPromocional.toStringAsFixed(2)}' : ''}",
                      style: pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      "Subtotal: R\$ ${totalItem.toStringAsFixed(2)}",
                      style: pw.TextStyle(fontSize: 8),
                    ),
                    pw.Divider(height: 1),
                  ],
                );
              }),
              pw.SizedBox(height: 6),
              pw.Text(
                "Frete: R\$ ${frete.toStringAsFixed(2)}",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                "Total da Venda: R\$ ${total.toStringAsFixed(2)}",
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                "Total com Frete: R\$ ${(total + frete).toStringAsFixed(2)}",
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                "Total Pago: R\$ ${_valor(venda['totalPago']).toStringAsFixed(2)}",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                "Troco: R\$ ${_valor(venda['troco']).toStringAsFixed(2)}",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                "Forma de Pagamento: $formasPagamento",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  "Obrigada pela preferência!",
                  style: pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
        ),
      );

      await Printing.layoutPdf(onLayout: (_) => pdf.save());
    } catch (erro) {
      debugPrint('Histórico de vendas • impressão: $erro');
      _aviso('Não foi possível imprimir a segunda via.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loja = widget.lojaSelecionada.trim();
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _marca,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 76,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Histórico de vendas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
            tooltip: 'Atualizar histórico',
            onPressed: _ocupado
                ? null
                : () => _aplicarPeriodo(_periodo, atualizar: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _ocupado ? null : _sair,
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1232),
            child: _conteudo(),
          ),
        ),
      ),
    );
  }

  Widget _conteudo() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final aguardando = snapshot.connectionState == ConnectionState.waiting;
        final docs = aguardando || snapshot.hasError
            ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
            : snapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final funcionarios = <String, String>{};
        final pagamentos = <String, String>{};
        final exibidos = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final busca = _chave(_buscaCliente);
        for (final doc in docs) {
          final venda = doc.data();
          final funcionario = _campo(venda['funcionario']);
          final chaveFuncionario = _chave(funcionario);
          if (chaveFuncionario.isNotEmpty)
            funcionarios.putIfAbsent(chaveFuncionario, () => funcionario);
          var temPagamento = _pagamento == null;
          for (final forma in _formasDaVenda(venda)) {
            final chave = _chavePagamento(forma);
            pagamentos.putIfAbsent(chave, () => forma);
            if (chave == _pagamento) temPagamento = true;
          }
          if ((_funcionario == null || _funcionario == chaveFuncionario) &&
              temPagamento &&
              (busca.isEmpty || _chave(_cliente(venda, '')).contains(busca))) {
            exibidos.add(doc);
          }
        }

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              sliver: SliverToBoxAdapter(
                child: _filtros(funcionarios, pagamentos),
              ),
            ),
            if (aguardando)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: LinearProgressIndicator(color: _marca),
                ),
              )
            else if (snapshot.hasError)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _cartao(
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        children: [
                          const Text('Não foi possível carregar as vendas.'),
                          TextButton(
                            onPressed: _ocupado
                                ? null
                                : () => _aplicarPeriodo(
                                    _periodo,
                                    atualizar: true,
                                  ),
                            child: const Text('Tentar novamente'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else if (exibidos.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _cartao(
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        docs.isEmpty
                            ? 'Nenhuma venda no período selecionado.'
                            : 'Nenhuma venda encontrada com esses filtros.',
                      ),
                    ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    exibidos.length == 1
                        ? '1 venda encontrada'
                        : '${exibidos.length} vendas encontradas',
                    style: const TextStyle(color: _suave),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _cardVenda(exibidos[index]),
                    ),
                    childCount: exibidos.length,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _filtros(
    Map<String, String> funcionarios,
    Map<String, String> pagamentos,
  ) {
    final inicio = _data.format(_intervalo.start);
    final fim = _data.format(_intervalo.end);
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titulo('Período'),
            const SizedBox(height: 4),
            Text(
              '${inicio == fim ? inicio : '$inicio a $fim'} · Todas as lojas',
              style: const TextStyle(color: _suave),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final periodo in _periodos.entries)
                  ChoiceChip(
                    label: Text(periodo.value),
                    selected: _periodo == periodo.key,
                    selectedColor: _rosaClaro,
                    onSelected: _ocupado
                        ? null
                        : (selecionado) {
                            if (selecionado) _aplicarPeriodo(periodo.key);
                          },
                  ),
                ChoiceChip(
                  label: const Text('Selecionar datas'),
                  selected: _periodo == 'personalizado',
                  selectedColor: _rosaClaro,
                  onSelected: _ocupado ? null : (_) => _selecionarDatas(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, limites) {
                const espaco = 12.0;
                final largura = limites.maxWidth >= 720
                    ? (limites.maxWidth - espaco * 2) / 3
                    : limites.maxWidth;
                return Wrap(
                  spacing: espaco,
                  runSpacing: espaco,
                  children: [
                    SizedBox(
                      width: largura,
                      child: TextField(
                        controller: _busca,
                        enabled: !_ocupado,
                        decoration: _decoracao('Buscar cliente').copyWith(
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _buscaCliente.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpar busca',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(() {
                                    _busca.clear();
                                    _buscaCliente = '';
                                  }),
                                ),
                        ),
                        onChanged: (texto) =>
                            setState(() => _buscaCliente = texto),
                      ),
                    ),
                    SizedBox(
                      width: largura,
                      child: _seletorFiltro(
                        'Funcionário',
                        'Todos',
                        funcionarios,
                        _funcionario,
                        (valor) {
                          setState(() => _funcionario = valor);
                        },
                      ),
                    ),
                    SizedBox(
                      width: largura,
                      child: _seletorFiltro(
                        'Pagamento',
                        'Todos',
                        pagamentos,
                        _pagamento,
                        (valor) {
                          setState(() => _pagamento = valor);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _seletorFiltro(
    String rotulo,
    String todos,
    Map<String, String> opcoes,
    String? ativo,
    ValueChanged<String?> mudar,
  ) {
    final itens = opcoes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: ativo ?? '',
      decoration: _decoracao(rotulo),
      items: [
        DropdownMenuItem(value: '', child: Text(todos)),
        for (final item in itens)
          DropdownMenuItem(
            value: item.key,
            child: Text(item.value, overflow: TextOverflow.ellipsis),
          ),
        if (ativo != null && !opcoes.containsKey(ativo))
          DropdownMenuItem(
            value: ativo,
            child: Text(ativo, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _ocupado ? null : (valor) => mudar(valor == '' ? null : valor),
    );
  }

  Widget _cardVenda(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final venda = doc.data();
    final data = _dataVenda(venda['dataVenda']);
    final cancelada = _estaCancelada(venda);
    final funcionario = _campo(venda['funcionario']);
    final lojaCaixa = _campo(venda['lojaCaixa'], _campo(venda['loja']));
    return _cartao(
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: _rosaClaro,
          foregroundColor: _marca,
          child: Icon(Icons.receipt_long_outlined),
        ),
        title: Text(
          _moeda.format(_valor(venda['totalVenda'])),
          style: const TextStyle(color: _texto, fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_cliente(venda), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (data != null) Text(_dataHora.format(data)),
            if (funcionario.isNotEmpty) Text(funcionario),
            if (lojaCaixa.isNotEmpty)
              Text(
                'Caixa · $lojaCaixa',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (cancelada)
              Text(
                'Cancelada',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: _marca),
        onTap: _ocupado ? null : () => _mostrarDetalhesVenda(venda, doc.id),
      ),
    );
  }

  Widget _menu(String loja) => Drawer(
    backgroundColor: Colors.white,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            leading: const Icon(Icons.storefront_outlined, color: _marca),
            title: Text(nomeUsuario.isEmpty ? 'Senhorita' : nomeUsuario),
            subtitle: loja.isEmpty ? null : Text(loja),
          ),
          const Divider(color: _borda),
          if (tipoUsuario == 'admin')
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
          if (tipoUsuario == 'funcionario')
            _link(
              Icons.receipt_long_outlined,
              'Vendas realizadas',
              () => VendasRealizadasView(lojaSelecionada: loja),
            ),
          if (tipoUsuario == 'admin') ...[
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

  Widget _link(IconData icone, String rotulo, Widget Function() abrir) =>
      ListTile(
        leading: Icon(icone, color: _suave),
        title: Text(rotulo),
        onTap: _ocupado
            ? null
            : () {
                final navegador = Navigator.of(context);
                navegador.pop();
                navegador.pushReplacement<void, void>(
                  MaterialPageRoute<void>(builder: (_) => abrir()),
                );
              },
      );

  Future<void> _confirmarCancelamento(
    String vendaId,
    Map<String, dynamic> venda,
  ) async {
    if (_ocupado) return;
    var motivo = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Cancelar venda?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('O cancelamento devolve os itens ao estoque.'),
            const SizedBox(height: 12),
            TextField(
              onChanged: (texto) => motivo = texto,
              decoration: _decoracao('Motivo (opcional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Cancelar venda'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true || _ocupado) return;
    await _cancelarVenda(vendaId, venda, motivo.trim());
  }

  String? _resolveProdutoIdBruto(Map<String, dynamic> item) {
    // tenta várias formas comuns de vir o id do produto no item
    final cands = <dynamic>[
      item['docId'],
      item['produtoId'],
      item['idProduto'],
      item['id_produto'],
      item['produtoID'],
      (item['produto'] is Map ? (item['produto'] as Map)['id'] : null),
    ].where((e) => e != null).map((e) => e.toString().trim()).toList();

    for (final c in cands) {
      if (c.isNotEmpty) return c;
    }
    return null;
  }

  int _resolveQtd(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v == null) return 0;
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s) ?? 0;
  }

  String? _resolveTamanhoBruto(Map<String, dynamic> item) {
    final cands = <dynamic>[item['tamanho'], item['tam'], item['size']];
    for (final v in cands) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  Future<String?> _descobrirProdutoIdViaConsulta(
    Map<String, dynamic> item,
  ) async {
    // 1) tenta por código de barras
    final cods = <dynamic>[
      item['codigoBarras'],
      item['codigo'],
      item['barcode'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).toList();

    if (cods.isNotEmpty) {
      final cod = cods.first.toString().trim();
      final qs = await FirebaseFirestore.instance
          .collection('produtos')
          .where('codigoBarras', isEqualTo: cod)
          .limit(2)
          .get();
      if (qs.docs.length == 1) return qs.docs.single.id;
    }

    // 2) tenta por nome (+ cor/loja se disponíveis, para diminuir ambiguidades)
    final nome = (item['produtoNome'] ?? item['nome'] ?? '').toString().trim();
    if (nome.isNotEmpty) {
      var q = FirebaseFirestore.instance
          .collection('produtos')
          .where('nome', isEqualTo: nome.toUpperCase());

      final cor = (item['cor'] ?? '').toString().trim();
      final loja = _campo(item['lojaProduto'], _campo(item['loja']));

      if (cor.isNotEmpty) q = q.where('cor', isEqualTo: cor);
      if (loja.isNotEmpty) q = q.where('loja', isEqualTo: loja);

      final qs = await q.limit(2).get();
      if (qs.docs.length == 1) return qs.docs.single.id;
    }

    return null; // não encontrado
  }

  Future<void> _cancelarVenda(
    String vendaId,
    Map<String, dynamic> venda,
    String motivo,
  ) async {
    setState(() => _cancelando = true);
    final uid = user?.uid;
    final autor = nomeUsuario;
    try {
      if (_estaCancelada(venda)) {
        _aviso('Esta venda já está cancelada.');
        return;
      }

      final itens = _itensDaVenda(venda);
      if (itens.isEmpty) {
        _aviso('Venda sem itens. Nenhum estoque foi alterado.');
        return;
      }

      /// Acúmulo:
      /// { produtoId: {
      ///     'qtdTotal': int,
      ///     'porTamanho': { 'M': 2, 'G': 1 },                  // compat
      ///     'porGrade': { 'M': { 'PRETO': 1 }, 'G': {'AZUL':1} } // novo
      ///   }
      /// }
      final updatesPorProduto = <String, Map<String, dynamic>>{};
      final produtos = FirebaseFirestore.instance.collection('produtos');
      final cache = <String, DocumentSnapshot<Map<String, dynamic>>>{};

      for (final item in itens) {
        // quantidade
        final int qty = _resolveQtd(item['quantidade'] ?? item['qtd']);
        if (qty <= 0) continue;

        var produtoId = _resolveProdutoIdBruto(item);
        DocumentSnapshot<Map<String, dynamic>>? produtoSnap;
        if (produtoId != null) {
          produtoSnap = cache[produtoId] ??= await produtos
              .doc(produtoId)
              .get();
        }
        if (produtoSnap?.exists != true) {
          produtoId = await _descobrirProdutoIdViaConsulta(item);
          if (produtoId != null) {
            produtoSnap = cache[produtoId] ??= await produtos
                .doc(produtoId)
                .get();
          }
        }

        final prod = produtoSnap?.data();
        if (produtoId == null || prod == null) {
          final nome = _campo(item['produtoNome'], 'Produto sem nome');
          _aviso('Não foi possível localizar $nome no estoque.');
          return;
        }

        final tamBruto = _resolveTamanhoBruto(item);
        final corBruta = _resolveCorBruto(item);
        final tamanhosProduto = Map<String, dynamic>.from(
          prod['tamanhos'] ?? {},
        );
        final gradeProduto = Map<String, dynamic>.from(
          prod['tamanhosCores'] ?? prod['grade'] ?? {},
        );

        // resolve chaves (se não existir no produto, cria com o valor normalizado)
        String? tamKey;
        if (tamBruto != null && tamBruto.trim().isNotEmpty) {
          tamKey =
              _resolverChaveNormalizada(
                gradeProduto.isNotEmpty ? gradeProduto : tamanhosProduto,
                tamBruto,
              ) ??
              tamBruto.trim().toUpperCase();
        }

        String? corKey;
        if (corBruta != null && corBruta.trim().isNotEmpty) {
          // tenta resolver dentro do mapa de cores daquele tamanho, se existir
          if (gradeProduto.isNotEmpty &&
              tamKey != null &&
              gradeProduto[tamKey] is Map) {
            final coresDoTam = Map<String, dynamic>.from(gradeProduto[tamKey]);
            corKey =
                _resolverChaveNormalizada(coresDoTam, corBruta) ??
                corBruta.trim().toUpperCase();
          } else {
            corKey = corBruta.trim().toUpperCase();
          }
        }

        // acumula
        updatesPorProduto.putIfAbsent(
          produtoId,
          () => {
            'qtdTotal': 0,
            'porTamanho': <String, int>{},
            'porGrade': <String, Map<String, int>>{},
          },
        );

        updatesPorProduto[produtoId]!['qtdTotal'] =
            (updatesPorProduto[produtoId]!['qtdTotal'] as int) + qty;

        // se vier tamanho+cor => usa grade (novo)
        if (tamKey != null &&
            corKey != null &&
            tamKey.isNotEmpty &&
            corKey.isNotEmpty) {
          final porGrade =
              updatesPorProduto[produtoId]!['porGrade']
                  as Map<String, Map<String, int>>;
          porGrade.putIfAbsent(tamKey, () => <String, int>{});
          porGrade[tamKey]![corKey] = (porGrade[tamKey]![corKey] ?? 0) + qty;
        }
        // se vier só tamanho => mantém compat com 'tamanhos'
        else if (tamKey != null && tamKey.isNotEmpty) {
          final porTam =
              updatesPorProduto[produtoId]!['porTamanho'] as Map<String, int>;
          porTam[tamKey] = (porTam[tamKey] ?? 0) + qty;
        }
        // se não veio nada, apenas soma na quantidade total
      }

      if (updatesPorProduto.isEmpty) {
        _aviso('Nada a repor nesta venda.');
        return;
      }

      final vendaRef = _vendas.doc(vendaId);
      final cancelou = await FirebaseFirestore.instance.runTransaction<bool>((
        transacao,
      ) async {
        final atual = (await transacao.get(vendaRef)).data();
        if (atual == null || _estaCancelada(atual)) return false;

        updatesPorProduto.forEach((produtoId, payload) {
          final produtoRef = FirebaseFirestore.instance
              .collection('produtos')
              .doc(produtoId);

          final int qtdTotal = payload['qtdTotal'] as int;

          // total sempre volta
          transacao.update(produtoRef, {
            'quantidade': FieldValue.increment(qtdTotal),
          });

          // 1) compat (se você ainda usa): tamanhos.<tam> += inc
          final porTamanho = payload['porTamanho'] as Map<String, int>;
          porTamanho.forEach((tamOrig, inc) {
            final tam = _sanitizeField(tamOrig);
            transacao.set(produtoRef, {
              'tamanhos': {tam: FieldValue.increment(inc)},
            }, SetOptions(merge: true));
          });

          // 2) **NOVO OFICIAL**: tamanhosCores.<tam>.<cor> += inc
          //    (no seu código anterior a variável chamava "porGrade"; reaproveite)
          final Map<String, Map<String, int>> porTamCor =
              (payload['porGrade']
                  as Map<
                    String,
                    Map<String, int>
                  >); // <- mantém o nome antigo se já existir

          porTamCor.forEach((tamOrig, cores) {
            final tam = _sanitizeField(tamOrig);
            cores.forEach((corOrig, inc) {
              final cor = _sanitizeField(corOrig);
              transacao.set(
                produtoRef,
                {
                  'tamanhosCores': {
                    tam: {cor: FieldValue.increment(inc)},
                  },
                },
                SetOptions(merge: true), // cria os pais se não existirem
              );
            });
          });

          // (opcional) espelho em "estoque"
          final estoqueRef = FirebaseFirestore.instance
              .collection('estoque')
              .doc(produtoId);
          final estoqueMerge = <String, dynamic>{
            'idProduto': produtoId,
            'quantidade': FieldValue.increment(qtdTotal),
          };

          porTamanho.forEach((tamOrig, inc) {
            final tam = _sanitizeField(tamOrig);
            estoqueMerge['tamanhos.$tam'] = FieldValue.increment(inc);
          });
          porTamCor.forEach((tamOrig, cores) {
            final tam = _sanitizeField(tamOrig);
            cores.forEach((corOrig, inc) {
              final cor = _sanitizeField(corOrig);
              estoqueMerge['tamanhosCores.$tam.$cor'] = FieldValue.increment(
                inc,
              );
            });
          });

          transacao.set(estoqueRef, estoqueMerge, SetOptions(merge: true));
        });

        transacao.update(vendaRef, {
          'cancelada': true,
          'status': 'cancelada',
          'canceladaEm': FieldValue.serverTimestamp(),
          'canceladaPorUid': uid,
          'canceladaPorNome': autor,
          if (motivo.isNotEmpty) 'motivoCancelamento': motivo,
        });
        return true;
      });

      if (!cancelou) {
        _aviso('A venda já foi cancelada ou não está mais disponível.');
        return;
      }
      try {
        await vendaRef.collection('logs').add({
          'tipo': 'cancelamento',
          'quando': FieldValue.serverTimestamp(),
          'quemUid': uid,
          'quemNome': autor,
          'motivo': motivo,
        });
      } catch (erro) {
        debugPrint('Histórico de vendas • auditoria: $erro');
        _aviso(
          'Venda cancelada e estoque reposto. Falha ao registrar a auditoria.',
        );
        return;
      }
      _aviso('Venda cancelada e estoque restabelecido.');
    } catch (erro, pilha) {
      debugPrint('Histórico de vendas • cancelamento: $erro\n$pilha');
      _aviso('Não foi possível cancelar a venda.');
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }
}

Widget _cartao(Widget filho) => Material(
  color: Colors.white,
  clipBehavior: Clip.antiAlias,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: _borda),
  ),
  child: filho,
);

Widget _titulo(String texto) => Text(
  texto,
  style: const TextStyle(
    color: _texto,
    fontSize: 18,
    fontWeight: FontWeight.w800,
  ),
);

InputDecoration _decoracao(String rotulo) => InputDecoration(
  labelText: rotulo,
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _borda),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _marca),
  ),
);

String _campo(Object? valor, [String? s]) => valor?.toString().trim() ?? '';
