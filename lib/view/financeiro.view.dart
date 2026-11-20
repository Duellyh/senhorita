// ignore_for_file: use_build_context_synchronously
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diacritic/diacritic.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fl_chart/fl_chart.dart';
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

class FinanceiroView extends StatefulWidget {
  final String lojaSelecionada;
  const FinanceiroView({super.key, required this.lojaSelecionada});

  @override
  State<FinanceiroView> createState() => _FinanceiroViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);

enum _FiltroPeriodo {
  hoje('Hoje'),
  mesAtual('Mês atual'),
  semanaPassada('Semana passada'),
  mesPassado('Mês passado'),
  personalizado('Personalizado');

  const _FiltroPeriodo(this.rotulo);

  final String rotulo;
}

class _FinanceiroViewState extends State<FinanceiroView> {
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  String nomeUsuario = '';
  _FiltroPeriodo _filtroPeriodo = _FiltroPeriodo.mesAtual;
  DateTimeRange? _periodoPersonalizado;
  DateTimeRange? _periodoCarregado;
  int _loadToken = 0;
  bool _loading = true;
  bool _exportando = false;
  bool _saindo = false;
  bool _erroCarregamento = false;
  double totalPeriodo = 0;
  double valorGastoTotal = 0;
  int totalVendas = 0;
  Map<String, double> vendasPorFuncionario = {};
  double lucro = 0;
  Map<String, double> vendasPorDia = {};
  Map<String, int> formasPagamento = {};
  Map<String, double> vendasPorCategoria = {};
  int _touchedIndexCategorias = -1;
  int _touchedIndexPagamentos = -1;
  List<Map<String, dynamic>> _vendasDoPeriodo = [];

  int totalCanceladas = 0;
  double valorCancelado = 0;

