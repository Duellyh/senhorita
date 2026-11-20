import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diacritic/diacritic.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

class FinanceiroEspecificoView extends StatefulWidget {
  final String lojaSelecionada;

  const FinanceiroEspecificoView({super.key, required this.lojaSelecionada});

  @override
  State<FinanceiroEspecificoView> createState() =>
      _FinanceiroEspecificoViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);

final _numero = NumberFormat.decimalPattern('pt_BR');

enum _FiltroPeriodo {
  hoje('Hoje'),
  mesAtual('Mês atual'),
  semanaPassada('Semana passada'),
  mesPassado('Mês passado'),
  personalizado('Personalizado');

  const _FiltroPeriodo(this.rotulo);

  final String rotulo;
}

class _FinanceiroEspecificoViewState extends State<FinanceiroEspecificoView> {
  String tipoUsuario = '';
  String nomeUsuario = '';
  DateTimeRange? _periodoPersonalizado;
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

  int _loadToken = 0;
  bool _loading = false;
  bool _exportando = false;
  bool _saindo = false;
  bool _erroCarregamento = false;
  DateTimeRange? _periodoCarregado;

  _FiltroPeriodo _filtroPeriodo = _FiltroPeriodo.hoje;
  double totalPeriodoSelecionado = 0;

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

  String? _lojaPadraoDosItens(Map<String, dynamic> venda) {
    final lojasDeclaradas = venda['lojaProdutoOficial'];
    if (lojasDeclaradas is List) {
      final lojas = lojasDeclaradas
          .whereType<String>()
          .map(_lojaKey)
          .where((loja) => loja.isNotEmpty)
          .toSet();
      if (lojas.isNotEmpty) return lojas.length == 1 ? lojas.single : null;
    }

    if (lojasDeclaradas is String && lojasDeclaradas.trim().isNotEmpty) {
      return lojasDeclaradas;
    }

    final caixa = (venda['lojaCaixa'] ?? '').toString().trim();
    return caixa.isNotEmpty ? caixa : venda['loja']?.toString();
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
    valorGastoTotal = 0;
    totalVendas = 0;
    lucro = 0;

    vendasPorDia = {};
    formasPagamento = {};
    vendasPorFuncionario = {};
    vendasPorCategoria = {};

    totalCanceladas = 0;
    valorCancelado = 0;
    canceladasPorDia = {};
    canceladasPorMotivo = {};

    _vendasDoPeriodo = [];
    _periodoCarregado = null;
  }

