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

class FinanceiroView extends StatefulWidget {
  const FinanceiroView({super.key});

  @override
  State<FinanceiroView> createState() => _FinanceiroViewState();
}

class _FinanceiroViewState extends State<FinanceiroView> {
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

  int totalCanceladas = 0;
  double valorCancelado = 0;
  List<Map<String, dynamic>> listaCanceladas = []; // p/ PDF/Tabela se quiser

  // NOVOS mapas p/ gráficos:
  Map<String, double> canceladasPorDia = {}; // R$ por dia (ex.: "12/09": 350.0)
  Map<String, int> canceladasPorMotivo = {}; // qtd por motivo

  bool _isCancelada(Map<String, dynamic> venda) {
    final status = (venda['status'] ?? '').toString().toLowerCase().trim();
    final flag = venda['cancelada'] == true;
    return flag || status == 'cancelada';
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

    // ===================== NOVO: helpers forma de pagamento =====================
    String _normalizarForma(String f) {
      final s = f.toLowerCase().trim();
      if (s.contains('pix')) return 'Pix';
      if (s.contains('dinheiro')) return 'Dinheiro';
      if (s.contains('débito') || s.contains('debito')) return 'Débito';
      if (s.contains('crédito') || s.contains('credito')) return 'Crédito';
      if (s.contains('cartao') || s.contains('cartão')) {
        // se seu app diferencia "cartão débito" e "cartão crédito" no texto:
        if (s.contains('debito') || s.contains('débito')) return 'Débito';
        if (s.contains('credito') || s.contains('crédito')) return 'Crédito';
        // fallback genérico para Cartão -> Crédito (ajuste se preferir)
        return 'Crédito';
      }
      return f.isEmpty ? 'Outros' : f[0].toUpperCase() + f.substring(1);
    }

    void _addForma(Map<String, double> acc, String forma, double valor) {
      if (valor <= 0) return;
      final key = _normalizarForma(forma);
      acc[key] = (acc[key] ?? 0) + valor;
    }
    // ===========================================================================

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

    // DEBUG opcional
    print('🔍 Vendas encontradas para o PDF: ${snapshot.docs.length}');

    // Separa ativas e canceladas
    final vendasAtivasDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final canceladasDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final d in snapshot.docs) {
      final m = d.data();
      if (_isCancelada(m)) {
        canceladasDocs.add(d);
      } else {
        vendasAtivasDocs.add(d);
      }
    }
    // ===================== NOVO: somatório por forma (valor) ====================
    final Map<String, double> totalPorForma = {};
    for (final doc in vendasAtivasDocs) {
      final data = doc.data();

      // Caso padrão: lista de pagamentos [{forma: 'Pix', valor: 100.0}, ...]
      final pagamentos =
          (data['pagamentos'] as List?)?.whereType<Map>() ?? const [];

      if (pagamentos.isNotEmpty) {
        for (final p in pagamentos) {
          final forma = (p['forma'] ?? p['tipo'] ?? '').toString();
          final valor = (p['valor'] ?? p['quantia'] ?? 0).toString();
          final v =
              double.tryParse(valor.replaceAll(',', '.')) ??
              (p['valor'] as num?)?.toDouble() ??
              0.0;
          _addForma(totalPorForma, forma, v);
        }
        continue;
      }

      // Fallback (se não houver lista de pagamentos):
      // Se existir apenas um campo 'formaPagamento' e o totalVenda,
      // atribuimos TODO o valor àquela forma (ajuste se não desejar esse fallback).
      final unicaForma = (data['formaPagamento'] ?? '').toString();
      if (unicaForma.isNotEmpty) {
        final totalVenda = (data['totalVenda'] ?? 0).toDouble();
        _addForma(totalPorForma, unicaForma, totalVenda);
        continue;
      }

      // Se só houver lista de nomes (sem valores individuais), não é possível
      // repartir com precisão — então não somamos aqui.
      // final formasLista = (data['formasPagamento'] as List?)?.cast<String>();
    }
    // ===========================================================================

    // Monta linhas da tabela principal (somente ativas)
    final linhasAtivas = vendasAtivasDocs.map((doc) {
      final data = doc.data();
      final valor = (data['totalVenda'] ?? 0).toDouble();
      final ts = data['dataVenda'];
      final DateTime dataVenda = ts is Timestamp
          ? ts.toDate()
          : DateTime.tryParse(ts?.toString() ?? '') ?? agora;

      final formas = (data['formasPagamento'] as List?)?.join(', ') ?? '-';
      final funcionario = data.containsKey('funcionario')
          ? (data['funcionario'] ?? '-')
          : '-';

      return [
        DateFormat('dd/MM/yyyy').format(dataVenda),
        'R\$ ${valor.toStringAsFixed(2)}',
        formas,
        funcionario,
      ];
    }).toList();

