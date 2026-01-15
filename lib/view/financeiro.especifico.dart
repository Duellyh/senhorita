// ignore_for_file: use_build_context_synchronously
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diacritic/diacritic.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:ui' show FontFeature;

class FinanceiroEspecificoView extends StatefulWidget {
  final String lojaSelecionada;

  const FinanceiroEspecificoView({super.key, required this.lojaSelecionada});

  @override
  State<FinanceiroEspecificoView> createState() =>
      _FinanceiroEspecificoViewState();
}

enum _DashboardModo { hoje, periodo }

class _FinanceiroEspecificoViewState extends State<FinanceiroEspecificoView> {
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';
  DateTime? dataInicio;
  DateTime? dataFim;
  double totalHoje = 0;
  double totalMes = 0;
  double valorGastoTotal = 0;
  double ticketMedio = 0;
  int totalVendas = 0;
  Map<String, double> vendasPorFuncionario = {};
  double lucro = 0;
  Map<String, double> vendasPorDia = {};
  Map<String, int> formasPagamento = {};
  Map<String, double> vendasPorCategoria = {};
  int _touchedIndexCategorias = -1;
  int _touchedIndexPagamentos = -1;
  // Cache: produtoDocId -> loja
  final Map<String, String> _lojaPorDocIdCache = {};
  List<Map<String, dynamic>> _vendasDoPeriodo = [];
  // Cache: codigoBarras -> loja
  final Map<String, String> _lojaPorCodigoCache = {};

  int totalCanceladas = 0;
  double valorCancelado = 0;
  List<Map<String, dynamic>> listaCanceladas = []; // p/ PDF/Tabela se quiser

  // NOVOS mapas p/ gráficos:
  Map<String, double> canceladasPorDia = {}; // R$ por dia (ex.: "12/09": 350.0)
  Map<String, int> canceladasPorMotivo = {}; // qtd por motivo

  int _loadToken = 0;
  bool _loading = false;

  _DashboardModo _modo = _DashboardModo.hoje;

  // KPIs fixos (não dependem do filtro visual)
  double totalMesAtual = 0; // sempre mês atual
  double totalHojeKpi = 0; // sempre hoje

  // KPI do período selecionado (apenas se tiver intervalo)
  double totalPeriodoSelecionado = 0;

  // Range que está sendo exibido nos gráficos/contadores
  DateTime _rangeInicioVisual = DateTime.now();
  DateTime _rangeFimVisual = DateTime.now();

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  bool get _temPeriodoSelecionado => (dataInicio != null && dataFim != null);

  String _labelPeriodoSelecionado() {
    if (!_temPeriodoSelecionado) return '';
    return "${DateFormat('dd/MM/yyyy').format(dataInicio!)} - ${DateFormat('dd/MM/yyyy').format(dataFim!)}";
  }

  String _normLoja(String s) => removeDiacritics(s).toLowerCase().trim();
  bool _docEhDaLojaSelecionada(Map<String, dynamic> venda) {
    final lojaDoc = (venda['lojaCaixa'] ?? '').toString();
    if (lojaDoc.trim().isEmpty) return false;
    return _normLoja(lojaDoc) == _normLoja(widget.lojaSelecionada);
  }

  bool _isCancelada(Map<String, dynamic> venda) {
    final status = (venda['status'] ?? '').toString().toLowerCase().trim();
    final flag = venda['cancelada'] == true;
    return flag || status == 'cancelada';
  }

  bool _vendaTemLojaSelecionadaNoCabecalho(Map<String, dynamic> venda) {
    final sel = widget.lojaSelecionada;

    // 1) NOVO MODELO: lista de lojas dos produtos
    final lp = venda['lojaProdutoOficial'];
    if (lp is List && lp.isNotEmpty) {
      return lp.any((x) => _normLoja(x.toString()) == _normLoja(sel));
    }

    // 2) fallback: lojaCaixa
    final caixa = (venda['lojaCaixa'] ?? '').toString().trim();
    if (caixa.isNotEmpty) return _normLoja(caixa) == _normLoja(sel);

    // 3) fallback EXTRA: sua venda está salvando em "loja"
    final loja = (venda['loja'] ?? '').toString().trim();
    if (loja.isNotEmpty) return _normLoja(loja) == _normLoja(sel);

    return false;
  }

  String _lojaKey(String s) {
    final n = removeDiacritics(s).toLowerCase().trim();

    // ajuste aqui conforme seus nomes reais
    if (n.contains('jaleco')) return 'jalecos';
    if (n.contains('modelador') || n.contains('cinta')) return 'modeladores';

    // fallback: usa o normalizado
    return n;
  }

  bool _mesmaLojaKey(String a, String b) => _lojaKey(a) == _lojaKey(b);

  void _resetDashboardState() {
    totalHoje = 0;
    totalMes = 0;
    valorGastoTotal = 0;
    ticketMedio = 0;
    totalVendas = 0;
    lucro = 0;

    vendasPorDia = {};
    formasPagamento = {};
    vendasPorFuncionario = {};
    vendasPorCategoria = {};

    totalCanceladas = 0;
    valorCancelado = 0;
    listaCanceladas = [];
    canceladasPorDia = {};
    canceladasPorMotivo = {};

    _vendasDoPeriodo = [];

    // importante: cache de loja/categoria pode “vazar” entre lojas em navegação
    _lojaPorDocIdCache.clear();
    _lojaPorCodigoCache.clear();
    _categoriaPorCodigoCache.clear();
  }