  @override
  void didUpdateWidget(covariant FinanceiroEspecificoView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.lojaSelecionada.trim() != widget.lojaSelecionada.trim()) {
      carregarEstatisticas();
    }
  }

  Future<String?> _buscarLojaProdutoPorDocId(String docId) async {
    if (docId.trim().isEmpty) return null;
    final doc = await FirebaseFirestore.instance
        .collection('produtos')
        .doc(docId)
        .get();
    if (!doc.exists) return null;

    final loja = (doc.data()?['loja'] ?? '').toString();
    return loja.isEmpty ? null : loja;
  }

  Future<String?> _buscarLojaProdutoPorCodigo(String codigoBarras) async {
    final cod = codigoBarras.trim();
    if (cod.isEmpty) return null;

    final qs = await FirebaseFirestore.instance
        .collection('produtos')
        .where('codigoBarras', isEqualTo: cod)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return null;

    final loja = (qs.docs.first.data()['loja'] ?? '').toString();
    return loja.isEmpty ? null : loja;
  }

  // Decide qual loja é do item (prioriza loja já gravada no item)
  Future<String?> _lojaDoItem(Map item, _CacheLojas cache) async {
    // ✅ 1) loja do produto já salva no item (SEU realizarVenda grava como lojaProduto)
    final lojaProduto = (item['lojaProduto'] ?? '').toString().trim();
    if (lojaProduto.isNotEmpty) return lojaProduto;

    // ✅ 1.1) compatibilidade: se existir "loja" (versão antiga/alternativa)
    final lojaDireta = (item['loja'] ?? '').toString().trim();
    if (lojaDireta.isNotEmpty) return lojaDireta;

    // ✅ 2) docId
    final docId = (item['docId'] ?? '').toString().trim();
    if (docId.isNotEmpty) {
      final loja = await cache.documentos.putIfAbsent(
        docId,
        () => _buscarLojaProdutoPorDocId(docId),
      );
      if (loja != null && loja.trim().isNotEmpty) return loja;
    }

    // ✅ 3) codigo barras
    final codigo =
        (item['codigoBarras'] ?? item['codigo'] ?? item['barcode'] ?? '')
            .toString()
            .trim();
    if (codigo.isNotEmpty) {
      return cache.codigos.putIfAbsent(
        codigo,
        () => _buscarLojaProdutoPorCodigo(codigo),
      );
    }

    return null;
  }

  bool _mesmaLoja(String? a, String b) {
    if (a == null || a.trim().isEmpty) return false;
    return _mesmaLojaKey(a, b);
  }

  double _toDouble(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse((valor ?? '').toString().replaceAll(',', '.').trim());
    return numero != null && numero.isFinite ? numero : 0.0;
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      if (!mounted) return;
      final dados = doc.data();
      setState(() {
        tipoUsuario = (dados?['tipo'] ?? 'funcionario').toString();
        nomeUsuario = (dados?['nome'] ?? 'Usuário').toString();
      });
    } catch (erro) {
      debugPrint('Financeiro específico • perfil: $erro');
    }
  }

  Future<void> _exportarPDF() async {
    final periodo = _periodoCarregado;
    if (periodo == null || _loading || _exportando) return;
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

    final agora = DateTime.now();
    final loja = widget.lojaSelecionada.trim();
    final inicioFiltro = periodo.start;
    final fimFiltro = periodo.end;
    final vendasAtivas = _vendasDoPeriodo
        .where((venda) => !_isCancelada(venda))
        .toList();
    final canceladas = _vendasDoPeriodo.where(_isCancelada).toList();

    // ===================== somatório por forma (valor) =========================
    // Observação: como a venda pode ser "mista", aqui atribuímos o subtotal da loja
    // às formas de pagamento da venda (se houver mais de uma forma, distribui proporcionalmente
    // pelo valor informado; se não houver valor por forma, divide igualmente).
    final Map<String, double> totalPorForma = {};

    for (final data in vendasAtivas) {
      final subtotalLoja = _toDouble(data['_subtotalLoja']);
      if (subtotalLoja <= 0) continue;

      final camposPagamento = data['pagamentos'];
      final pagamentos = camposPagamento is List
          ? camposPagamento.whereType<Map>()
          : const <Map>[];

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

      final cadastradas = data['formasPagamento'];
      final pagamentos = data['pagamentos'];
      final formas = cadastradas is List && cadastradas.isNotEmpty
          ? cadastradas.join(', ')
          : pagamentos is List
          ? pagamentos
                .whereType<Map>()
                .map((p) => (p['forma'] ?? p['tipo'] ?? '').toString())
                .where((s) => s.trim().isNotEmpty)
                .join(', ')
          : (data['formaPagamento'] ?? '').toString();

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
            pw.Text('Relatório Financeiro', style: pw.TextStyle(fontSize: 24)),
            pw.SizedBox(height: 6),
            pw.Text(
              'Loja: $loja',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),

            pw.Text(
              'Período: ${DateFormat('dd/MM/yyyy').format(inicioFiltro)} - ${DateFormat('dd/MM/yyyy').format(fimFiltro)}',
            ),
            pw.SizedBox(height: 8),

            pw.Text('Total de Vendas (Loja): ${vendasAtivas.length}'),
            pw.Text(
              'Total de Vendas no Período (Loja): ${fmtBRL(totalPeriodoSelecionado)}',
            ),
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
              'Detalhes das Vendas (Loja)',
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
              'Formas de Pagamento (Qtd na tela)',
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
              'Vendas por Funcionário (Tela)',
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
              'Vendas por Categoria (Tela)',
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
              'Vendas por Dia (Tela)',
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
                'Vendas Canceladas (Loja)',
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
      filename: 'relatorio_vendas_$loja.pdf',
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
    if (_exportando) return;
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

  Future<_TotaisItens> _resumirItens(
    Map<String, dynamic> venda,
    String loja,
    _CacheLojas cache, {
    required bool detalhar,
  }) async {
    final lojaPadrao = _lojaPadraoDosItens(venda);
    final itensDaVenda = venda['itens'];
    final itens = itensDaVenda is List
        ? itensDaVenda.whereType<Map>().toList()
        : const <Map>[];
    if (itens.isEmpty) {
      if (!_mesmaLoja(lojaPadrao, loja)) return const _TotaisItens(0, 0, {});
      final total = _toDouble(venda['totalVenda']);
      final custo = detalhar ? _toDouble(venda['valorReal']) : 0.0;
      return _TotaisItens(total, custo, const {});
    }

    var subtotal = 0.0;
    var custo = 0.0;
    final totaisCategorias = <String, double>{};
    for (final item in itens) {
      final lojaItem = await _lojaDoItem(item, cache) ?? lojaPadrao;
      if (!_mesmaLoja(lojaItem, loja)) continue;
      final qtd = _toInt(item['quantidade'], def: 1);
      final preco = _toDouble(
        item['precoFinal'] ?? item['preco'] ?? item['valor'],
      );
      final total = preco * qtd;
      subtotal += total;
      if (detalhar) {
        custo += _toDouble(item['valorReal']) * qtd;
        _somar(
          totaisCategorias,
          _snapCategoria(item['categoria']?.toString()),
          total,
        );
      }
    }
    return _TotaisItens(subtotal, custo, totaisCategorias);
  }

  Future<void> carregarEstatisticas() async {
    if (!mounted || _saindo) return;
    final token = ++_loadToken;
    final loja = widget.lojaSelecionada.trim();
    setState(() {
      _loading = loja.isNotEmpty;
      _erroCarregamento = false;
      _resetDashboardState();
      totalPeriodoSelecionado = 0;
      _touchedIndexCategorias = -1;
      _touchedIndexPagamentos = -1;
    });
    if (loja.isEmpty) return;

    final periodo = _intervaloSelecionado(_startOfDay(DateTime.now()));
    final limiteExclusivo = _diaSeguinte(periodo.end);
    final cache = _CacheLojas();

    try {
      final resultado = await FirebaseFirestore.instance
          .collection('vendas')
          .where('dataVenda', isGreaterThanOrEqualTo: periodo.start)
          .where('dataVenda', isLessThan: limiteExclusivo)
          .orderBy('dataVenda')
          .get();
      if (!mounted || token != _loadToken) return;

      var somaPeriodo = 0.0;
      var gastoPeriodo = 0.0;
      var quantidadeVendas = 0;
      var quantidadeCanceladas = 0;
      var somaCanceladas = 0.0;

      final porDia = <String, double>{};
      final porFuncionario = <String, double>{};
      final porCategoria = <String, double>{};
      final porForma = <String, int>{};
      final canceladasDia = <String, double>{};
      final canceladasMotivo = <String, int>{};
      final registrosPeriodo = <Map<String, dynamic>>[];
      final dataFormato = DateFormat('dd/MM/yyyy');

      for (final documento in resultado.docs) {
        if (!mounted || token != _loadToken) return;
        final venda = documento.data();
        final carimbo = venda['dataVenda'];
        if (carimbo is! Timestamp) continue;

        final data = carimbo.toDate();
        final cancelada = _isCancelada(venda);
        final totais = await _resumirItens(
          venda,
          loja,
          cache,
          detalhar: !cancelada,
        );
        if (!mounted || token != _loadToken) return;
        if (!totais.subtotal.isFinite || totais.subtotal <= 0) continue;

        registrosPeriodo.add({...venda, '_subtotalLoja': totais.subtotal});
        final dia = dataFormato.format(data);
        if (cancelada) {
          quantidadeCanceladas++;
          somaCanceladas += totais.subtotal;
          _somar(canceladasDia, dia, totais.subtotal);
          final motivo = (venda['motivoCancelamento'] ?? '').toString().trim();
          final chave = motivo.isEmpty ? 'Sem motivo' : motivo;
          canceladasMotivo.update(
            chave,
            (valor) => valor + 1,
            ifAbsent: () => 1,
          );
          continue;
        }

        quantidadeVendas++;
        somaPeriodo += totais.subtotal;
        gastoPeriodo += totais.custo;
        _somar(porDia, dia, totais.subtotal);
        final funcionario = (venda['funcionario'] ?? 'Desconhecido').toString();
        _somar(porFuncionario, funcionario, totais.subtotal);

        final formas = venda['formasPagamento'];
        if (formas is List) {
          for (final forma in formas) {
            final nome = forma.toString().trim();
            if (nome.isEmpty) continue;
            porForma.update(nome, (valor) => valor + 1, ifAbsent: () => 1);
          }
        }
        for (final categoria in totais.categorias.entries) {
          _somar(porCategoria, categoria.key, categoria.value);
        }
      }

      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _periodoCarregado = periodo;
        totalPeriodoSelecionado = somaPeriodo;
        totalVendas = quantidadeVendas;
        valorGastoTotal = gastoPeriodo;
        lucro = somaPeriodo - gastoPeriodo;
        vendasPorDia = porDia;
        formasPagamento = porForma;
        vendasPorFuncionario = porFuncionario;
        vendasPorCategoria = porCategoria;
        totalCanceladas = quantidadeCanceladas;
        valorCancelado = somaCanceladas;
        canceladasPorDia = canceladasDia;
        canceladasPorMotivo = canceladasMotivo;
        _vendasDoPeriodo = registrosPeriodo;
      });
    } catch (erro, pilha) {
      debugPrint('Financeiro específico • consulta: $erro\n$pilha');
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
      debugPrint('Financeiro específico • saída: $erro');
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
        elevation: 0,
        toolbarHeight: 76,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Financeiro específico',
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
            tooltip: 'Atualizar financeiro',
            onPressed: _loading || _exportando || _saindo || loja.isEmpty
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
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saindo,
          child: LayoutBuilder(
            builder: (context, limites) {
              final margem = limites.maxWidth >= 720 ? 32.0 : 14.0;
              return RefreshIndicator(
                color: _marca,
                onRefresh: () async {
                  if (!_loading && !_exportando) await carregarEstatisticas();
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(margem, 24, margem, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
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
    if (loja.isEmpty) {
      return _mensagem('Selecione uma loja para consultar o financeiro.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filtros(),
        const SizedBox(height: 20),
        if (_loading)
          _cartao(
            const Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Carregando o resumo financeiro…',
                    style: TextStyle(color: _suave),
                  ),
                  SizedBox(height: 12),
                  LinearProgressIndicator(color: _marca),
                ],
              ),
            ),
          )
        else if (_erroCarregamento)
          _mensagem(
            'Não foi possível carregar o financeiro desta loja.',
            acao: TextButton(
              onPressed: carregarEstatisticas,
              child: const Text('Tentar novamente'),
            ),
          )
        else if (_periodoCarregado != null) ...[
          _titulo('Indicadores do período'),
          const SizedBox(height: 12),
          _indicadores(),
          const SizedBox(height: 22),
          _grafico(
            'Vendas por dia',
            vendasPorDia.isEmpty
                ? const Center(child: Text('Nenhuma venda no período.'))
                : _rolagemDatas(
                    vendasPorDia.length,
                    _BarChartVendasDia(data: vendasPorDia, chartHeight: 220),
                  ),
          ),
          const SizedBox(height: 14),
          _grafico(
            'Vendas por funcionário',
            _BarChartFuncionarios(
              data: vendasPorFuncionario,
              maxBars: 7,
              chartHeight: 240,
            ),
          ),
          const SizedBox(height: 14),
          _graficosEmColunas(
            _grafico(
              'Formas de pagamento',
              _buildPieChartPagamentos(_vendasDoPeriodo),
            ),
            _grafico('Vendas por categoria', _buildPieChartCategorias()),
          ),
          const SizedBox(height: 14),
          _grafico(
            'Canceladas por dia',
            _rolagemDatas(
              canceladasPorDia.length,
              SizedBox(
                height: 220,
                child: _BarChartCanceladas(data: canceladasPorDia),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _grafico(
            'Motivos de cancelamento',
            _buildPieChartCanceladasMotivos(),
          ),
        ],
      ],
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

  Widget _indicadores() {
    final cards = [
      _indicador(
        Icons.date_range_outlined,
        'Vendas do período',
        _brl.format(totalPeriodoSelecionado),
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
        _numero.format(totalVendas),
      ),
      _indicador(
        Icons.cancel_outlined,
        'Canceladas',
        _numero.format(totalCanceladas),
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

  Widget _grafico(String titulo, Widget grafico) {
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_titulo(titulo), const SizedBox(height: 14), grafico],
        ),
      ),
    );
  }

  Widget _graficosEmColunas(Widget primeiro, Widget segundo) {
    return LayoutBuilder(
      builder: (context, limites) {
        if (limites.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primeiro, const SizedBox(height: 14), segundo],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: primeiro),
            const SizedBox(width: 14),
            Expanded(child: segundo),
          ],
        );
      },
    );
  }

  Widget _rolagemDatas(int dias, Widget grafico) {
    return LayoutBuilder(
      builder: (context, limites) {
        final larguraMinima = 56.0 + dias * 32.0;
        if (larguraMinima <= limites.maxWidth) return grafico;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: larguraMinima, child: grafico),
        );
      },
    );
  }

  Widget _mensagem(String texto, {Widget? acao}) {
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Text(texto, textAlign: TextAlign.center),
            if (acao != null) acao,
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
    final valoresPorForma = _somarPorForma(vendasDoPeriodo);

    if (valoresPorForma.isEmpty) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    const int maxSlices = 6; // 5 maiores + "Outras"
    final entries = valoresPorForma.entries.toList()
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
      if (_isCancelada(v)) continue;
      final subtotalLoja = _toDouble(v['_subtotalLoja']); // vem do passo 1
      final totalVenda = _toDouble(v['totalVenda']);

      // rateio: se a venda total é 100 e subtotalLoja é 40 => loja paga 40% de cada pagamento
      final double rate = (totalVenda > 0)
          ? (subtotalLoja / totalVenda).clamp(0.0, 1.0).toDouble()
          : 1.0;

      final campoPagamentos = v['pagamentos'];
      final pagamentos = campoPagamentos is List ? campoPagamentos : const [];

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
        final campoFormas = v['formasPagamento'];
        final formas = campoFormas is List ? campoFormas : const [];
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
                  child: Text(
                    _diaCurto(dias[i]),
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
                          _diaCurto(dias[i]),
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

class _CacheLojas {
  final documentos = <String, Future<String?>>{};
  final codigos = <String, Future<String?>>{};
}

class _TotaisItens {
  const _TotaisItens(this.subtotal, this.custo, this.categorias);

  final double subtotal;
  final double custo;
  final Map<String, double> categorias;
}

void _somar(Map<String, double> totais, String chave, double valor) {
  totais.update(chave, (atual) => atual + valor, ifAbsent: () => valor);
}

String _diaCurto(String data) => data.length > 5 ? data.substring(0, 5) : data;

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