    // Monta linhas da seção de canceladas
    double valorCancelado = 0;
    final linhasCanceladas = canceladasDocs.map((doc) {
      final data = doc.data();
      final valor = (data['totalVenda'] ?? 0).toDouble();
      valorCancelado += valor;

      final ts = data['dataVenda'];
      final DateTime? dataVenda = ts is Timestamp
          ? ts.toDate()
          : DateTime.tryParse(ts?.toString() ?? '');

      final funcionario = data['funcionario'] ?? '-';
      final cliente = (data['cliente']?['nome']) ?? '-';
      final motivo = (data['motivoCancelamento'] ?? '').toString().trim();

      return [
        _fmtData(dataVenda),
        'R\$ ${valor.toStringAsFixed(2)}',
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
              '📊 Relatório Financeiro',
              style: pw.TextStyle(fontSize: 24),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Período: ${DateFormat('dd/MM/yyyy').format(inicioFiltro)} - ${DateFormat('dd/MM/yyyy').format(fimFiltro)}',
            ),
            pw.SizedBox(height: 8),
            // Observação: estes KPIs vêm do estado atual; se já excluem canceladas,
            // ótimo. Se não, você pode recalcular aqui usando 'vendasAtivasDocs'.
            pw.Text('Total de Vendas: $totalVendas'),
            pw.Text(
              'Total de Vendas no Período: R\$ ${totalMes.toStringAsFixed(2)}',
            ),
            pw.Text('Total de Hoje: R\$ ${totalHoje.toStringAsFixed(2)}'),
            pw.Text(
              'Valor Gasto Total: R\$ ${valorGastoTotal.toStringAsFixed(2)}',
            ),
            pw.Text('Lucro: R\$ ${lucro.toStringAsFixed(2)}'),
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
                  'Total de vendas no ${k.toLowerCase()}: R\$ ${v.toStringAsFixed(2)}',
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
                  .map((e) => [e.key, 'R\$ ${e.value.toStringAsFixed(2)}'])
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
                  .map((e) => [e.key, 'R\$ ${e.value.toStringAsFixed(2)}'])
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
                  .map((e) => [e.key, 'R\$ ${e.value.toStringAsFixed(2)}'])
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

            // ========= NOVA SEÇÃO: VENDAS CANCELADAS =========
            if (canceladasDocs.isNotEmpty) ...[
              pw.SizedBox(height: 24),
              pw.Divider(),
              pw.Text(
                '❌ Vendas Canceladas',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Quantidade: ${canceladasDocs.length}'),
              pw.Text(
                'Valor Total Cancelado: R\$ ${valorCancelado.toStringAsFixed(2)}',
              ),
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
      filename: 'relatorio_vendas.pdf',
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
      initialDateRange: dataInicio != null && dataFim != null
          ? DateTimeRange(start: dataInicio!, end: dataFim!)
          : null,
    );

    if (picked != null) {
      setState(() {
        dataInicio = picked.start;
        dataFim = picked.end;
      });

      carregarEstatisticas(); // Recarrega os dados com filtro
    }
  }

  Future<void> carregarEstatisticas() async {
    // --- helper local para normalizar e casar com sua lista 'categorias' ---
    String _snapCategoriaLocal(String? raw) {
      if (raw == null) return 'OUTROS';
      final s = raw.toString().trim().toUpperCase();
      // tenta match case-insensitive com a lista canônica
      for (final c in categorias) {
        if (c.trim().toUpperCase() == s) return c; // retorna o nome canônico
      }
      return 'OUTROS';
    }

    double _toDouble(dynamic v) {
      if (v is int) return v.toDouble();
      if (v is double) return v;
      if (v == null) return 0.0;
      final s = v.toString().replaceAll(',', '.').trim();
      return double.tryParse(s) ?? 0.0;
    }

    // -----------------------------------------------------------------------

    valorGastoTotal = 0; // Reset para não acumular

    final agora = DateTime.now();
    final inicioFiltro = dataInicio ?? DateTime(agora.year, agora.month, 1);
    final fimFiltro = (dataFim ?? DateTime.now()).add(
      const Duration(hours: 23, minutes: 59, seconds: 59),
    );

    final snapshot = await FirebaseFirestore.instance
        .collection('vendas')
        .orderBy('dataVenda') // <-- ESSENCIAL!
        .where('dataVenda', isGreaterThanOrEqualTo: inicioFiltro)
        .where('dataVenda', isLessThanOrEqualTo: fimFiltro)
        .get();

    double somaHoje = 0;
    double somaMes = 0;
    int vendasTotal = 0;

    final Map<String, double> tempVendasPorDia = {};
    final Map<String, int> tempFormasPagamento = {};
    final Map<String, double> tempVendasPorFuncionario = {};
    final Map<String, double> tempVendasPorCategoria = {};

    // gráficos/contadores de canceladas
    final Map<String, double> tempCanceladasPorDia = {};
    final Map<String, int> tempCanceladasPorMotivo = {};
    totalCanceladas = 0;
    valorCancelado = 0;
    listaCanceladas = [];

    // pendências de categoria a resolver por codigoBarras (somadas por código)
    final Map<String, double> pendentesPorCodigo = {}; // codigo -> soma R$

    for (var doc in snapshot.docs) {
      final dataDoc = doc.data();

      // ======= CANCELADAS (saem da contabilidade normal) =======
      if (_isCancelada(dataDoc)) {
        totalCanceladas++;
        final valorCanc = _toDouble(dataDoc['totalVenda']);
        valorCancelado += valorCanc;

        final dt = (dataDoc['dataVenda'] as Timestamp?)?.toDate();
        final diaStr = dt != null ? DateFormat('dd/MM').format(dt) : '-';
        tempCanceladasPorDia[diaStr] =
            (tempCanceladasPorDia[diaStr] ?? 0) + valorCanc;

        final motivo = (dataDoc['motivoCancelamento'] ?? '').toString().trim();
        final motivoKey = motivo.isEmpty ? 'Sem motivo' : motivo;
        tempCanceladasPorMotivo[motivoKey] =
            (tempCanceladasPorMotivo[motivoKey] ?? 0) + 1;

        listaCanceladas.add({
          'dataVenda': dt,
          'totalVenda': valorCanc,
          'formasPagamento': (dataDoc['formasPagamento'] as List?) ?? const [],
          'funcionario': dataDoc['funcionario'] ?? '-',
          'cliente': dataDoc['cliente']?['nome'] ?? '-',
          'motivo': motivo,
        });
        continue;
      }

      // ======= A PARTIR DAQUI, SÓ VENDAS ATIVAS =======
      final DateTime data = (dataDoc['dataVenda'] as Timestamp).toDate();
      final double valor = _toDouble(dataDoc['totalVenda']);
      final String funcionario = dataDoc.containsKey('funcionario')
          ? (dataDoc['funcionario'] ?? 'Desconhecido')
          : 'Desconhecido';

      final diaStr = DateFormat('dd/MM').format(data);
      tempVendasPorDia[diaStr] = (tempVendasPorDia[diaStr] ?? 0) + valor;

      final formas = (dataDoc['formasPagamento'] as List<dynamic>?) ?? [];
      for (var forma in formas) {
        final f = (forma ?? '').toString();
        if (f.isEmpty) continue;
        tempFormasPagamento[f] = (tempFormasPagamento[f] ?? 0) + 1;
      }

      tempVendasPorFuncionario[funcionario] =
          (tempVendasPorFuncionario[funcionario] ?? 0) + valor;

      if (_mesmoDia(data, agora)) somaHoje += valor;
      somaMes += valor;
      vendasTotal++;

      // custo (valorReal * quantidade)
      final itens = dataDoc['itens'] as List<dynamic>? ?? [];
      for (var item in itens) {
        final vReal = _toDouble(item['valorReal']);
        final qtd = (item['quantidade'] ?? 1).toInt();
        valorGastoTotal += vReal * qtd;
      }

      // ======= VENDAS POR CATEGORIA =======
      for (var item in itens) {
        final valorVenda = _toDouble(item['precoFinal']);
        final quantidade = (item['quantidade'] ?? 1).toInt();
        final total = valorVenda * quantidade;

        // 1) tenta a categoria do item (normalizada para sua lista)
        String categoria = _snapCategoriaLocal(item['categoria']?.toString());

        if (categoria != 'OUTROS') {
          // categoria válida no item: soma direto
          tempVendasPorCategoria[categoria] =
              (tempVendasPorCategoria[categoria] ?? 0) + total;
        } else {
          // 2) ficou OUTROS -> tentar resolver por codigoBarras depois (em lote)
          final codigo =
              (item['codigoBarras'] ?? item['codigo'] ?? item['barcode'] ?? '')
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

        for (final d in qs.docs) {
          final data = d.data();
          final cod = (data['codigoBarras'] ?? '').toString().trim();
          if (cod.isEmpty) continue;

          final cat = _snapCategoriaLocal(data['categoria']?.toString());
          final soma = pendentesPorCodigo[cod] ?? 0.0;

          tempVendasPorCategoria[cat] =
              (tempVendasPorCategoria[cat] ?? 0) + soma;

          resolvidos.add(cod);
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

    final lucroCalculado = somaMes - valorGastoTotal;

    setState(() {
      totalHoje = somaHoje;
      totalMes = somaMes;
      totalVendas = vendasTotal;
      vendasPorDia = Map.from(tempVendasPorDia);
      formasPagamento = Map.from(tempFormasPagamento);
      vendasPorFuncionario = Map.from(tempVendasPorFuncionario);
      lucro = lucroCalculado;
      vendasPorCategoria = Map.from(tempVendasPorCategoria);

      // gráficos/contadores de canceladas
      canceladasPorDia = Map.from(tempCanceladasPorDia);
      canceladasPorMotivo = Map.from(tempCanceladasPorMotivo);
    });
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
      body: RefreshIndicator(
        onRefresh: carregarEstatisticas,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      dataInicio != null && dataFim != null
                          ? "${DateFormat('dd/MM/yyyy').format(dataInicio!)} - ${DateFormat('dd/MM/yyyy').format(dataFim!)}"
                          : "Selecionar Datas",
                      style: const TextStyle(color: Colors.white),
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
                  child: _buildPieChartPagamentos(showLegend: true),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildKpiCard("Hoje", totalHoje, Colors.green), // dinheiro (padrão)
        _buildKpiCard("Mês", totalMes, Colors.blue), // dinheiro
        _buildKpiCard(
          "Valor Gasto",
          valorGastoTotal,
          Colors.orange,
        ), // dinheiro
        _buildKpiCard(
          "Lucro",
          lucro,
          const Color.fromARGB(255, 51, 143, 159),
        ), // dinheiro
        _buildKpiCard(
          "Vendas",
          totalVendas,
          Colors.purple,
          isMoney: false,
        ), // inteiro
        _buildKpiCard(
          "Canceladas",
          totalCanceladas,
          Colors.red,
          isMoney: false,
        ), // inteiro
      ],
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

  Widget _buildPieChartPagamentos({bool showLegend = true}) {
    if (formasPagamento.isEmpty) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    // Ordena por quantidade (desc) e agrupa o resto em "Outras"
    const int maxSlices = 6; // 5 maiores + "Outras"
    final entries = formasPagamento.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final List<MapEntry<String, int>> main = entries
        .take(maxSlices - 1)
        .toList();
    final int others = entries
        .skip(maxSlices - 1)
        .fold(0, (s, e) => s + e.value);

    final List<MapEntry<String, int>> toPlot = [
      ...main,
      if (others > 0) const MapEntry('Outras', 0),
    ];
    if (others > 0) {
      toPlot[toPlot.length - 1] = MapEntry('Outras', others);
    }

    final int total = toPlot.fold(0, (s, e) => s + e.value);
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
              centerSpaceRadius: 48, // donut
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
                final bool isTouched = i == _touchedIndexPagamentos;
                final bool showTitle =
                    pct >= 0.06 || isTouched; // >=6% ou tocado

                final String title = showTitle
                    ? '${e.key}\nR\$ ${(e.value).toStringAsFixed(2)}\n(${(pct * 100).toStringAsFixed(0)}%)'
                    : '';

                return PieChartSectionData(
                  value: e.value.toDouble(),
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

  Widget _buildLegendPagamentos(List<MapEntry<String, int>> data, int total) {
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
              '${e.key}: R\$ ${(e.value).toStringAsFixed(2)} (${pct.toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      }).toList(),
    );
  }

  Color _getColorForPayment(String forma) {
    switch (forma.toLowerCase()) {
      case 'pix':
        return Colors.green;
      case 'dinheiro':
        return Colors.orange;
      case 'cartão':
      case 'cartao':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

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