  @override
  void didUpdateWidget(covariant FinanceiroEspecificoView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.lojaSelecionada.trim() != widget.lojaSelecionada.trim()) {
      _resetDashboardState();
      carregarEstatisticas();
    }
  }

  Future<String?> _buscarLojaProdutoPorDocId(String docId) async {
    if (docId.trim().isEmpty) return null;
    final hit = _lojaPorDocIdCache[docId];
    if (hit != null) return hit;

    final doc = await FirebaseFirestore.instance
        .collection('produtos')
        .doc(docId)
        .get();
    if (!doc.exists) return null;

    final loja = (doc.data()?['loja'] ?? '').toString();
    if (loja.isNotEmpty) _lojaPorDocIdCache[docId] = loja;
    return loja.isEmpty ? null : loja;
  }

  Future<String?> _buscarLojaProdutoPorCodigo(String codigoBarras) async {
    final cod = codigoBarras.trim();
    if (cod.isEmpty) return null;

    final hit = _lojaPorCodigoCache[cod];
    if (hit != null) return hit;

    final qs = await FirebaseFirestore.instance
        .collection('produtos')
        .where('codigoBarras', isEqualTo: cod)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return null;

    final loja = (qs.docs.first.data()['loja'] ?? '').toString();
    if (loja.isNotEmpty) _lojaPorCodigoCache[cod] = loja;
    return loja.isEmpty ? null : loja;
  }

  // Decide qual loja é do item (prioriza loja já gravada no item)
  Future<String?> _lojaDoItem(Map item) async {
    // ✅ 1) loja do produto já salva no item (SEU realizarVenda grava como lojaProduto)
    final lojaProduto = (item['lojaProduto'] ?? '').toString().trim();
    if (lojaProduto.isNotEmpty) return lojaProduto;

    // ✅ 1.1) compatibilidade: se existir "loja" (versão antiga/alternativa)
    final lojaDireta = (item['loja'] ?? '').toString().trim();
    if (lojaDireta.isNotEmpty) return lojaDireta;

    // ✅ 2) docId
    final docId = (item['docId'] ?? '').toString().trim();
    if (docId.isNotEmpty) return _buscarLojaProdutoPorDocId(docId);

    // ✅ 3) codigo barras
    final codigo =
        (item['codigoBarras'] ?? item['codigo'] ?? item['barcode'] ?? '')
            .toString()
            .trim();
    if (codigo.isNotEmpty) return _buscarLojaProdutoPorCodigo(codigo);

    return null;
  }

  bool _mesmaLoja(String? a, String b) {
    if (a == null || a.trim().isEmpty) return false;
    return _mesmaLojaKey(a, b);
  }

  double _toDouble(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v == null) return 0.0;
    final s = v.toString().replaceAll(',', '.').trim();
    return double.tryParse(s) ?? 0.0;
  }

  Future<double> _subtotalDaLojaNaVenda(List<dynamic> itens) async {
    double subtotal = 0.0;

    for (final raw in itens) {
      if (raw is! Map) continue;
      final item = raw;

      final lojaItem = await _lojaDoItem(item);
      if (!_mesmaLoja(lojaItem, widget.lojaSelecionada)) continue;

      final preco = _toDouble(
        item['precoFinal'] ?? item['preco'] ?? item['valor'],
      );
      final qtd = (item['quantidade'] ?? 1);
      final q = (qtd is num) ? qtd.toInt() : int.tryParse(qtd.toString()) ?? 1;

      subtotal += preco * q;
    }

    return subtotal;
  }

  Future<double> _custoDaLojaNaVenda(List<dynamic> itens) async {
    double custo = 0.0;

    for (final raw in itens) {
      if (raw is! Map) continue;
      final item = raw;

      final lojaItem = await _lojaDoItem(item);
      if (!_mesmaLoja(lojaItem, widget.lojaSelecionada)) continue;

      final vReal = _toDouble(item['valorReal']);
      final qtd = (item['quantidade'] ?? 1);
      final q = (qtd is num) ? qtd.toInt() : int.tryParse(qtd.toString()) ?? 1;

      custo += vReal * q;
    }

    return custo;
  }

  // seu array de categorias já existe:
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

  // índice normalizado -> nome canônico
  late final Map<String, String> _catIndex = {
    for (final c in categorias) _normCat(c): c,
  };

  String _normCat(String s) => removeDiacritics(s.trim().toUpperCase());

  // converte qualquer entrada para uma categoria canônica da sua lista
  String _snapCategoria(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'OUTROS';
    final key = _normCat(raw);
    return _catIndex[key] ?? 'OUTROS';
  }

  // cache para não ficar consultando o mesmo código toda hora
  final Map<String, String> _categoriaPorCodigoCache = {};

  // busca categoria do produto por codigoBarras (com cache)
  Future<String> _categoriaPorCodigo(String codigo) async {
    final cod = codigo.trim();
    if (cod.isEmpty) return 'OUTROS';
    final hit = _categoriaPorCodigoCache[cod];
    if (hit != null) return hit;

    final qs = await FirebaseFirestore.instance
        .collection('produtos')
        .where('codigoBarras', isEqualTo: cod)
        .limit(1)
        .get();

    String cat = 'OUTROS';
    if (qs.docs.isNotEmpty) {
      final data = qs.docs.first.data();
      cat = _snapCategoria(data['categoria']?.toString());
    }
    _categoriaPorCodigoCache[cod] = cat;
    return cat;
  }

  @override
  void initState() {
    super.initState();
    _modo = _DashboardModo.hoje;
    final now = DateTime.now();
    _rangeInicioVisual = _startOfDay(now);
    _rangeFimVisual = _endOfDay(now);

    carregarEstatisticas();
    buscarTipoUsuario();
  }

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

  Future<void> _exportarPDF() async {
    // helper local: detecta canceladas com segurança
    bool _isCancelada(Map<String, dynamic> venda) {
      final status = (venda['status'] ?? '').toString().toLowerCase().trim();
      final flag = venda['cancelada'] == true;
      return flag || status == 'cancelada';
    }

    String _fmtData(DateTime? dt) =>
        dt == null ? '-' : DateFormat('dd/MM/yyyy').format(dt);

    // ===================== moeda BR ============================
    final NumberFormat _brl = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 2,
    );

    String fmtBRL(num? v) => _brl.format((v ?? 0).toDouble());

    // ===================== helpers forma de pagamento ====================
    String _normalizarForma(String f) {
      final s = f.toLowerCase().trim();
      if (s.contains('pix')) return 'Pix';
      if (s.contains('dinheiro')) return 'Dinheiro';
      if (s.contains('débito') || s.contains('debito')) return 'Débito';
      if (s.contains('crédito') || s.contains('credito')) return 'Crédito';
      if (s.contains('cartao') || s.contains('cartão')) {
        if (s.contains('debito') || s.contains('débito')) return 'Débito';
        if (s.contains('credito') || s.contains('crédito')) return 'Crédito';
        return 'Crédito';
      }
      return f.isEmpty ? 'Outros' : f[0].toUpperCase() + f.substring(1);
    }

    void _addForma(Map<String, double> acc, String forma, double valor) {
      if (valor <= 0) return;
      final key = _normalizarForma(forma);
      acc[key] = (acc[key] ?? 0) + valor;
    }

    double _toDouble(dynamic v) {
      if (v is int) return v.toDouble();
      if (v is double) return v;
      if (v == null) return 0.0;
      final s = v.toString().replaceAll(',', '.').trim();
      return double.tryParse(s) ?? 0.0;
    }

    // ====== IMPORTANTE: filtra a venda pela loja olhando os ITENS ======
    // Requer que no seu State existam (conforme ajuste anterior):
    //   Future<double> _subtotalDaLojaNaVenda(List<dynamic> itens)
    // e que widget.lojaSelecionada esteja definido no FinanceiroView.
    // ===================================================================

    final agora = DateTime.now();
    final inicioFiltro = dataInicio ?? DateTime(agora.year, agora.month, 1);
    final fimFiltro = (dataFim ?? DateTime.now()).add(
      const Duration(hours: 23, minutes: 59, seconds: 59),
    );

    final snapshot = await FirebaseFirestore.instance
        .collection('vendas')
        .where('dataVenda', isGreaterThanOrEqualTo: inicioFiltro)
        .where('dataVenda', isLessThanOrEqualTo: fimFiltro)
        .get();

    print(
      '🔍 Vendas encontradas para o PDF (período): ${snapshot.docs.length}',
    );

    // Separa ativas/canceladas, MAS só se tiver item da loja selecionada
    final vendasAtivas = <Map<String, dynamic>>[];
    final canceladas = <Map<String, dynamic>>[];

    for (final d in snapshot.docs) {
      final m = d.data();
      final itens = (m['itens'] as List?) ?? const [];
      if (itens.isEmpty) continue;

      final subtotalLoja = await _subtotalDaLojaNaVenda(itens);
      if (subtotalLoja <= 0) continue; // não tem item da loja

      // guarda subtotal já calculado (evita recalcular várias vezes)
      m['_subtotalLoja'] = subtotalLoja;

      if (_isCancelada(m)) {
        canceladas.add(m);
      } else {
        vendasAtivas.add(m);
      }
    }

    print(
      '🏷️ Vendas consideradas para PDF (loja=${widget.lojaSelecionada}): '
      'ativas=${vendasAtivas.length} canceladas=${canceladas.length}',
    );

    // ===================== somatório por forma (valor) =========================
    // Observação: como a venda pode ser "mista", aqui atribuímos o subtotal da loja
    // às formas de pagamento da venda (se houver mais de uma forma, distribui proporcionalmente
    // pelo valor informado; se não houver valor por forma, divide igualmente).
    final Map<String, double> totalPorForma = {};

    for (final data in vendasAtivas) {
      final subtotalLoja = _toDouble(data['_subtotalLoja']);
      if (subtotalLoja <= 0) continue;

      final pagamentos =
          (data['pagamentos'] as List?)?.whereType<Map>() ?? const [];

      if (pagamentos.isNotEmpty) {
        // tenta usar valores reais por forma (proporcional ao subtotal da loja)
        final valores = <Map<String, dynamic>>[];
        double somaPag = 0.0;

        for (final p in pagamentos) {
          final forma = (p['forma'] ?? p['tipo'] ?? '').toString();
          final v = _toDouble(p['valor'] ?? p['quantia'] ?? 0);
          if (forma.trim().isEmpty) continue;
          valores.add({'forma': forma, 'valor': v});
          somaPag += v;
        }

        if (valores.isEmpty) continue;

        if (somaPag > 0) {
          // distribui proporcionalmente
          for (final it in valores) {
            final forma = it['forma'].toString();
            final v = _toDouble(it['valor']);
            final parte = (v / somaPag) * subtotalLoja;
            _addForma(totalPorForma, forma, parte);
          }
        } else {
          // sem valores -> divide igualmente
          final parte = subtotalLoja / valores.length;
          for (final it in valores) {
            _addForma(totalPorForma, it['forma'].toString(), parte);
          }
        }
        continue;
      }

      // Fallback (se não houver lista de pagamentos)
      final unicaForma = (data['formaPagamento'] ?? '').toString();
      if (unicaForma.isNotEmpty) {
        _addForma(totalPorForma, unicaForma, subtotalLoja);
      }
    }
    // ==========================================================================

    // Monta linhas da tabela principal (somente ativas da loja)
    final linhasAtivas = vendasAtivas.map((data) {
      final valor = _toDouble(
        data['_subtotalLoja'],
      ); // <-- usa subtotal da loja

      final ts = data['dataVenda'];
      final DateTime dataVenda = ts is Timestamp
          ? ts.toDate()
          : DateTime.tryParse(ts?.toString() ?? '') ?? agora;

      final formas =
          (data['formasPagamento'] as List?)?.join(', ') ??
          (data['pagamentos'] is List
              ? ((data['pagamentos'] as List)
                    .whereType<Map>()
                    .map((p) => (p['forma'] ?? p['tipo'] ?? '').toString())
                    .where((s) => s.trim().isNotEmpty)
                    .join(', '))
              : '') ??
          '-';

      final funcionario = data.containsKey('funcionario')
          ? (data['funcionario'] ?? '-')
          : '-';

      return [
        DateFormat('dd/MM/yyyy').format(dataVenda),
        fmtBRL(valor),
        (formas.toString().trim().isEmpty) ? '-' : formas.toString(),
        funcionario.toString(),
      ];
    }).toList();

    // Monta linhas da seção de canceladas (somente canceladas da loja)
    double valorCanceladoLocal = 0.0;
    final linhasCanceladas = canceladas.map((data) {
      final valor = _toDouble(data['_subtotalLoja']); // <-- subtotal da loja
      valorCanceladoLocal += valor;

      final ts = data['dataVenda'];
      final DateTime? dataVenda = ts is Timestamp
          ? ts.toDate()
          : DateTime.tryParse(ts?.toString() ?? '');

      final funcionario = data['funcionario'] ?? '-';
      final cliente = (data['cliente']?['nome']) ?? '-';
      final motivo = (data['motivoCancelamento'] ?? '').toString().trim();

      return [
        _fmtData(dataVenda),
        fmtBRL(valor),
        funcionario.toString(),
        cliente.toString(),
        motivo.isEmpty ? '-' : motivo,
      ];
    }).toList();

    // Totais do PDF (recalculados pela loja, para ficar 100% coerente)
    final totalMesLoja = vendasAtivas.fold<double>(
      0.0,
      (s, v) => s + _toDouble(v['_subtotalLoja']),
    );

    double totalHojeLoja = 0.0;
    for (final v in vendasAtivas) {
      final ts = v['dataVenda'];
      final dt = ts is Timestamp
          ? ts.toDate()
          : DateTime.tryParse(ts?.toString() ?? '');
      if (dt != null && _mesmoDia(dt, agora)) {
        totalHojeLoja += _toDouble(v['_subtotalLoja']);
      }
    }

    // Observação: custo/lucro do PDF usarão os valores já calculados na tela
    // (carregarEstatisticas). Se quiser recalcular custo/lucro no PDF por loja,
    // dá para fazer, mas aqui mantive alinhado com seus campos atuais.
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Text(
              '📊 Relatório Financeiro',
              style: pw.TextStyle(fontSize: 24),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Loja: ${widget.lojaSelecionada}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),

            pw.Text(
              'Período: ${DateFormat('dd/MM/yyyy').format(inicioFiltro)} - ${DateFormat('dd/MM/yyyy').format(fimFiltro)}',
            ),
            pw.SizedBox(height: 8),

            pw.Text('Total de Vendas (Loja): ${vendasAtivas.length}'),
            pw.Text(
              'Total de Vendas no Período (Loja): ${fmtBRL(totalMesLoja)}',
            ),
            pw.Text('Total de Hoje (Loja): ${fmtBRL(totalHojeLoja)}'),
            pw.Text('Valor Gasto Total: ${fmtBRL(valorGastoTotal)}'),
            pw.Text('Lucro: ${fmtBRL(lucro)}'),
            pw.SizedBox(height: 12),

            if (totalPorForma.isNotEmpty) ...[
              pw.Text(
                'Totais por Forma de Pagamento:',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),

              ...[
                'Pix',
                'Dinheiro',
                'Débito',
                'Crédito',
                ...totalPorForma.keys
                    .where(
                      (k) =>
                          !['Pix', 'Dinheiro', 'Débito', 'Crédito'].contains(k),
                    )
                    .toList(),
              ].where((k) => (totalPorForma[k] ?? 0) > 0).map((k) {
                final v = totalPorForma[k]!;
                return pw.Text(
                  'Total de vendas no ${k.toLowerCase()}: ${fmtBRL(v)}',
                );
              }),
            ],

            pw.SizedBox(height: 12),
            pw.Divider(),

            pw.Text(
              '🧾 Detalhes das Vendas (Loja)',
              style: pw.TextStyle(fontSize: 18),
            ),
            pw.SizedBox(height: 8),

            pw.Table.fromTextArray(
              headers: [
                'Data',
                'Valor (Loja)',
                'Formas de Pagamento',
                'Funcionário',
              ],
              data: linhasAtivas,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),

            pw.SizedBox(height: 16),

            pw.Text(
              '💳 Formas de Pagamento (Qtd na tela)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Forma', 'Quantidade'],
              data: formasPagamento.entries
                  .map((e) => [e.key, e.value.toString()])
                  .toList(),
            ),

            pw.SizedBox(height: 16),

            pw.Text(
              '👤 Vendas por Funcionário (Tela)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Funcionário', 'Valor Total'],
              data: vendasPorFuncionario.entries
                  .map((e) => [e.key, fmtBRL(e.value)])
                  .toList(),
            ),

            pw.SizedBox(height: 16),

            pw.Text(
              '📦 Vendas por Categoria (Tela)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Categoria', 'Valor Total'],
              data: vendasPorCategoria.entries
                  .map((e) => [e.key, fmtBRL(e.value)])
                  .toList(),
            ),

            pw.SizedBox(height: 16),

            pw.Text(
              '📆 Vendas por Dia (Tela)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Dia', 'Valor'],
              data: vendasPorDia.entries
                  .map((e) => [e.key, fmtBRL(e.value)])
                  .toList(),
            ),

            pw.SizedBox(height: 16),

            if (vendasPorFuncionario.isNotEmpty)
              pw.Text(
                '🏆 Funcionário com maior venda: ${_getMelhorFuncionario()}',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

            // ========= VENDAS CANCELADAS =========
            if (canceladas.isNotEmpty) ...[
              pw.SizedBox(height: 24),
              pw.Divider(),
              pw.Text(
                '❌ Vendas Canceladas (Loja)',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Quantidade: ${canceladas.length}'),
              pw.Text('Valor Total Cancelado: ${fmtBRL(valorCanceladoLocal)}'),
              pw.SizedBox(height: 8),
              pw.Table.fromTextArray(
                headers: [
                  'Data',
                  'Valor (Loja)',
                  'Funcionário',
                  'Cliente',
                  'Motivo',
                ],
                data: linhasCanceladas,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ],
          ];
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'relatorio_vendas_${widget.lojaSelecionada}.pdf',
    );
  }

  String _getMelhorFuncionario() {
    if (vendasPorFuncionario.isEmpty) return 'Nenhum';
    final entry = vendasPorFuncionario.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );
    return '${entry.key} (R\$ ${entry.value.toStringAsFixed(2)})';
  }

  Future<void> _selecionarIntervaloDatas() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
      initialDateRange: (_temPeriodoSelecionado)
          ? DateTimeRange(start: dataInicio!, end: dataFim!)
          : null,
    );

    if (picked != null) {
      setState(() {
        dataInicio = _startOfDay(picked.start);
        dataFim = _endOfDay(picked.end);
        _modo = _DashboardModo.periodo;

        _rangeInicioVisual = dataInicio!;
        _rangeFimVisual = dataFim!;
      });

      carregarEstatisticas();
    }
  }

  void _voltarParaHoje() {
    final now = DateTime.now();
    setState(() {
      _modo = _DashboardModo.hoje;
      dataInicio = null;
      dataFim = null;
      _rangeInicioVisual = _startOfDay(now);
      _rangeFimVisual = _endOfDay(now);
    });
    carregarEstatisticas();
  }

  Future<void> carregarEstatisticas() async {
    final int token = ++_loadToken;

    String _snapCategoriaLocal(String? raw) {
      if (raw == null) return 'OUTROS';
      final s = raw.toString().trim().toUpperCase();
      for (final c in categorias) {
        if (c.trim().toUpperCase() == s) return c;
      }
      return 'OUTROS';
    }

    final lojaSelecionada = widget.lojaSelecionada.trim();
    if (lojaSelecionada.isEmpty) return;

    if (mounted) {
      setState(() {
        _loading = true;
        _resetDashboardState();
        totalMesAtual = 0;
        totalHojeKpi = 0;
        totalPeriodoSelecionado = 0;
      });
    }

    try {
      final now = DateTime.now();

      // ========= 1) RANGE FIXO DO MÊS (sempre) =========
      final mesInicio = DateTime(now.year, now.month, 1);
      final mesFim = _endOfDay(now);

      final snapshotMes = await FirebaseFirestore.instance
          .collection('vendas')
          .where('dataVenda', isGreaterThanOrEqualTo: mesInicio)
          .where('dataVenda', isLessThanOrEqualTo: mesFim)
          .orderBy('dataVenda')
          .get();

      if (!mounted || token != _loadToken) return;

      double somaMesLocal = 0;
      double somaHojeLocal = 0;

      // Varre mês só para KPIs fixos (Hoje e Mês)
      for (final doc in snapshotMes.docs) {
        if (!mounted || token != _loadToken) return;

        final dataDoc = doc.data();
        final itens = (dataDoc['itens'] as List?) ?? const [];
        if (itens.isEmpty) continue;

        if (!_vendaTemLojaSelecionadaNoCabecalho(dataDoc)) {
          continue;
        }

        final subtotalLoja = await _subtotalDaLojaNaVenda(itens);
        if (!mounted || token != _loadToken) return;
        if (subtotalLoja <= 0) continue;

        final dataVenda = (dataDoc['dataVenda'] as Timestamp?)?.toDate();
        if (dataVenda == null) continue;

        // ignora canceladas para Hoje/Mês (como você já faz)
        if (_isCancelada(dataDoc)) continue;

        somaMesLocal += subtotalLoja;
        if (_mesmoDia(dataVenda, now)) somaHojeLocal += subtotalLoja;
      }

      // ========= 2) RANGE VISUAL (gráficos/contadores) =========
      final DateTime inicioVisual;
      final DateTime fimVisual;

      if (_modo == _DashboardModo.hoje) {
        inicioVisual = _startOfDay(now);
        fimVisual = _endOfDay(now);
      } else {
        // período selecionado
        inicioVisual = dataInicio ?? _startOfDay(now);
        fimVisual = dataFim ?? _endOfDay(now);
      }

      // salva range que está na tela
      _rangeInicioVisual = inicioVisual;
      _rangeFimVisual = fimVisual;

      // Busca apenas o intervalo visual
      final snapshotVisual = await FirebaseFirestore.instance
          .collection('vendas')
          .where('dataVenda', isGreaterThanOrEqualTo: inicioVisual)
          .where('dataVenda', isLessThanOrEqualTo: fimVisual)
          .orderBy('dataVenda')
          .get();

      if (!mounted || token != _loadToken) return;

      double somaPeriodoLocal = 0;
      int vendasTotalLocal = 0;
      double gastoTotalLocal = 0;

      final Map<String, double> tempVendasPorDia = {};
      final Map<String, int> tempFormasPagamento = {};
      final Map<String, double> tempVendasPorFuncionario = {};
      final Map<String, double> tempVendasPorCategoria = {};
      final Map<String, double> tempCanceladasPorDia = {};
      final Map<String, int> tempCanceladasPorMotivo = {};

      int totalCanceladasLocal = 0;
      double valorCanceladoLocal = 0;
      final List<Map<String, dynamic>> listaCanceladasLocal = [];
      final List<Map<String, dynamic>> tempVendasDoPeriodo = [];

      for (final doc in snapshotVisual.docs) {
        if (!mounted || token != _loadToken) return;

        final dataDoc = doc.data();
        final itens = (dataDoc['itens'] as List?) ?? const [];
        if (itens.isEmpty) continue;

        if (!_vendaTemLojaSelecionadaNoCabecalho(dataDoc)) {
          continue;
        }

        final subtotalLoja = await _subtotalDaLojaNaVenda(itens);
        if (!mounted || token != _loadToken) return;
        if (subtotalLoja <= 0) continue;

        final dataVenda = (dataDoc['dataVenda'] as Timestamp?)?.toDate();
        if (dataVenda == null) continue;

        // guarda para pizza de pagamentos com rateio
        tempVendasDoPeriodo.add({...dataDoc, '_subtotalLoja': subtotalLoja});

        final diaStr = DateFormat('dd/MM').format(dataVenda);

        // CANCELADAS
        if (_isCancelada(dataDoc)) {
          totalCanceladasLocal++;
          valorCanceladoLocal += subtotalLoja;

          tempCanceladasPorDia[diaStr] =
              (tempCanceladasPorDia[diaStr] ?? 0) + subtotalLoja;

          final motivo = (dataDoc['motivoCancelamento'] ?? '')
              .toString()
              .trim();
          final motivoKey = motivo.isEmpty ? 'Sem motivo' : motivo;

          tempCanceladasPorMotivo[motivoKey] =
              (tempCanceladasPorMotivo[motivoKey] ?? 0) + 1;

          listaCanceladasLocal.add({
            'dataVenda': dataVenda,
            'totalVenda': subtotalLoja,
            'formasPagamento':
                (dataDoc['formasPagamento'] as List?) ?? const [],
            'funcionario': dataDoc['funcionario'] ?? '-',
            'cliente': dataDoc['cliente']?['nome'] ?? '-',
            'motivo': motivo,
          });
          continue;
        }

        // ATIVAS
        somaPeriodoLocal += subtotalLoja;
        vendasTotalLocal++;

        tempVendasPorDia[diaStr] =
            (tempVendasPorDia[diaStr] ?? 0) + subtotalLoja;

        final funcionario = (dataDoc['funcionario'] ?? 'Desconhecido')
            .toString();
        tempVendasPorFuncionario[funcionario] =
            (tempVendasPorFuncionario[funcionario] ?? 0) + subtotalLoja;

        final formas = (dataDoc['formasPagamento'] as List?) ?? [];
        for (final f in formas) {
          final forma = f.toString().trim();
          if (forma.isEmpty) continue;
          tempFormasPagamento[forma] = (tempFormasPagamento[forma] ?? 0) + 1;
        }

        gastoTotalLocal += await _custoDaLojaNaVenda(itens);
        if (!mounted || token != _loadToken) return;

        // Categorias (somente itens da loja)
        for (final raw in itens) {
          if (raw is! Map) continue;

          final lojaItem = (raw['lojaProduto'] ?? raw['loja'] ?? '')
              .toString()
              .trim();
          if (_normLoja(lojaItem) != _normLoja(widget.lojaSelecionada))
            continue;

          final preco = _toDouble(raw['precoFinal'] ?? raw['preco']);
          final qtd = _toInt(raw['quantidade'], def: 1);
          final totalItem = preco * qtd;

          final categoria = _snapCategoriaLocal(raw['categoria']?.toString());
          tempVendasPorCategoria[categoria] =
              (tempVendasPorCategoria[categoria] ?? 0) + totalItem;
        }
      }

      final lucroLocal = somaPeriodoLocal - gastoTotalLocal;

      if (!mounted || token != _loadToken) return;

      setState(() {
        _loading = false;

        // KPIs fixos
        totalMesAtual = somaMesLocal;
        totalHojeKpi = somaHojeLocal;

        // KPI visual
        totalPeriodoSelecionado = somaPeriodoLocal;

        // KPIs exibidos na barra (Hoje/Mês)
        totalHoje = totalHojeKpi; // mantém seu field original
        totalMes = totalMesAtual; // agora Mês é sempre mês atual

        // Contadores e gráficos seguem o RANGE VISUAL
        totalVendas = vendasTotalLocal;
        valorGastoTotal = gastoTotalLocal;
        lucro = lucroLocal;

        vendasPorDia = Map.from(tempVendasPorDia);
        formasPagamento = Map.from(tempFormasPagamento);
        vendasPorFuncionario = Map.from(tempVendasPorFuncionario);
        vendasPorCategoria = Map.from(tempVendasPorCategoria);

        totalCanceladas = totalCanceladasLocal;
        valorCancelado = valorCanceladoLocal;
        listaCanceladas = List.from(listaCanceladasLocal);

        canceladasPorDia = Map.from(tempCanceladasPorDia);
        canceladasPorMotivo = Map.from(tempCanceladasPorMotivo);

        _vendasDoPeriodo = List.from(tempVendasDoPeriodo);
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() => _loading = false);
      rethrow;
    }
  }

  bool _mesmoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
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
                'DASHBOARD FINANCEIRO',
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
                    MaterialPageRoute(
                      builder: (_) =>
                          HomeView(lojaSelecionada: widget.lojaSelecionada),
                    ),
                  );
                }),
              _menuItem(Icons.attach_money, 'Vender', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        VendasView(lojaSelecionada: widget.lojaSelecionada),
                  ),
                );
              }),
              _menuItem(Icons.checkroom, 'Produtos', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProdutosView(
                      lojaSelecionada:
                          widget.lojaSelecionada, // 👈 usa a mesma loja
                    ),
                  ),
                );
              }),

              _menuItem(Icons.add_box, 'Adicionar Produto', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdicionarProdutosView(
                      lojaSelecionada: widget.lojaSelecionada,
                    ),
                  ),
                );
              }),
              _menuItem(Icons.people, 'Clientes', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ClientesView(lojaSelecionada: widget.lojaSelecionada),
                  ),
                );
              }),
              if (tipoUsuario == 'funcionario')
                _menuItem(Icons.bar_chart, 'Vendas Realizadas', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VendasRealizadasView(
                        lojaSelecionada: widget.lojaSelecionada,
                      ),
                    ),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.show_chart, 'Relatórios', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RelatoriosView(
                        lojaSelecionada: widget.lojaSelecionada,
                      ),
                    ),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.settings, 'Configurações', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConfiguracoesView(
                        lojaSelecionada: widget.lojaSelecionada,
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: carregarEstatisticas,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],

              _buildKPIs(),
              const SizedBox(height: 20),

              // Filtros
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _selecionarIntervaloDatas,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _temPeriodoSelecionado
                          ? _labelPeriodoSelecionado()
                          : "Selecionar Datas",
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _voltarParaHoje, // <-- novo
                    icon: const Icon(Icons.today),
                    label: const Text(
                      "Hoje",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _exportarPDF,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text(
                      "Exportar PDF",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Gráfico de Barras
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "📊 Vendas por Dia (R\$)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: 260,
                    child: _BarChartVendasDia(
                      data: vendasPorDia,
                      chartHeight:
                          220, // altura só do gráfico (a legenda vem abaixo)
                      showLegend: true,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Gráfico de Pizza
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "💳 Formas de Pagamento",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildPieChartPagamentos(
                    _vendasDoPeriodo,
                    showLegend: true,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "👤 Vendas por Funcionário",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _BarChartFuncionarios(
                    data: vendasPorFuncionario,
                    maxBars: 7, // opcional: Top 7 + OUTROS
                    showLegend: true, // <- ativa a legenda
                    chartHeight:
                        260, // altura do gráfico (a legenda fica abaixo)
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "📦 Vendas por Categoria",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildPieChartCategorias(),
                ),
              ),
              // ❌ Canceladas por Dia (R$)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "❌ Canceladas por Dia (R\$)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: 260,
                    child: _BarChartCanceladas(data: canceladasPorDia),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 📝 Motivos de Cancelamento (Qtd)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "📝 Motivos de Cancelamento (Qtd)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildPieChartCanceladasMotivos(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKPIs() {
    final cards = <Widget>[
      _kpiBox(_buildKpiCard("Hoje", totalHojeKpi, Colors.green)),
      _kpiBox(_buildKpiCard("Mês", totalMesAtual, Colors.blue)),
      if (_temPeriodoSelecionado)
        _kpiBox(
          _buildKpiCard("Selecionado", totalPeriodoSelecionado, Colors.teal),
        ),
      _kpiBox(_buildKpiCard("Valor Gasto", valorGastoTotal, Colors.orange)),
      _kpiBox(
        _buildKpiCard("Lucro", lucro, const Color.fromARGB(255, 51, 143, 159)),
      ),
      _kpiBox(
        _buildKpiCard("Vendas", totalVendas, Colors.purple, isMoney: false),
      ),
      _kpiBox(
        _buildKpiCard(
          "Canceladas",
          totalCanceladas,
          Colors.red,
          isMoney: false,
        ),
      ),
    ];

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }

  Widget _kpiBox(Widget child) {
    return SizedBox(width: 190, child: child);
  }

  Widget _buildPieChartCategorias() {
    if (vendasPorCategoria.isEmpty) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    // 1) ordena e agrupa “resto” em OUTRAS
    const int maxSlices = 6; // 5 maiores + OUTRAS
    final entries = vendasPorCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final List<MapEntry<String, double>> mainSlices = entries
        .take(maxSlices - 1)
        .toList();
    final double othersTotal = entries
        .skip(maxSlices - 1)
        .fold(0.0, (sum, e) => sum + e.value);

    final List<MapEntry<String, double>> toPlot = [
      ...mainSlices,
      if (othersTotal > 0) const MapEntry('OUTRAS', 0), // placeholder
    ];
    if (othersTotal > 0) {
      toPlot[toPlot.length - 1] = MapEntry('OUTRAS', othersTotal);
    }

    final double total = toPlot.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 260,
          child: PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 2, // espaço entre fatias
              centerSpaceRadius: 52, // deixa “donut”
              pieTouchData: PieTouchData(
                touchCallback: (event, resp) {
                  setState(() {
                    _touchedIndexCategorias =
                        resp?.touchedSection?.touchedSectionIndex ?? -1;
                  });
                },
              ),
              sections: List.generate(toPlot.length, (i) {
                final e = toPlot[i];
                final pct = e.value / total;
                final bool isTouched = i == _touchedIndexCategorias;
                final bool showTitle =
                    pct >= 0.06 || isTouched; // >=6% ou tocado
                final String title = showTitle
                    ? '${e.key}\n${_brl.format(e.value)}\n${(pct * 100).toStringAsFixed(0)}%'
                    : '';

                return PieChartSectionData(
                  value: e.value,
                  color: _getColorForCategory(e.key),
                  title: title,
                  radius: isTouched ? 74 : 64, // destaque ao toque
                  titleStyle: const TextStyle(
                    fontSize: 11,
                    color: Color.fromARGB(255, 10, 10, 10),
                    fontWeight: FontWeight.bold,
                  ),
                  // empurra o texto para fora do centro (melhora legibilidade)
                  titlePositionPercentageOffset: 0.6,
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildLegendCategorias(toPlot, total),
      ],
    );
  }

  Color _getColorForCategory(String categoria) {
    const palette = [
      Color(0xFFF59E0B), // amber
      Color(0xFF3B82F6), // blue
      Color(0xFF10B981), // emerald
      Color(0xFF8B5CF6), // violet
      Color(0xFFEF4444), // red
      Color(0xFF14B8A6), // teal
      Color(0xFF6366F1), // indigo
      Color(0xFFF97316), // orange
      Color(0xFF06B6D4), // cyan
      Color(0xFFA78BFA), // purple
    ];
    // mantém estabilidade por hash
    return palette[(categoria.hashCode & 0x7fffffff) % palette.length];
  }

  final NumberFormat _brl = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _brlCompact = NumberFormat.compactCurrency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  Widget _buildKpiCard(
    String title,
    num value,
    Color color, {
    bool isMoney = true,
    bool compact = false, // use true se quiser "R$ 27,7 mil"
    bool fancy = false, // deixa símbolo e centavos menores
  }) {
    String display = isMoney
        ? (compact ? _brlCompact.format(value) : _brl.format(value))
        : value.toInt().toString();

    // NBSP -> espaço normal (evita quebra estranha em web)
    display = display.replaceAll('\u00A0', ' ');

    final baseStyle = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      fontFeatures: [FontFeature.tabularFigures()], // dígitos alinhados
    );

    Widget valueWidget;
    if (isMoney && fancy && !compact) {
      // Deixa "R$" e centavos menores
      // Ex.: "R$ 27.759,50" -> "R$ " | "27.759" | ",50"
      final parts = display.split(',');
      final left = parts[0]; // "R$ 27.759"
      final cents = parts.length > 1 ? ',${parts[1]}' : '';

      valueWidget = RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: left.startsWith('R') ? 'R\$ ' : '',
              style: baseStyle.copyWith(fontSize: 12, color: Colors.black),
            ),
            TextSpan(
              text: left.replaceFirst('R ', ''),
              style: baseStyle.copyWith(fontSize: 18, color: Colors.black),
            ),
            if (cents.isNotEmpty)
              TextSpan(
                text: cents,
                style: baseStyle.copyWith(fontSize: 12, color: Colors.black87),
              ),
          ],
        ),
      );
    } else {
      valueWidget = Text(display, style: baseStyle);
    }

    return Expanded(
      child: Card(
        color: const Color(0xFFFFF4F4), // leve rosado; ajuste por KPI
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 8),
              valueWidget,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPieChartPagamentos(
    List<Map<String, dynamic>> vendasDoPeriodo, {
    bool showLegend = true,
  }) {
    // monta mapa: forma -> R$
    final formasPagamento = _somarPorForma(vendasDoPeriodo);

    if (formasPagamento.isEmpty) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    const int maxSlices = 6; // 5 maiores + "Outras"
    final entries = formasPagamento.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final main = entries.take(maxSlices - 1).toList();
    final others = entries
        .skip(maxSlices - 1)
        .fold<double>(0.0, (s, e) => s + e.value);

    final toPlot = <MapEntry<String, double>>[
      ...main,
      if (others > 0) MapEntry('Outras', others),
    ];

    final total = toPlot.fold<double>(0.0, (s, e) => s + e.value);
    if (total <= 0) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              pieTouchData: PieTouchData(
                touchCallback: (event, resp) {
                  setState(() {
                    _touchedIndexPagamentos =
                        resp?.touchedSection?.touchedSectionIndex ?? -1;
                  });
                },
              ),
              sections: List.generate(toPlot.length, (i) {
                final e = toPlot[i];
                final pct = e.value / total;
                final isTouched = i == _touchedIndexPagamentos;
                final showTitle = pct >= 0.06 || isTouched;

                final title = showTitle
                    ? '${e.key}\n${_brl2.format(e.value)}\n(${(pct * 100).toStringAsFixed(0)}%)'
                    : '';

                return PieChartSectionData(
                  value: e.value,
                  color: _getColorForPayment(e.key),
                  title: title,
                  radius: isTouched ? 72 : 62,
                  titleStyle: const TextStyle(
                    fontSize: 11,
                    color: Color.fromARGB(255, 7, 7, 7),
                    fontWeight: FontWeight.bold,
                  ),
                  titlePositionPercentageOffset: 0.6,
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (showLegend) _buildLegendPagamentos(toPlot, total),
      ],
    );
  }

  Widget _buildLegendPagamentos(
    List<MapEntry<String, double>> data,
    double total,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: data.map((e) {
        final pct = total == 0 ? 0 : (e.value / total) * 100;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getColorForPayment(e.key),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${e.key}: ${_brl2.format(e.value)} (${pct.toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      }).toList(),
    );
  }

  Color _getColorForPayment(String forma) {
    final f = forma.toLowerCase().trim();
    if (f == 'pix') return Colors.green;
    if (f == 'dinheiro') return Colors.orange;
    if (f == 'crédito' || f == 'credito') return Colors.blue;
    if (f == 'débito' || f == 'debito') return Colors.purple;
    return Colors.grey;
  }

  final NumberFormat _brl2 = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 2,
  );

  Widget _buildPieChartCanceladasMotivos() {
    if (canceladasPorMotivo.isEmpty) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    return SizedBox(
      height: 220,
      child: PieChart(
        PieChartData(
          sections: canceladasPorMotivo.entries.map((e) {
            // Reaproveita sua paleta:
            final color = _getColorForCategory(e.key);
            return PieChartSectionData(
              value: e.value.toDouble(),
              color: color,
              title: '${e.key}\n(${e.value})',
              radius: 60,
              titleStyle: const TextStyle(fontSize: 11, color: Colors.white),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLegendCategorias(
    List<MapEntry<String, double>> data,
    double total,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: data.map((e) {
        final pct = (e.value / total) * 100;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getColorForCategory(e.key),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${e.key}: ${_brl.format(e.value)} (${pct.toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      }).toList(),
    );
  }

  double _parseValorBr(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();

    final s = v.toString().trim();
    if (s.isEmpty) return 0.0;

    final cleaned = s.replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (cleaned.contains(',') && cleaned.contains('.')) {
      final semMilhar = cleaned.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(semMilhar) ?? 0.0;
    }
    if (cleaned.contains(',')) {
      return double.tryParse(cleaned.replaceAll(',', '.')) ?? 0.0;
    }
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _padronizarForma(dynamic forma) {
    final f = removeDiacritics((forma ?? '').toString().toLowerCase().trim());
    if (f.contains('pix')) return 'Pix';
    if (f.contains('dinheiro')) return 'Dinheiro';
    if (f.contains('credito') || f.contains('crédito')) return 'Crédito';
    if (f.contains('debito') || f.contains('débito')) return 'Débito';
    if (f.isEmpty) return 'Outros';
    return f[0].toUpperCase() + f.substring(1);
  }

  Map<String, double> _somarPorForma(List<Map<String, dynamic>> vendas) {
    final Map<String, double> out = {};

    String fixForma(String raw) {
      final s = removeDiacritics(raw.trim().toLowerCase());
      if (s.contains('pix')) return 'Pix';
      if (s.contains('dinheiro') || s.contains('cash')) return 'Dinheiro';
      if (s.contains('debito')) return 'Débito';
      if (s.contains('credito') || s.contains('crédito')) return 'Crédito';
      return raw.trim().isEmpty ? 'Outros' : raw.trim();
    }

    for (final v in vendas) {
      final subtotalLoja = _toDouble(v['_subtotalLoja']); // vem do passo 1
      final totalVenda = _toDouble(v['totalVenda']);

      // rateio: se a venda total é 100 e subtotalLoja é 40 => loja paga 40% de cada pagamento
      final double rate = (totalVenda > 0)
          ? (subtotalLoja / totalVenda).clamp(0.0, 1.0)
          : 1.0;

      final pagamentos = (v['pagamentos'] as List?) ?? const [];

      if (pagamentos.isNotEmpty) {
        for (final p in pagamentos) {
          if (p is! Map) continue;

          final forma = fixForma((p['forma'] ?? '').toString());
          final valor = _toDouble(p['valor']);

          if (valor <= 0) continue;
          out[forma] = (out[forma] ?? 0) + (valor * rate);
        }
      } else {
        // fallback se sua venda antiga não tiver "pagamentos"
        final formas = (v['formasPagamento'] as List?) ?? const [];
        if (formas.isEmpty) continue;

        final double base = subtotalLoja > 0 ? subtotalLoja : totalVenda;
        final double porForma = base / formas.length;

        for (final f in formas) {
          final forma = fixForma((f ?? '').toString());
          out[forma] = (out[forma] ?? 0) + porForma;
        }
      }
    }

    return out;
  }

  int _toInt(dynamic v, {int def = 0}) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.toInt();

    final s = v.toString().trim();
    if (s.isEmpty) return def;

    return int.tryParse(s) ?? def;
  }
}

class _BarChartCanceladas extends StatelessWidget {
  final Map<String, double> data;
  const _BarChartCanceladas({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('Sem dados para mostrar'));
    }

    final dias = data.keys.toList();
    final valores = data.values.toList();
    final maxValor = valores.reduce((a, b) => a > b ? a : b);
    final maxY = (maxValor * 1.2).ceilToDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxY,
        minY: 0,
        barGroups: List.generate(dias.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: valores[i],
                color: Colors.redAccent,
                width: 12,
                borderRadius: BorderRadius.circular(6),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: Colors.grey[200]!,
                ),
              ),
            ],
          );
        }),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 5,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.grey[300]!, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= dias.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(dias[i], style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: maxY / 5,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'R\$ ${value.toInt()}',
                    style: const TextStyle(fontSize: 10),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _BarChartVendasDia extends StatefulWidget {
  final Map<String, double> data; // chave 'dd/MM' -> valor total R$
  final double chartHeight;
  final bool showLegend;

  const _BarChartVendasDia({
    Key? key,
    required this.data,
    this.chartHeight = 260,
    this.showLegend = true,
  }) : super(key: key);

  @override
  State<_BarChartVendasDia> createState() => _BarChartVendasDiaState();
}

class _BarChartVendasDiaState extends State<_BarChartVendasDia> {
  int _touchedIndex = -1;

  // tenta ordenar 'dd/MM'
  List<MapEntry<String, double>> _sortedEntries(Map<String, double> m) {
    final list = m.entries.toList();
    int _ordKey(String k) {
      final parts = k.split('/');
      if (parts.length == 2) {
        final d = int.tryParse(parts[0]) ?? 0;
        final mo = int.tryParse(parts[1]) ?? 0;
        return mo * 31 + d;
      }
      return 0;
    }

    list.sort((a, b) => _ordKey(a.key).compareTo(_ordKey(b.key)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return const Center(child: Text('Sem dados para mostrar'));
    }

    final entries = _sortedEntries(widget.data);
    final dias = entries.map((e) => e.key).toList();
    final valores = entries.map((e) => e.value).toList();

    final total = valores.fold(0.0, (s, v) => s + v);
    final maxValor = valores.reduce((a, b) => a > b ? a : b);
    final maxY = (maxValor * 1.2).ceilToDouble();
    final media = total / valores.length;
    final double tick = math.max(maxY / 5, 1.0);

    // índice do “melhor dia”
    int bestIdx = 0;
    for (int i = 1; i < valores.length; i++) {
      if (valores[i] > valores[bestIdx]) bestIdx = i;
    }

    // espaçar rótulos do eixo X
    final step = (dias.length / 10).ceil().clamp(1, 9999);

    const barColor = Color.fromARGB(255, 39, 176, 105);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.chartHeight,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceBetween,
              maxY: maxY,
              minY: 0,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  // tooltipBgColor / tooltipBackgroundColor variam por versão do fl_chart
                  // Se sua versão suportar, descomente UMA:
                  // tooltipBgColor: Colors.black87,
                  // tooltipBackgroundColor: Colors.black87,
                  tooltipPadding: const EdgeInsets.all(8),
                  tooltipMargin: 8,
                  getTooltipItem: (group, gi, rod, ri) {
                    final i = group.x.toInt();
                    final valor = rod.toY;
                    final pct = total == 0 ? 0 : (valor / total * 100);
                    return BarTooltipItem(
                      '${dias[i]}\n${_brl.format(valor)}  • ${pct.toStringAsFixed(1)}%',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
                touchCallback: (event, response) {
                  setState(
                    () => _touchedIndex =
                        response?.spot?.touchedBarGroupIndex ?? -1,
                  );
                },
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: media,
                    color: Colors.grey.shade400,
                    strokeWidth: 1,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      alignment: Alignment.centerRight,
                      show: true,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                      labelResolver: (_) =>
                          'média ${_brlCompact.format(media)}',
                    ),
                  ),
                ],
              ),
              barGroups: List.generate(dias.length, (i) {
                final v = valores[i];
                final isTouched = i == _touchedIndex;
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: v,
                      color: barColor,
                      width: isTouched ? 16 : 12,
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxY,
                        color: Colors.grey[200]!,
                      ),
                    ),
                  ],
                  showingTooltipIndicators: isTouched ? const [0] : const [],
                );
              }),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= dias.length)
                        return const SizedBox.shrink();
                      if (i % step != 0 && i != dias.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          dias[i],
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    interval: tick,
                    getTitlesWidget: (value, meta) {
                      final s = _brlCompact.format(value);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          s,
                          style: const TextStyle(fontSize: 10),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: tick,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: Colors.grey[300]!, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),

        // ====== LEGENDA / RESUMO ======
        if (widget.showLegend) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _legendDot(text: 'Total: ${_brl.format(total)}', color: barColor),
              _legendDot(
                text: 'Média/dia: ${_brl.format(media)}',
                color: Colors.grey.shade600,
              ),
              _legendDot(
                text:
                    'Melhor dia: ${dias[bestIdx]} (${_brl.format(valores[bestIdx])})',
                color: Colors.amber.shade600,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _legendDot({required String text, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

final NumberFormat _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final NumberFormat _brlCompact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: r'R$',
);

class _BarChartFuncionarios extends StatefulWidget {
  final Map<String, double> data;
  final int maxBars;
  final bool showLegend;
  final double chartHeight;

  const _BarChartFuncionarios({
    Key? key,
    required this.data,
    this.maxBars = 7,
    this.showLegend = false,
    this.chartHeight = 260,
  }) : super(key: key);

  @override
  State<_BarChartFuncionarios> createState() => _BarChartFuncionariosState();
}

class _BarChartFuncionariosState extends State<_BarChartFuncionarios> {
  int _touchedIndex = -1;

  Color _barColorFor(int i, String label) {
    if (i == 0) return const Color(0xFFF59E0B); // “ouro” pro top 1
    const palette = [
      Color(0xFF3B82F6), // blue
      Color(0xFF10B981), // emerald
      Color(0xFF8B5CF6), // violet
      Color(0xFFEF4444), // red
      Color(0xFF14B8A6), // teal
      Color(0xFF6366F1), // indigo
      Color(0xFFF97316), // orange
      Color(0xFF06B6D4), // cyan
    ];
    return palette[(label.hashCode & 0x7fffffff) % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return const Center(child: Text('Sem dados para mostrar'));
    }

    // Ordena e aplica Top N + OUTROS
    final entries = widget.data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final bars = <MapEntry<String, double>>[
      ...entries.take(widget.maxBars),
      if (entries.length > widget.maxBars)
        MapEntry(
          'OUTROS',
          entries.skip(widget.maxBars).fold(0.0, (s, e) => s + e.value),
        ),
    ];

    final labels = bars.map((e) => e.key).toList();
    final values = bars.map((e) => e.value).toList();
    final total = values.fold(0.0, (s, v) => s + v);
    final maxValor = values.reduce((a, b) => a > b ? a : b);
    final maxY = (maxValor * 1.2).ceilToDouble();
    final media = total / values.length;
    final double tick = math.max(maxY / 5, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.chartHeight,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              minY: 0,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  // tooltipBgColor / tooltipBackgroundColor variam por versão.
                  // Se sua versão suportar, descomente UMA:
                  // tooltipBgColor: Colors.black87,
                  // tooltipBackgroundColor: Colors.black87,
                  tooltipPadding: const EdgeInsets.all(8),
                  tooltipMargin: 8,
                  getTooltipItem: (group, gi, rod, ri) {
                    final i = group.x.toInt();
                    final nome = labels[i];
                    final valor = rod.toY;
                    final pct = total == 0 ? 0 : (valor / total * 100);
                    return BarTooltipItem(
                      '$nome\n${_brl.format(valor)}  • ${pct.toStringAsFixed(1)}%',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
                touchCallback: (event, response) {
                  setState(
                    () => _touchedIndex =
                        response?.spot?.touchedBarGroupIndex ?? -1,
                  );
                },
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: media,
                    color: Colors.grey.shade400,
                    strokeWidth: 1,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      alignment: Alignment.centerRight,
                      show: true,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                      labelResolver: (_) =>
                          'média ${_brlCompact.format(media)}',
                    ),
                  ),
                ],
              ),
              barGroups: List.generate(labels.length, (i) {
                final v = values[i];
                final isTouched = i == _touchedIndex;
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: v,
                      color: _barColorFor(i, labels[i]),
                      width: 18,
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxY,
                        color: Colors.grey[200]!,
                      ),
                    ),
                  ],
                  showingTooltipIndicators: isTouched ? const [0] : const [],
                );
              }),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= labels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 72),
                          child: Text(
                            labels[i],
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    interval: tick,
                    getTitlesWidget: (value, meta) {
                      final s = _brlCompact.format(value);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          s,
                          style: const TextStyle(fontSize: 10),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: tick,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: Colors.grey[300]!, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),

        // ====== LEGENDA ======
        if (widget.showLegend) ...[
          const SizedBox(height: 8),
          _buildLegend(labels, values, total),
        ],
      ],
    );
  }

  Widget _buildLegend(List<String> labels, List<double> values, double total) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: List.generate(labels.length, (i) {
        final nome = labels[i];
        final valor = values[i];
        final pct = total == 0 ? 0 : (valor / total) * 100;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _barColorFor(i, nome),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$nome: ${_brl.format(valor)} (${pct.toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      }),
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
