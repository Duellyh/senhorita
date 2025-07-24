// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
    final agora = DateTime.now();
    final inicioFiltro = dataInicio ?? DateTime(agora.year, agora.month, 1);
    final fimFiltro = dataFim ?? DateTime.now();

    final snapshot = await FirebaseFirestore.instance
        .collection('vendas')
        .where('dataVenda', isGreaterThanOrEqualTo: inicioFiltro)
        .where('dataVenda', isLessThanOrEqualTo: fimFiltro)
        .get();

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
            pw.Text('Total de Vendas: $totalVendas'),
            pw.Text('Total do Mês: R\$ ${totalMes.toStringAsFixed(2)}'),
            pw.Text('Total de Hoje: R\$ ${totalHoje.toStringAsFixed(2)}'),
            pw.Text(
              'Valor Gasto Total: R\$ ${valorGastoTotal.toStringAsFixed(2)}',
            ),
            pw.Text('Lucro: R\$ ${lucro.toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),

            pw.Divider(),

            pw.Text(
              '🧾 Detalhes das Vendas',
              style: pw.TextStyle(fontSize: 18),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Data', 'Valor', 'Formas de Pagamento', 'Funcionário'],
              data: snapshot.docs.map((doc) {
                final data = (doc['dataVenda'] as Timestamp).toDate();
                final valor = (doc['totalVenda'] ?? 0).toDouble();
                final formas = (doc['formasPagamento'] as List).join(', ');
                final funcionario = doc['funcionario'] ?? '';
                return [
                  DateFormat('dd/MM/yyyy').format(data),
                  'R\$ ${valor.toStringAsFixed(2)}',
                  formas,
                  funcionario,
                ];
              }).toList(),
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

  Future<void> _exportarCSV() async {
    final agora = DateTime.now();
    final inicioFiltro = dataInicio ?? DateTime(agora.year, agora.month, 1);
    final fimFiltro = dataFim ?? DateTime.now();

    final snapshot = await FirebaseFirestore.instance
        .collection('vendas')
        .where('dataVenda', isGreaterThanOrEqualTo: inicioFiltro)
        .where('dataVenda', isLessThanOrEqualTo: fimFiltro)
        .get();

    List<List<dynamic>> rows = [
      ['Data', 'Valor', 'Formas Pagamento', 'Funcionário'],
    ];

    for (var doc in snapshot.docs) {
      final data = (doc['dataVenda'] as Timestamp).toDate();
      final valor = (doc['totalVenda'] ?? 0).toDouble();
      final formas = (doc['formasPagamento'] as List).join(', ');
      final funcionario = doc['funcionario'] ?? '';

      rows.add([
        DateFormat('dd/MM/yyyy').format(data),
        valor.toStringAsFixed(2),
        formas,
        funcionario,
      ]);

      final itens = doc['itens'] as List<dynamic>? ?? [];
      for (var item in itens) {
        final valorReal = (item['valorReal'] ?? 0).toDouble();
        final quantidade = (item['quantidade'] ?? 1).toInt();
        valorGastoTotal += valorReal * quantidade;
      }
    }

    String csvData = const ListToCsvConverter().convert(rows);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/relatorio_vendas.csv');

    await file.writeAsString(csvData);

    await Share.shareXFiles([XFile(file.path)], text: 'Relatório de Vendas');
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

    Map<String, double> tempVendasPorDia = {};
    Map<String, int> tempFormasPagamento = {};
    Map<String, double> tempVendasPorFuncionario = {};
    Map<String, double> tempVendasPorCategoria =
        {}; // Declarar aqui fora, uma única vez

    for (var doc in snapshot.docs) {
      final data = (doc['dataVenda'] as Timestamp).toDate();
      final valor = (doc['totalVenda'] ?? 0).toDouble();
      final funcionario = doc['funcionario'] ?? 'Desconhecido';

      // Acumula por dia
      final diaStr = DateFormat('dd/MM').format(data);
      tempVendasPorDia[diaStr] = (tempVendasPorDia[diaStr] ?? 0) + valor;

      // Acumula formas de pagamento
      final formas = (doc['formasPagamento'] as List<dynamic>?) ?? [];
      for (var forma in formas) {
        tempFormasPagamento[forma] = (tempFormasPagamento[forma] ?? 0) + 1;
      }

      // Acumula por funcionário
      tempVendasPorFuncionario[funcionario] =
          (tempVendasPorFuncionario[funcionario] ?? 0) + valor;

      // Acumula totais
      if (_mesmoDia(data, agora)) {
        somaHoje += valor;
      }

      somaMes += valor;
      vendasTotal++;

      // Calcular valor gasto (valorReal * quantidade)
      final itens = doc['itens'] as List<dynamic>? ?? [];
      for (var item in itens) {
        final valorReal = (item['valorReal'] ?? 0).toDouble();
        final quantidade = (item['quantidade'] ?? 1).toInt();
        valorGastoTotal += valorReal * quantidade;
      }

      // **Acumula as vendas por categoria dentro do mesmo mapa externo**
      for (var item in itens) {
        final categoria = item['categoria'] ?? 'Outros';

        // Atenção: use 'precoFinal', pois é o campo que você está salvando no item da venda
        final valorVenda = (item['precoFinal'] ?? 0).toDouble();
        final quantidade = (item['quantidade'] ?? 1).toInt();
        final total = valorVenda * quantidade;

        tempVendasPorCategoria[categoria] =
            (tempVendasPorCategoria[categoria] ?? 0) + total;
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
                    onPressed: _exportarCSV,
                    icon: const Icon(Icons.file_download),
                    label: const Text(
                      "Exportar CSV",
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
                    child: _BarChartContainer(data: vendasPorDia),
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
                  child: _buildPieChart(),
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
                  child: SizedBox(
                    height: 260,
                    child: _BarChartFuncionarios(data: vendasPorFuncionario),
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
        _buildKpiCard("Hoje", totalHoje, Colors.green),
        _buildKpiCard("Mês", totalMes, Colors.blue),
        _buildKpiCard("Valor Gasto", valorGastoTotal, Colors.orange),
        _buildKpiCard("Lucro", lucro, const Color.fromARGB(255, 51, 143, 159)),
        _buildKpiCard("Vendas", totalVendas.toDouble(), Colors.purple),
      ],
    );
  }

  Widget _buildPieChartCategorias() {
    if (vendasPorCategoria.isEmpty) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    return SizedBox(
      height: 220,
      child: PieChart(
        PieChartData(
          sections: vendasPorCategoria.entries.map((e) {
            final color = _getColorForCategory(e.key);
            return PieChartSectionData(
              value: e.value,
              color: color,
              title: '${e.key} \nR\$ ${e.value.toStringAsFixed(0)}',
              radius: 60,
              titleStyle: const TextStyle(fontSize: 11, color: Colors.white),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _getColorForCategory(String categoria) {
    final cores = [
      Colors.pink,
      Colors.teal,
      Colors.deepPurple,
      Colors.amber,
      Colors.indigo,
      Colors.brown,
      Colors.cyan,
      Colors.lime,
    ];
    return cores[categoria.hashCode % cores.length];
  }

  Widget _buildKpiCard(String title, double value, Color color) {
    return Expanded(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                title == "Vendas"
                    ? value.toInt().toString()
                    : "R\$ ${value.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    if (formasPagamento.isEmpty) {
      return const Center(child: Text("Sem dados suficientes"));
    }

    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sections: formasPagamento.entries.map((e) {
            final color = _getColorForPayment(e.key);
            return PieChartSectionData(
              value: e.value.toDouble(),
              color: color,
              title: '${e.key} (${e.value})',
              radius: 60,
              titleStyle: const TextStyle(fontSize: 12, color: Colors.white),
            );
          }).toList(),
        ),
      ),
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
}

class _BarChartContainer extends StatelessWidget {
  final Map<String, double> data;
  const _BarChartContainer({required this.data});

  @override
  Widget build(BuildContext context) {
    final dias = data.keys.toList();
    final valores = data.values.toList();

    if (valores.isEmpty) {
      return const Center(child: Text('Sem dados para mostrar'));
    }

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
                color: const Color.fromARGB(255, 39, 176, 105),
                width: 12,
                borderRadius: BorderRadius.circular(6),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY:
                      maxY, // aqui deve ser o maxY para desenhar fundo completo
                  color: Colors.grey[200]!,
                ),
              ),
            ],
          );
        }),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 5, // intervalo dinâmico
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
              reservedSize: 40,
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

class _BarChartFuncionarios extends StatelessWidget {
  final Map<String, double> data;
  const _BarChartFuncionarios({required this.data});

  @override
  Widget build(BuildContext context) {
    final nomes = data.keys.toList();
    final valores = data.values.toList();

    if (valores.isEmpty) {
      return const Center(child: Text('Sem dados para mostrar'));
    }

    final maxValor = valores.reduce((a, b) => a > b ? a : b);
    final maxY = (maxValor * 1.2).ceilToDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        minY: 0,
        barGroups: List.generate(nomes.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: valores[i],
                color: const Color.fromARGB(255, 255, 120, 80),
                width: 14,
                borderRadius: BorderRadius.circular(4),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: Colors.grey[200]!,
                ),
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          show: true,
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= nomes.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(nomes[i], style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
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
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 5,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.grey[300]!, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
      ),
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