  // NOVOS mapas p/ gráficos:
  Map<String, double> canceladasPorDia = {}; // R$ por dia (ex.: "12/09": 350.0)
  Map<String, int> canceladasPorMotivo = {}; // qtd por motivo

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _diaSeguinte(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  DateTimeRange _intervaloSelecionado(DateTime hoje) {
    switch (_filtroPeriodo) {
      case _FiltroPeriodo.hoje:
        return DateTimeRange(start: hoje, end: hoje);
      case _FiltroPeriodo.mesAtual:
        return DateTimeRange(start: DateTime(hoje.year, hoje.month), end: hoje);
      case _FiltroPeriodo.semanaPassada:
        final segundaAtual = hoje.day - (hoje.weekday - DateTime.monday);
        return DateTimeRange(
          start: DateTime(hoje.year, hoje.month, segundaAtual - 7),
          end: DateTime(hoje.year, hoje.month, segundaAtual - 1),
        );
      case _FiltroPeriodo.mesPassado:
        return DateTimeRange(
          start: DateTime(hoje.year, hoje.month - 1),
          end: DateTime(hoje.year, hoje.month, 0),
        );
      case _FiltroPeriodo.personalizado:
        return _periodoPersonalizado!;
    }
  }

  String _labelPeriodo(DateTimeRange periodo) {
    final formato = DateFormat('dd/MM/yyyy');
    final inicio = formato.format(periodo.start);
    final fim = formato.format(periodo.end);
    return inicio == fim ? inicio : '$inicio a $fim';
  }

  bool _isCancelada(Map<String, dynamic> venda) {
    final status = (venda['status'] ?? '').toString().toLowerCase().trim();
    final flag = venda['cancelada'] == true;
    return flag || status == 'cancelada';
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
    final Map<String, double> totais = {};

    for (final venda in vendas) {
      // 👉 reaproveita sua regra existente
      if (_isCancelada(venda)) continue;

      final pagamentos = venda['pagamentos'];

      // ✅ Caminho principal (correto): pagamentos = [{forma, valor}]
      if (pagamentos is List && pagamentos.isNotEmpty) {
        for (final p in pagamentos) {
          if (p is Map) {
            final forma = _padronizarForma(p['forma'] ?? p['tipo']);
            final valor = _parseValorBr(p['valor'] ?? p['quantia']);

            if (valor <= 0) continue;

            totais[forma] = (totais[forma] ?? 0) + valor;
          }
        }
        continue;
      }

      // 🔁 Fallback (casos antigos)
      final formas = venda['formasPagamento'];
      final totalPago = _parseValorBr(
        venda['totalPago'] ?? venda['totalVenda'],
      );
      if (formas is! List || formas.isEmpty) {
        final formaLegada = (venda['formaPagamento'] ?? '').toString().trim();
        if (formaLegada.isNotEmpty && totalPago > 0) {
          final forma = _padronizarForma(formaLegada);
          totais[forma] = (totais[forma] ?? 0) + totalPago;
        }
        continue;
      }

      if (totalPago > 0) {
        if (formas.length == 1) {
          final forma = _padronizarForma(formas.first);
          totais[forma] = (totais[forma] ?? 0) + totalPago;
        } else {
          // múltiplas formas sem valores → não inventa divisão
          totais['Outros'] = (totais['Outros'] ?? 0) + totalPago;
        }
      }
    }

    return totais;
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

  @override
  void initState() {
    super.initState();
    carregarEstatisticas();
    buscarTipoUsuario();
  }

  Future<void> buscarTipoUsuario() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user!.uid)
          .get();
      if (!mounted) return;
      final dados = doc.data();
      setState(() {
        tipoUsuario = (dados?['tipo'] ?? 'funcionario').toString();
        nomeUsuario = (dados?['nome'] ?? 'Usuário').toString();
      });
    }
  }

  Future<void> _exportarPDF() async {
    final periodo = _periodoCarregado;
    if (periodo == null || _loading || _exportando || _saindo) return;
    setState(() => _exportando = true);
    try {
      await _gerarPDF(periodo);
    } catch (erro) {
      debugPrint('Financeiro específico • PDF: $erro');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível exportar o PDF.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _gerarPDF(DateTimeRange periodo) async {
    String _fmtData(DateTime? dt) =>
        dt == null ? '-' : DateFormat('dd/MM/yyyy').format(dt);

    // ===================== NOVO: helper de moeda BR ============================
    final NumberFormat _brl = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 2,
    );

    String fmtBRL(num? v) {
      final valor = (v ?? 0).toDouble();
      return _brl.format(valor);
    }
    // ==========================================================================

    final vendasAtivas = _vendasDoPeriodo
        .where((venda) => !_isCancelada(venda))
        .toList();
    final canceladas = _vendasDoPeriodo.where(_isCancelada).toList();
    final totalPorForma = _somarPorForma(vendasAtivas);

    // Monta linhas da tabela principal (somente ativas)
    final linhasAtivas = vendasAtivas.map((data) {
      final valor = _parseValorBr(data['totalVenda']);
      final ts = data['dataVenda'];
      final DateTime dataVenda = ts is Timestamp
          ? ts.toDate()
          : DateTime.tryParse(ts?.toString() ?? '') ?? periodo.start;

      final formasRegistradas = data['formasPagamento'];
      final formas = formasRegistradas is List
          ? formasRegistradas.join(', ')
          : (data['formaPagamento'] ?? '-').toString();
      final funcionario = data.containsKey('funcionario')
          ? (data['funcionario'] ?? '-')
          : '-';

      return [
        DateFormat('dd/MM/yyyy').format(dataVenda),
        fmtBRL(valor),
        formas,
        funcionario,
      ];
    }).toList();

    // Monta linhas da seção de canceladas
    final linhasCanceladas = canceladas.map((data) {
      final valor = _parseValorBr(data['totalVenda']);

      final ts = data['dataVenda'];
      final DateTime? dataVenda = ts is Timestamp
          ? ts.toDate()
          : DateTime.tryParse(ts?.toString() ?? '');

      final funcionario = data['funcionario'] ?? '-';
      final cadastro = data['cliente'];
      final cliente = cadastro is Map ? (cadastro['nome'] ?? '-') : '-';
      final motivo = (data['motivoCancelamento'] ?? '').toString().trim();

      return [
        _fmtData(dataVenda),
        fmtBRL(valor),
        funcionario.toString(),
        cliente.toString(),
        motivo.isEmpty ? '-' : motivo,
      ];
    }).toList();

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Text(
              'Relatório Financeiro Geral',
              style: pw.TextStyle(fontSize: 24),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Período: ${_labelPeriodo(periodo)}'),
            pw.SizedBox(height: 8),

            pw.Text('Total de Vendas: $totalVendas'),
            pw.Text('Total de Vendas no Período: ${fmtBRL(totalPeriodo)}'),
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

              // Ordem fixa: Pix, Dinheiro, Débito, Crédito, depois outras
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
              '🧾 Detalhes das Vendas',
              style: pw.TextStyle(fontSize: 18),
            ),
            pw.SizedBox(height: 8),

            pw.Table.fromTextArray(
              headers: ['Data', 'Valor', 'Formas de Pagamento', 'Funcionário'],
              data: linhasAtivas,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),

            pw.SizedBox(height: 16),

            pw.Text(
              '💳 Formas de Pagamento',
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
              '👤 Vendas por Funcionário',
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
              '📦 Vendas por Categoria',
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
              '📆 Vendas por Dia',
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
                'Funcionário com maior venda: ${_getMelhorFuncionario()}',
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
                'Vendas Canceladas',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Quantidade: ${canceladas.length}'),
              pw.Text('Valor Total Cancelado: ${fmtBRL(valorCancelado)}'),
              pw.SizedBox(height: 8),
              pw.Table.fromTextArray(
                headers: ['Data', 'Valor', 'Funcionário', 'Cliente', 'Motivo'],
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
      filename: 'relatorio_financeiro_geral.pdf',
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
    if (_exportando || _saindo) return;
    final ultimoDia = _startOfDay(DateTime.now());
    final periodoAtual = _intervaloSelecionado(ultimoDia);
    final selecionado = await showDialog<DateTimeRange>(
      context: context,
      builder: (dialogo) => Localizations.override(
        context: dialogo,
        locale: const Locale('pt', 'BR'),
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        child: _SeletorPeriodo(
          primeiroDia: DateTime(2022),
          ultimoDia: ultimoDia,
          periodoInicial: periodoAtual.end.isAfter(ultimoDia)
              ? null
              : periodoAtual,
        ),
      ),
    );
    if (!mounted || selecionado == null) return;
    await _aplicarFiltro(_FiltroPeriodo.personalizado, periodo: selecionado);
  }

  Future<void> _aplicarFiltro(
    _FiltroPeriodo filtro, {
    DateTimeRange? periodo,
  }) async {
    if (_exportando || _saindo) return;
    setState(() {
      _filtroPeriodo = filtro;
      _periodoPersonalizado = periodo;
    });
    await carregarEstatisticas();
  }

  Future<void> carregarEstatisticas() async {
    if (!mounted || _exportando || _saindo) return;
    final token = ++_loadToken;
    final periodo = _intervaloSelecionado(_startOfDay(DateTime.now()));
    final limiteExclusivo = _diaSeguinte(periodo.end);
    setState(() {
      _loading = true;
      _erroCarregamento = false;
      _periodoCarregado = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vendas')
          .where('dataVenda', isGreaterThanOrEqualTo: periodo.start)
          .where('dataVenda', isLessThan: limiteExclusivo)
          .orderBy('dataVenda')
          .get();
      if (!mounted || token != _loadToken) return;

      var somaPeriodo = 0.0;
      var custoPeriodo = 0.0;
      var quantidadeCanceladas = 0;
      var somaCanceladas = 0.0;
      final formatoDia = DateFormat('dd/MM/yyyy');
      int vendasTotal = 0;

      final Map<String, double> tempVendasPorDia = {};
      final Map<String, int> tempFormasPagamento = {};
      final Map<String, double> tempVendasPorFuncionario = {};
      final Map<String, double> tempVendasPorCategoria = {};

      // gráficos/contadores de canceladas
      final Map<String, double> tempCanceladasPorDia = {};
      final Map<String, int> tempCanceladasPorMotivo = {};

      // pendências de categoria a resolver por codigoBarras (somadas por código)
      final Map<String, double> pendentesPorCodigo = {}; // codigo -> soma R$
      final List<Map<String, dynamic>> tempVendasDoPeriodo = [];

      for (var doc in snapshot.docs) {
        final dataDoc = doc.data();
        final carimbo = dataDoc['dataVenda'];
        if (carimbo is! Timestamp) continue;
        final diaStr = formatoDia.format(carimbo.toDate());
        tempVendasDoPeriodo.add(dataDoc);

        // ======= CANCELADAS (saem da contabilidade normal) =======
        if (_isCancelada(dataDoc)) {
          quantidadeCanceladas++;
          final valorCanc = _parseValorBr(dataDoc['totalVenda']);
          somaCanceladas += valorCanc;
          tempCanceladasPorDia[diaStr] =
              (tempCanceladasPorDia[diaStr] ?? 0) + valorCanc;

          final motivo = (dataDoc['motivoCancelamento'] ?? '')
              .toString()
              .trim();
          final motivoKey = motivo.isEmpty ? 'Sem motivo' : motivo;
          tempCanceladasPorMotivo[motivoKey] =
              (tempCanceladasPorMotivo[motivoKey] ?? 0) + 1;

          continue;
        }

        // ======= A PARTIR DAQUI, SÓ VENDAS ATIVAS =======
        final valor = _parseValorBr(dataDoc['totalVenda']);
        final funcionario = (dataDoc['funcionario'] ?? 'Desconhecido')
            .toString();

        tempVendasPorDia[diaStr] = (tempVendasPorDia[diaStr] ?? 0) + valor;

        final formasRegistradas = dataDoc['formasPagamento'];
        final formas = formasRegistradas is List ? formasRegistradas : const [];
        for (var forma in formas) {
          final f = (forma ?? '').toString();
          if (f.isEmpty) continue;
          tempFormasPagamento[f] = (tempFormasPagamento[f] ?? 0) + 1;
        }

        tempVendasPorFuncionario[funcionario] =
            (tempVendasPorFuncionario[funcionario] ?? 0) + valor;

        somaPeriodo += valor;
        vendasTotal++;

        final itens = dataDoc['itens'];
        if (itens is! List || itens.isEmpty) {
          custoPeriodo += _parseValorBr(dataDoc['valorReal']);
          continue;
        }

        for (final item in itens.whereType<Map>()) {
          final quantidade = _parseValorBr(item['quantidade'] ?? 1).toInt();
          custoPeriodo += _parseValorBr(item['valorReal']) * quantidade;
          final total = _parseValorBr(item['precoFinal']) * quantidade;
          final categoria = _snapCategoria(item['categoria']?.toString());

          if (categoria != 'OUTROS') {
            // categoria válida no item: soma direto
            tempVendasPorCategoria[categoria] =
                (tempVendasPorCategoria[categoria] ?? 0) + total;
          } else {
            // 2) ficou OUTROS -> tentar resolver por codigoBarras depois (em lote)
            final codigo =
                (item['codigoBarras'] ??
                        item['codigo'] ??
                        item['barcode'] ??
                        '')
                    .toString()
                    .trim();

            if (codigo.isNotEmpty) {
              pendentesPorCodigo[codigo] =
                  (pendentesPorCodigo[codigo] ?? 0) + total;
            } else {
              // sem código e sem categoria válida => OUTROS
              tempVendasPorCategoria['OUTROS'] =
                  (tempVendasPorCategoria['OUTROS'] ?? 0) + total;
            }
          }
        }
      }

      // ======= Resolver categorias por codigoBarras em LOTE (whereIn até 10) =======
      if (pendentesPorCodigo.isNotEmpty) {
        final codes = pendentesPorCodigo.keys.toList();
        final Set<String> resolvidos = {};

        for (var i = 0; i < codes.length; i += 10) {
          final chunk = codes.skip(i).take(10).toList();

          final qs = await FirebaseFirestore.instance
              .collection('produtos')
              .where('codigoBarras', whereIn: chunk)
              .get();

          if (!mounted || token != _loadToken) return;
          for (final d in qs.docs) {
            final data = d.data();
            final cod = (data['codigoBarras'] ?? '').toString().trim();
            if (cod.isEmpty || !resolvidos.add(cod)) continue;

            final cat = _snapCategoria(data['categoria']?.toString());
            final soma = pendentesPorCodigo[cod] ?? 0.0;

            tempVendasPorCategoria[cat] =
                (tempVendasPorCategoria[cat] ?? 0) + soma;
          }
        }

        // códigos não encontrados em 'produtos' => caem em OUTROS
        for (final cod in codes) {
          if (!resolvidos.contains(cod)) {
            final soma = pendentesPorCodigo[cod] ?? 0.0;
            tempVendasPorCategoria['OUTROS'] =
                (tempVendasPorCategoria['OUTROS'] ?? 0) + soma;
          }
        }
      }

      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _periodoCarregado = periodo;
        totalPeriodo = somaPeriodo;
        valorGastoTotal = custoPeriodo;
        lucro = somaPeriodo - custoPeriodo;
        totalVendas = vendasTotal;
        vendasPorDia = tempVendasPorDia;
        formasPagamento = tempFormasPagamento;
        vendasPorFuncionario = tempVendasPorFuncionario;
        vendasPorCategoria = tempVendasPorCategoria;
        totalCanceladas = quantidadeCanceladas;
        valorCancelado = somaCanceladas;
        canceladasPorDia = tempCanceladasPorDia;
        canceladasPorMotivo = tempCanceladasPorMotivo;
        _vendasDoPeriodo = tempVendasDoPeriodo;
        _touchedIndexCategorias = -1;
        _touchedIndexPagamentos = -1;
      });
    } catch (erro, pilha) {
      debugPrint('Financeiro geral • consulta: $erro\n$pilha');
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _erroCarregamento = true;
      });
    }
  }

  Future<void> _sair() async {
    if (_saindo || _exportando) return;
    setState(() => _saindo = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    } catch (erro) {
      debugPrint('Financeiro geral • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Não foi possível sair.')));
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Financeiro geral',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _texto,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.storefront_outlined, color: _marca, size: 16),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Todas as lojas',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
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
            tooltip: 'Atualizar financeiro',
            onPressed: _loading || _exportando || _saindo
                ? null
                : carregarEstatisticas,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _exportando || _saindo ? null : _sair,
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
      body: RefreshIndicator(
        onRefresh: carregarEstatisticas,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _filtros(),
              const SizedBox(height: 20),
              if (_loading)
                const LinearProgressIndicator(color: _marca)
              else if (_erroCarregamento)
                _cartao(
                  ListTile(
                    title: const Text(
                      'Não foi possível carregar o financeiro geral.',
                    ),
                    trailing: TextButton(
                      onPressed: carregarEstatisticas,
                      child: const Text('Tentar novamente'),
                    ),
                  ),
                )
              else if (_periodoCarregado != null) ...[
                _titulo('Indicadores do período'),
                const SizedBox(height: 12),
                _buildKPIs(),
                const SizedBox(height: 20),
                if (_vendasDoPeriodo.isEmpty)
                  const Text('Nenhuma venda registrada no período.'),
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
                    child: _BarChartVendasDia(
                      data: vendasPorDia,
                      chartHeight: 220,
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
  }

  Widget _link(IconData icone, String rotulo, Widget Function() abrir) {
    return ListTile(
      leading: Icon(icone, color: _suave),
      title: Text(rotulo),
      onTap: () {
        if (_saindo || _exportando) return;
        final navegador = Navigator.of(context);
        navegador.pop();
        navegador.pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => abrir()),
        );
      },
    );
  }

  Widget _filtros() {
    final periodo =
        _periodoCarregado ?? _intervaloSelecionado(_startOfDay(DateTime.now()));
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titulo('Período'),
            const SizedBox(height: 4),
            Text(
              '${_filtroPeriodo.rotulo} · ${_labelPeriodo(periodo)}',
              style: const TextStyle(color: _suave),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filtro in _FiltroPeriodo.values)
                  if (filtro != _FiltroPeriodo.personalizado)
                    ChoiceChip(
                      label: Text(filtro.rotulo),
                      selected: _filtroPeriodo == filtro,
                      selectedColor: _rosaClaro,
                      onSelected: _exportando
                          ? null
                          : (selecionado) {
                              if (selecionado) _aplicarFiltro(filtro);
                            },
                    ),
                OutlinedButton.icon(
                  onPressed: _exportando ? null : _selecionarIntervaloDatas,
                  icon: const Icon(Icons.date_range_outlined),
                  label: const Text('Selecionar datas'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _marca),
                  onPressed:
                      _loading || _exportando || _periodoCarregado == null
                      ? null
                      : _exportarPDF,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_exportando ? 'Gerando PDF…' : 'Exportar PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIs() {
    final cards = [
      _indicador(
        Icons.date_range_outlined,
        'Vendas do período',
        _brl.format(totalPeriodo),
      ),
      _indicador(
        Icons.payments_outlined,
        'Custo dos itens',
        _brl.format(valorGastoTotal),
      ),
      _indicador(Icons.trending_up, 'Lucro bruto', _brl.format(lucro)),
      _indicador(
        Icons.receipt_long_outlined,
        'Quantidade de vendas',
        NumberFormat.decimalPattern('pt_BR').format(totalVendas),
      ),
      _indicador(
        Icons.cancel_outlined,
        'Canceladas',
        NumberFormat.decimalPattern('pt_BR').format(totalCanceladas),
        detalhe: _brl.format(valorCancelado),
      ),
    ];
    return LayoutBuilder(
      builder: (context, limites) {
        const espaco = 12.0;
        final colunas = ((limites.maxWidth + espaco) / (180 + espaco))
            .floor()
            .clamp(1, 4)
            .toInt();
        final largura = ((limites.maxWidth - espaco * (colunas - 1)) / colunas)
            .floorToDouble();
        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            for (final card in cards) SizedBox(width: largura, child: card),
          ],
        );
      },
    );
  }

  Widget _indicador(
    IconData icone,
    String rotulo,
    String valor, {
    String? detalhe,
  }) {
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _icone(icone),
            const SizedBox(height: 10),
            Text(
              valor,
              style: const TextStyle(
                color: _texto,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              rotulo,
              style: const TextStyle(
                color: _suave,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detalhe != null)
              Text(
                detalhe,
                style: const TextStyle(color: _suave, fontSize: 12),
              ),
          ],
        ),
      ),
    );
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
}

