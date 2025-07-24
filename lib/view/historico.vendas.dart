// ignore_for_file: unnecessary_to_list_in_spreads, avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

class HistoricoVendasView extends StatefulWidget {
  const HistoricoVendasView({super.key});

  @override
  State<HistoricoVendasView> createState() => _HistoricoVendasViewState();
}

class _HistoricoVendasViewState extends State<HistoricoVendasView> {
  String filtroSelecionado = 'dia';
  DateTimeRange? intervaloPersonalizado;
  final List<String> filtros = ['dia', 'semana', 'mes', 'ano', 'personalizado'];
  String? filtroUsuario;
  String? filtroFormaPagamento;
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';
  bool carregandoUsuario = true;
  String? usuarioSelecionado;
  String? formaPagamentoSelecionada;
  String? usuarioSelecionadoId;
  List<Map<String, dynamic>> funcionarios = [];

  List<String> usuarios = []; // preenchido do Firestore
  List<String> formasPagamento = [
    'Dinheiro',
    'Pix',
    'Cartão Crédito',
    'Cartão Débito',
  ];
  Future<void> carregarFuncionarios() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('tipo', whereIn: ['funcionario', 'admin'])
        .get();

    setState(() {
      funcionarios = snapshot.docs.map((doc) {
        return {'id': doc.id, 'nome': doc['nomeUsuario']};
      }).toList();
    });
  }

  Future<void> buscarTipoUsuario() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user!.uid)
          .get();
      setState(() {
        tipoUsuario = doc['tipo'] ?? 'funcionario';
        nomeUsuario = doc['nome'] ?? '';
        carregandoUsuario = false;
      });
    }
  }

  DateTime _getDataInicial() {
    final agora = DateTime.now();
    switch (filtroSelecionado) {
      case 'semana':
        return agora.subtract(Duration(days: agora.weekday - 1));
      case 'mes':
        return DateTime(agora.year, agora.month);
      case 'ano':
        return DateTime(agora.year);
      case 'personalizado':
        return intervaloPersonalizado?.start ?? agora;
      default:
        return DateTime(agora.year, agora.month, agora.day);
    }
  }

  void _mostrarDetalhesVenda(Map<String, dynamic> venda) {
    final itens = List<Map<String, dynamic>>.from(venda['itens'] ?? []);
    final cliente = venda['cliente']?['nome'] ?? 'Não informado';
    final telefone = venda['cliente']?['telefone'] ?? '';
    final dataVenda = (venda['dataVenda'] as Timestamp).toDate();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Detalhes da Venda'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cliente: $cliente'),
                if (telefone.isNotEmpty) Text('Telefone: $telefone'),
                Text(
                  'Data: ${DateFormat('dd/MM/yyyy HH:mm').format(dataVenda)}',
                ),
                Text(
                  "Atendente: ${venda['funcionarioNome'] ?? 'Desconhecido'}",
                ),
                const SizedBox(height: 10),
                const Text(
                  'Itens:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                ...itens.map((item) {
                  final precoFinal = item['precoFinal'] ?? 0.0;
                  final quantidade = item['quantidade'] ?? 1;
                  final desconto = item['desconto'];
                  final precoPromocional = item['precoPromocional'];
                  final totalItem = precoFinal * quantidade;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['produtoNome'] ?? 'Produto'}'
                        ' ${item['tamanho']?.toString().isNotEmpty == true ? '(${item['tamanho']})' : ''}',
                      ),
                      Text(
                        'Quantidade: $quantidade | Unitário: R\$ ${precoFinal.toStringAsFixed(2)}'
                        '${desconto != null ? ' | Desconto: R\$ ${desconto.toStringAsFixed(2)}' : ''}'
                        '${precoPromocional != null && precoPromocional > 0 ? ' | Promo: R\$ ${precoPromocional.toStringAsFixed(2)}' : ''}',
                      ),
                      Text('Subtotal: R\$ ${totalItem.toStringAsFixed(2)}'),
                      const Divider(),
                    ],
                  );
                }),
                const SizedBox(height: 10),
                Text(
                  'Frete: R\$ ${venda['frete']?.toStringAsFixed(2) ?? '0.00'}',
                ),

                Text(
                  'Total da Venda: R\$ ${venda['totalVenda']?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Total com Frete: R\$ ${((venda['totalVenda'] ?? 0.0) + (venda['frete'] ?? 0.0)).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Total Pago: R\$ ${venda['totalPago']?.toStringAsFixed(2) ?? '0.00'}',
                ),
                Text(
                  'Troco: R\$ ${venda['troco']?.toStringAsFixed(2) ?? '0.00'}',
                ),
                Text(
                  'Forma de Pagamento: ${(venda['formasPagamento'] as List<dynamic>).join(" / ")}',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _imprimirNotaVenda(venda); // Chama a impressão
            },
            child: const Text('Imprimir 2ª Via'),
          ),
        ],
      ),
    );
  }

  Stream<List<DocumentSnapshot>> _getVendasStream() {
    final DateTime dataInicial = _getDataInicial();
    final DateTime dataFinal = _getDataFinal();

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('vendas')
        .where('dataVenda', isGreaterThanOrEqualTo: dataInicial)
        .where('dataVenda', isLessThanOrEqualTo: dataFinal)
        .orderBy('dataVenda', descending: true);

    // Filtro por funcionário
    if (usuarioSelecionadoId != null) {
      query = query.where('funcionarioId', isEqualTo: usuarioSelecionadoId);
    }

    return query.snapshots().map((snapshot) {
      final docsFiltrados = snapshot.docs.where((doc) {
        final data = doc.data();

        // Filtro por forma de pagamento (cliente)
        if (formaPagamentoSelecionada != null) {
          final pagamentos = (data['pagamentos'] as List?)
              ?.map((e) => e['forma']?.toString())
              .toList();
          if (pagamentos == null ||
              !pagamentos.contains(formaPagamentoSelecionada)) {
            return false;
          }
        }

        return true;
      }).toList();

      return docsFiltrados;
    });
  }

  Future<void> _selecionarIntervaloDatas() async {
    final hoje = DateTime.now();
    final intervalo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(hoje.year, hoje.month, hoje.day + 1),
      initialDateRange:
          intervaloPersonalizado ??
          DateTimeRange(
            start: DateTime(hoje.year, hoje.month, hoje.day),
            end: DateTime(hoje.year, hoje.month, hoje.day),
          ),
    );

    if (intervalo != null) {
      setState(() {
        intervaloPersonalizado = intervalo;
      });
    }
  }

  DateTime _getDataFinal() {
    final agora = DateTime.now();
    final base = filtroSelecionado == 'personalizado'
        ? intervaloPersonalizado?.end ?? agora
        : agora;

    return DateTime(base.year, base.month, base.day, 23, 59, 59);
  }

  Future<void> _selecionarIntervaloPersonalizado() async {
    DateTime dataInicialTemp = _getDataInicial();
    DateTime dataFinalTemp = _getDataFinal();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Selecionar período'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Início: ${DateFormat('dd/MM/yyyy').format(dataInicialTemp)}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final data = await showDatePicker(
                    context: context,
                    initialDate: dataInicialTemp,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                    locale: const Locale('pt', 'BR'),
                  );
                  if (data != null) setState(() => dataInicialTemp = data);
                },
              ),
              ListTile(
                title: Text(
                  'Fim: ${DateFormat('dd/MM/yyyy').format(dataFinalTemp)}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final data = await showDatePicker(
                    context: context,
                    initialDate: dataFinalTemp,
                    firstDate: dataInicialTemp,
                    lastDate: DateTime.now(),
                    locale: const Locale('pt', 'BR'),
                  );
                  if (data != null) setState(() => dataFinalTemp = data);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  intervaloPersonalizado = DateTimeRange(
                    start: dataInicialTemp,
                    end: dataFinalTemp,
                  );
                  filtroSelecionado = 'personalizado';
                });
                Navigator.pop(context);
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: filtros.map((filtro) {
          final isSelecionado = filtroSelecionado == filtro;
          final isPersonalizado = filtro == 'personalizado';
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () async {
                if (isPersonalizado) {
                  await _selecionarIntervaloPersonalizado();
                } else {
                  setState(() => filtroSelecionado = filtro);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelecionado ? Colors.purple[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelecionado ? Colors.purple : Colors.grey,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPersonalizado ? Icons.date_range : Icons.filter_alt,
                      size: 18,
                      color: isSelecionado ? Colors.purple : Colors.grey[700],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPersonalizado
                          ? intervaloPersonalizado != null
                                ? '${DateFormat('dd/MM').format(intervaloPersonalizado!.start)} - ${DateFormat('dd/MM').format(intervaloPersonalizado!.end)}'
                                : 'Personalizado'
                          : filtro.toUpperCase(),
                      style: TextStyle(
                        fontWeight: isSelecionado
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelecionado ? Colors.purple : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFiltrosExtras() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Usuário'),
              value: filtroUsuario,
              onChanged: (value) => setState(() => filtroUsuario = value),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                ...usuarios.map(
                  (u) => DropdownMenuItem(value: u, child: Text(u)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Forma Pagamento'),
              value: filtroFormaPagamento,
              onChanged: (value) =>
                  setState(() => filtroFormaPagamento = value),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                ...formasPagamento.map(
                  (f) => DropdownMenuItem(value: f, child: Text(f)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _imprimirNotaVenda(Map<String, dynamic> venda) {
    final pdf = pw.Document();
    final cliente = venda['cliente']?['nome'] ?? 'CONSUMIDOR';
    final telefone = venda['cliente']?['telefone'] ?? '';
    final dataVenda = (venda['dataVenda'] as Timestamp).toDate();
    final itens = List<Map<String, dynamic>>.from(venda['itens'] ?? []);
    final formasPagamento = (venda['formasPagamento'] as List).join(" / ");
    final frete = venda['frete'] ?? 0.0;
    final total = venda['totalVenda'] ?? 0.0;

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "SENHORITA CINTAS",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              "COMPROVANTE DE VENDA",
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text("Atendente: ${venda['nomeUsuario']}"),
            pw.Text("Cliente: $cliente"),
            if (telefone.isNotEmpty) pw.Text("Telefone: $telefone"),
            pw.Text(
              "Data: ${DateFormat('dd/MM/yyyy HH:mm').format(dataVenda)}",
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              "Itens:",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(),
            ...itens.map((item) {
              final quantidade = item['quantidade'] ?? 1;
              final precoFinal = item['precoFinal'] ?? 0.0;
              final desconto = item['desconto'] ?? 0.0;
              final precoPromocional = item['precoPromocional'] ?? 0.0;
              final totalItem = precoFinal * quantidade;

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (desconto > 0 || precoPromocional > 0)
                    pw.Text(
                      ">> PRODUTO EM PROMOÇÃO <<",
                      style: pw.TextStyle(
                        color: PdfColors.red,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  pw.Text(
                    "${item['produtoNome']} ${item['tamanho']?.toString().isNotEmpty == true ? '(${item['tamanho']})' : ''}",
                  ),
                  pw.Text(
                    "Quantidade: $quantidade - Unitário: R\$ ${precoFinal.toStringAsFixed(2)}"
                    "${desconto > 0 ? ' | Desc: R\$ ${desconto.toStringAsFixed(2)}' : ''}"
                    "${precoPromocional > 0 ? ' | Promo: R\$ ${precoPromocional.toStringAsFixed(2)}' : ''}",
                  ),
                  pw.Text("Subtotal: R\$ ${totalItem.toStringAsFixed(2)}"),
                  pw.Divider(),
                ],
              );
            }),
            pw.SizedBox(height: 10),
            pw.Text("Frete: R\$ ${frete.toStringAsFixed(2)}"),
            pw.Text(
              "Total da Venda: R\$ ${venda['totalVenda']?.toStringAsFixed(2) ?? '0.00'}",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              "Total com Frete: R\$ ${(total + frete).toStringAsFixed(2)}",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              "Total Pago: R\$ ${venda['totalPago']?.toStringAsFixed(2) ?? '0.00'}",
            ),
            pw.Text(
              "Troco: R\$ ${venda['troco']?.toStringAsFixed(2) ?? '0.00'}",
            ),
            pw.SizedBox(height: 10),
            pw.Text("Forma de Pagamento: $formasPagamento"),
            pw.SizedBox(height: 10),
            pw.Text(
              "Obrigada pela preferência!",
              style: pw.TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );

    Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Widget _buildVendaCard(Map<String, dynamic> venda, int index) {
    final total = venda['total'] ?? 0;
    final data = DateTime.tryParse(venda['dataVenda'] ?? '');
    final itens = venda['itens'] as List<dynamic>? ?? [];
    final cliente = venda['cliente'] ?? 'Não informado';
    final frete = venda['frete'] ?? 0.0;
    final nomeUsuario = venda['funcionarioNome'] ?? 'Desconhecido';
    final pagamentos = venda['pagamentos'] as List<dynamic>? ?? [];
    final formaPagamento = pagamentos.isNotEmpty
        ? pagamentos
              .map(
                (p) =>
                    '${p['forma']}: R\$ ${(p['valor'] ?? 0).toStringAsFixed(2)}',
              )
              .join(' | ')
        : 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: Text(
          'Venda ${index + 1} - R\$ ${total.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          data != null
              ? DateFormat('dd/MM/yyyy – HH:mm').format(data)
              : 'Data inválida',
          style: const TextStyle(color: Colors.grey),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👤 Cliente: $cliente'),
                Text('🚚 Frete: R\$ ${frete.toStringAsFixed(2)}'),
                Text('👩‍💼 Usuário: $nomeUsuario'),
                Text('💳 Pagamentos: $formaPagamento'),
                const Divider(),
                const Text(
                  'Itens:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ...itens.map((item) {
            return ListTile(
              leading: const Icon(
                Icons.shopping_bag_outlined,
                color: Colors.purple,
              ),
              title: Text(item['produtoNome'] ?? 'Produto'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((item['tamanho'] ?? '').toString().isNotEmpty)
                    Text('Tamanho: ${item['tamanho']}'),
                  Text('Qtd: ${item['quantidade']}'),
                  Text(
                    'Valor unitário: R\$ ${(item['precoFinal'] ?? 0).toStringAsFixed(2)}',
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Future<void> _carregarUsuarios() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .get();
    setState(() {
      usuarios = snapshot.docs.map((doc) => doc['nome'] as String).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _carregarFiltros();
    buscarTipoUsuario();
    _carregarUsuarios();
    buscarFuncionarios();
    carregarFuncionarios();
  }

  Future<List<Map<String, dynamic>>> buscarFuncionarios() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('tipo', whereIn: ['funcionario', 'admin'])
        .get();

    return snapshot.docs.map((doc) {
      return {'id': doc.id, 'nome': doc['nome'] ?? ''};
    }).toList();
  }

  Future<void> _carregarFiltros() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vendas')
          .get();

      final Set<String> nomes = {};
      final Set<String> formas = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();

        // Pegando o nome do usuário
        final nome = data['nomeUsuario'];
        if (nome != null && nome.toString().trim().isNotEmpty) {
          nomes.add(nome.toString().trim());
        }

        // Pegando formas de pagamento dentro da lista 'pagamentos'
        final pagamentos = data['pagamentos'];
        if (pagamentos != null && pagamentos is List) {
          for (var pagamento in pagamentos) {
            if (pagamento is Map && pagamento.containsKey('forma')) {
              final forma = pagamento['forma'];
              if (forma != null && forma.toString().trim().isNotEmpty) {
                formas.add(forma.toString().trim());
              }
            }
          }
        }
      }

      setState(() {
        usuarios = nomes.toList()..sort();
        formasPagamento = formas.toList()..sort();
      });
    } catch (e) {
      print('Erro ao carregar filtros: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Histórico de Vendas',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
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
      body: carregandoUsuario
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filtros (dia, semana, mês, personalizado)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: Colors.grey[100],
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: filtros.map((filtro) {
                      final isSelecionado = filtroSelecionado == filtro;
                      return ChoiceChip(
                        label: Text(
                          filtro == 'personalizado'
                              ? 'Personalizado'
                              : filtro[0].toUpperCase() + filtro.substring(1),
                          style: TextStyle(
                            color: isSelecionado ? Colors.white : Colors.black,
                          ),
                        ),
                        selected: isSelecionado,
                        selectedColor: primaryColor,
                        onSelected: (selected) async {
                          if (selected) {
                            if (filtro == 'personalizado') {
                              await _selecionarIntervaloDatas();
                            }
                            setState(() => filtroSelecionado = filtro);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),

                // Exibe intervalo de data se for personalizado
                if (filtroSelecionado == 'personalizado' &&
                    intervaloPersonalizado != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${DateFormat('dd/MM/yyyy').format(intervaloPersonalizado!.start)} até '
                          '${DateFormat('dd/MM/yyyy').format(intervaloPersonalizado!.end)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      // Filtro por Funcionário
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: usuarioSelecionado,
                          items: funcionarios.map((usuario) {
                            return DropdownMenuItem<String>(
                              value: usuario['nome'], // salva o nome
                              child: Text(usuario['nome']),
                            );
                          }).toList(),
                          onChanged: (String? novoValor) {
                            setState(() {
                              usuarioSelecionado = novoValor;

                              // Encontra o funcionário correspondente pelo nome
                              final funcionario = funcionarios.firstWhere(
                                (f) => f['nome'] == novoValor,
                                orElse: () => {'id': null, 'nome': ''},
                              );

                              // Pega o ID se existir
                              usuarioSelecionadoId = funcionario != null
                                  ? funcionario['id']
                                  : null;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Funcionário',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Filtro por Forma de Pagamento
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: formaPagamentoSelecionada,
                          decoration: const InputDecoration(
                            labelText: 'Pagamento',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Todas'),
                            ),
                            ...formasPagamento.map(
                              (fp) =>
                                  DropdownMenuItem(value: fp, child: Text(fp)),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              formaPagamentoSelecionada = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de vendas
                Expanded(
                  child:
                      StreamBuilder<
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>
                      >(
                        stream: _getVendasStream().map(
                          (vendas) => vendas
                              .map(
                                (doc) =>
                                    doc
                                        as QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >,
                              )
                              .toList(),
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(
                              child: Text('Nenhuma venda encontrada.'),
                            );
                          }

                          final vendas = snapshot.data!;

                          return ListView.builder(
                            itemCount: vendas.length,
                            itemBuilder: (context, index) {
                              final venda = vendas[index].data();
                              DateTime dataVenda;

                              final rawData = venda['dataVenda'];

                              if (rawData is Timestamp) {
                                dataVenda = rawData.toDate();
                              } else if (rawData is String) {
                                dataVenda =
                                    DateTime.tryParse(rawData) ??
                                    DateTime.now();
                              } else {
                                dataVenda = DateTime.now(); // fallback seguro
                              }

                              final cliente =
                                  venda['cliente']?['nome'] ??
                                  'Cliente não informado';
                              final valor = venda['totalVenda'] is int
                                  ? (venda['totalVenda'] as int).toDouble()
                                  : venda['totalVenda'] ?? 0.0;

                              return Card(
                                elevation: 2,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  title: Text(
                                    'R\$ ${valor.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        cliente,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        DateFormat(
                                          'dd/MM/yyyy – HH:mm',
                                        ).format(dataVenda),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.receipt_long_rounded,
                                      color: Colors.purple,
                                    ),
                                    onPressed: () {
                                      _mostrarDetalhesVenda(venda);
                                    },
                                  ),
                                  onTap: () {
                                    _mostrarDetalhesVenda(venda);
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                ),
              ],
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