class _SeletorPeriodo extends StatefulWidget {
  const _SeletorPeriodo({
    required this.primeiroDia,
    required this.ultimoDia,
    required this.periodoInicial,
  });

  final DateTime primeiroDia;
  final DateTime ultimoDia;
  final DateTimeRange? periodoInicial;

  @override
  State<_SeletorPeriodo> createState() => _SeletorPeriodoState();
}

class _SeletorPeriodoState extends State<_SeletorPeriodo> {
  final _formato = DateFormat('dd/MM/yyyy');
  DateTime? _inicio;
  DateTime? _fim;
  bool _selecionandoInicio = true;

  @override
  void initState() {
    super.initState();
    _inicio = widget.periodoInicial?.start;
    _fim = widget.periodoInicial?.end;
  }

  void _selecionarData(DateTime data) {
    setState(() {
      if (_selecionandoInicio) {
        _inicio = data;
        if (_fim == null || _fim!.isBefore(data)) _fim = data;
      } else {
        _fim = data;
      }
    });
  }

  void _aplicar() {
    final inicio = _inicio;
    final fim = _fim;
    if (inicio == null || fim == null || fim.isBefore(inicio)) return;
    Navigator.of(context).pop(DateTimeRange(start: inicio, end: fim));
  }

  Widget _botaoData(String rotulo, DateTime? data, {required bool inicio}) {
    final ativo = _selecionandoInicio == inicio;
    return Semantics(
      selected: ativo,
      child: OutlinedButton(
        onPressed: inicio || _inicio != null
            ? () => setState(() => _selecionandoInicio = inicio)
            : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: ativo ? _marca : _texto,
          backgroundColor: ativo ? _rosaClaro : Colors.white,
          side: BorderSide(color: ativo ? _marca : _borda),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          heightFactor: 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: const TextStyle(fontSize: 12)),
              Text(
                data == null ? 'Selecionar' : _formato.format(data),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final escala = MediaQuery.textScalerOf(context).scale(14) / 14;
    final alturaCalendario = 346.0 + math.max(0.0, escala - 1) * 56;

    return Theme(
      data: tema.copyWith(
        colorScheme: tema.colorScheme.copyWith(
          primary: _marca,
          onPrimary: Colors.white,
        ),
      ),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 390,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _titulo('Selecionar período'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _botaoData('Início', _inicio, inicio: true),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _botaoData('Fim', _fim, inicio: false)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _selecionandoInicio
                          ? 'Escolha a data inicial e toque em Fim para ajustar a data final.'
                          : 'Escolha o último dia.',
                      style: const TextStyle(color: _suave, fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    height: alturaCalendario,
                    child: CalendarDatePicker(
                      key: ValueKey(_selecionandoInicio),
                      initialDate: _selecionandoInicio ? _inicio : _fim,
                      firstDate: _selecionandoInicio
                          ? widget.primeiroDia
                          : _inicio!,
                      lastDate: widget.ultimoDia,
                      currentDate: widget.ultimoDia,
                      onDateChanged: _selecionarData,
                    ),
                  ),
                  const Divider(height: 12, color: _borda),
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
                        onPressed: _inicio == null || _fim == null
                            ? null
                            : _aplicar,
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
    );
  }
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

Widget _titulo(String texto) => Text(
  texto,
  style: const TextStyle(
    color: _texto,
    fontSize: 18,
    fontWeight: FontWeight.w800,
  ),
);

Widget _icone(IconData icone) => DecoratedBox(
  decoration: BoxDecoration(
    color: _rosaClaro,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Padding(
    padding: const EdgeInsets.all(9),
    child: Icon(icone, color: _marca, size: 20),
  ),
);

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
    final maxY = math.max(1.0, (maxValor * 1.2).ceilToDouble());
    final step = (dias.length / 10).ceil();

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
                if (i < 0 ||
                    i >= dias.length ||
                    (i % step != 0 && i != dias.length - 1)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    dias[i].substring(0, 5),
                    style: const TextStyle(fontSize: 11),
                  ),
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
  final Map<String, double> data; // Data completa, em ordem cronológica.
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

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return const Center(child: Text('Sem dados para mostrar'));
    }

    final entries = widget.data.entries.toList();
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
                          dias[i].substring(0, 5),
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
