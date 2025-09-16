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
import 'package:diacritic/diacritic.dart';

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
  String? funcionarioSelecionado;
  String? formaPagamentoSelecionada;
  List<String> listaUsuarios = []; // preenchido do Firestore
  List<String> listaFormasPagamento = []; // preenchido do Firestore

  List<String> usuarios = []; // preenchido do Firestore
  List<String> formasPagamento = ['Dinheiro', 'Pix', 'Crédito', 'Débito'];

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

  void _mostrarDetalhesVenda(Map<String, dynamic> venda, String vendaId) {
    final itens = List<Map<String, dynamic>>.from(venda['itens'] ?? []);
    final cliente = venda['cliente']?['nome'] ?? 'Não informado';
    final telefone = venda['cliente']?['telefone'] ?? '';
    final dataVenda = (venda['dataVenda'] as Timestamp).toDate();
    final bool jaCancelada =
        (venda['cancelada'] == true) ||
        ((venda['status'] ?? '') == 'cancelada');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(jaCancelada ? 'Venda (CANCELADA)' : 'Detalhes da Venda'),
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
                Text("Atendente: ${venda['funcionario'] ?? 'Não informado'}"),
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
          if (!jaCancelada /* && tipoUsuario == 'admin' */ )
            TextButton(
              onPressed: () async {
                Navigator.pop(context); // fecha detalhes
                _confirmarCancelamento(vendaId, venda); // <<<<<<<<<<<<<<
              },
              child: const Text(
                'Cancelar venda',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _imprimirNotaVenda(venda);
            },
            child: const Text('Imprimir 2ª Via'),
          ),
        ],
      ),
    );
  }

  Stream<List<DocumentSnapshot>> _getVendasStream() {
    final dataInicial = _getDataInicial();
    final dataFinal = _getDataFinal().add(
      const Duration(hours: 23, minutes: 59, seconds: 59),
    );

    Query query = FirebaseFirestore.instance
        .collection('vendas')
        .where('dataVenda', isGreaterThanOrEqualTo: dataInicial)
        .where('dataVenda', isLessThanOrEqualTo: dataFinal)
        .orderBy('dataVenda', descending: true);

    return query.snapshots().map((snapshot) {
      final docsFiltrados = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;

        if (data == null) return false;

        // Filtro por funcionário
        if (funcionarioSelecionado != null &&
            funcionarioSelecionado!.trim().isNotEmpty) {
          final funcionario = removeDiacritics(
            data['funcionario']?.toString().toLowerCase().trim() ?? '',
          );
          final filtroFuncionario = removeDiacritics(
            funcionarioSelecionado!.toLowerCase().trim(),
          );
          if (funcionario != filtroFuncionario) return false;
        }

        // Filtro por forma de pagamento
        if (formaPagamentoSelecionada != null &&
            formaPagamentoSelecionada!.trim().isNotEmpty) {
          final pagamentos = data['pagamentos'] as List?;
          final formas = pagamentos
              ?.whereType<Map>()
              .map(
                (e) => removeDiacritics(
                  e['forma']?.toString().toLowerCase().trim() ?? '',
                ),
              )
              .toList();

          final formaSelecionadaNormalizada = removeDiacritics(
            formaPagamentoSelecionada!.toLowerCase().trim(),
          );

          if (formas == null || !formas.contains(formaSelecionadaNormalizada)) {
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
    return filtroSelecionado == 'personalizado'
        ? intervaloPersonalizado?.end ?? agora
        : agora;
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
              pw.Text("Telefone: $telefone", style: pw.TextStyle(fontSize: 8)),
            pw.Text(
              "Data: ${DateFormat('dd/MM/yyyy HH:mm').format(dataVenda)}",
              style: pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              "Itens:",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            ),
            pw.Divider(height: 1),
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
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              "Total com Frete: R\$ ${(total + frete).toStringAsFixed(2)}",
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              "Total Pago: R\$ ${venda['totalPago']?.toStringAsFixed(2) ?? '0.00'}",
              style: pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              "Troco: R\$ ${venda['troco']?.toStringAsFixed(2) ?? '0.00'}",
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

    Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Widget _buildVendaCard(Map<String, dynamic> venda, int index) {
    final total = venda['total'] ?? 0;
    final data = DateTime.tryParse(venda['dataVenda'] ?? '');
    final itens = venda['itens'] as List<dynamic>? ?? [];
    final cliente = venda['cliente'] ?? 'Não informado';
    final frete = venda['frete'] ?? 0.0;
    final funcionarioSelecionado =
        venda['funcionario']?['nome'] ?? 'Não informado';
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
                Text('👩‍💼 Funcionario: $funcionarioSelecionado'),
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
    buscarFuncionarios().then((funcionarios) {
      setState(() {
        usuarios = funcionarios;
      });
    });
  }

  Future<List<String>> buscarFuncionarios() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('tipo', whereIn: ['funcionario', 'admin'])
        .get();

    return snapshot.docs.map((doc) => doc['nomeUsuario'] as String).toList();
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

        // Pegando o nome do funcionário
        final nome = data['funcionario'];
        if (nome != null && nome.toString().trim().isNotEmpty) {
          nomes.add(removeDiacritics(nome.toString().toLowerCase().trim()));
        }

        // Pegando formas de pagamento dentro da lista 'pagamentos'
        final pagamentos = data['pagamentos'];
        if (pagamentos != null && pagamentos is List) {
          for (var pagamento in pagamentos) {
            if (pagamento is Map && pagamento.containsKey('forma')) {
              final forma = pagamento['forma'];
              if (forma != null && forma.toString().trim().isNotEmpty) {
                formas.add(
                  removeDiacritics(forma.toString().toLowerCase().trim()),
                );
              }
            }
          }
        }
      }

      setState(() {
        listaUsuarios = nomes.toList();
        listaFormasPagamento = formas.toList();
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
                        child: DropdownButtonFormField<String?>(
                          value: funcionarioSelecionado,
                          decoration: const InputDecoration(
                            labelText: 'Funcionário',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            ...usuarios.map(
                              (nome) => DropdownMenuItem<String?>(
                                value: nome,
                                child: Text(nome),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              funcionarioSelecionado = value;
                            });
                          },
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
                              final vendaDoc = vendas[index];
                              final venda = vendaDoc.data();

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
                                      _mostrarDetalhesVenda(venda, vendaDoc.id);
                                    },
                                  ),
                                  onTap: () {
                                    _mostrarDetalhesVenda(venda, vendaDoc.id);
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

  void _confirmarCancelamento(
    String vendaId,
    Map<String, dynamic> venda,
  ) async {
    final motivoCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cancelamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tem certeza que deseja cancelar esta venda? '
              'O estoque dos itens será devolvido.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _cancelarVenda(vendaId, venda, motivoCtrl.text.trim());
    }
  }

  String _normKey(String s) =>
      removeDiacritics(s.trim().toUpperCase()).replaceAll(RegExp(r'\s+'), '');

  String? _resolveProdutoIdBruto(Map<String, dynamic> item) {
    // tenta várias formas comuns de vir o id do produto no item
    final cands = <dynamic>[
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

  /// casa a chave exata do mapa 'tamanhos' do produto com o valor vindo do item
  String? _resolverChaveTamanhoExistente(
    Map<String, dynamic> tamanhosProduto,
    String tamItem,
  ) {
    if (tamItem.trim().isEmpty) return null;

    // 1) match exato
    if (tamanhosProduto.containsKey(tamItem)) return tamItem;

    // 2) case-insensitive
    final up = tamItem.trim().toUpperCase();
    for (final k in tamanhosProduto.keys) {
      if (k.toString().trim().toUpperCase() == up) return k.toString();
    }

    // 3) fuzzy (sem acentos/espaços)
    final alvo = _normKey(tamItem);
    for (final k in tamanhosProduto.keys) {
      if (_normKey(k.toString()) == alvo) return k.toString();
    }

    return null; // não achou
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
          .limit(1)
          .get();
      if (qs.docs.isNotEmpty) return qs.docs.first.id;
    }

    // 2) tenta por nome (+ cor/loja se disponíveis, para diminuir ambiguidades)
    final nome = (item['produtoNome'] ?? item['nome'] ?? '').toString().trim();
    if (nome.isNotEmpty) {
      Query q = FirebaseFirestore.instance
          .collection('produtos')
          .where('nome', isEqualTo: nome.toUpperCase());

      final cor = (item['cor'] ?? '').toString().trim();
      final loja = (item['loja'] ?? '').toString().trim();

      if (cor.isNotEmpty) q = q.where('cor', isEqualTo: cor);
      if (loja.isNotEmpty) q = q.where('loja', isEqualTo: loja);

      final qs = await q.limit(1).get();
      if (qs.docs.isNotEmpty) return qs.docs.first.id;
    }

    return null; // não encontrado
  }

  Future<void> _cancelarVenda(
    String vendaId,
    Map<String, dynamic> venda,
    String? motivo,
  ) async {
    try {
      if (venda['cancelada'] == true ||
          (venda['status'] ?? '') == 'cancelada') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta venda já está cancelada.')),
        );
        return;
      }

      final itens = List<Map<String, dynamic>>.from(venda['itens'] ?? const []);
      if (itens.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venda sem itens — nada a repor.')),
        );
        return;
      }

      // Vamos acumular os increments por produto e por tamanho
      final updatesPorProduto = <String, Map<String, dynamic>>{};
      // { produtoId: { 'qtdTotal': int, 'porTamanho': { 'PP': int, ... } } }

      for (final item in itens) {
        // 1) quantidade
        final int qty = _resolveQtd(item['quantidade'] ?? item['qtd']);
        if (qty <= 0) {
          debugPrint('[cancelar] Item ignorado: quantidade inválida => $item');
          continue;
        }

        // 2) produtoId (várias chaves) ou descobrir via consulta
        String? produtoId = _resolveProdutoIdBruto(item);
        if (produtoId == null) {
          produtoId = await _descobrirProdutoIdViaConsulta(item);
        }
        if (produtoId == null) {
          debugPrint(
            '[cancelar] NÃO FOI POSSÍVEL ENCONTRAR produtoId p/ item => $item',
          );
          continue;
        }

        // 3) tamanho bruto (se houver)
        final tamBruto = _resolveTamanhoBruto(item);

        // 4) ler produto para casar a chave de tamanho correta
        final produtoRef = FirebaseFirestore.instance
            .collection('produtos')
            .doc(produtoId);
        final produtoSnap = await produtoRef.get();
        if (!produtoSnap.exists) {
          debugPrint('[cancelar] Produto não existe: $produtoId (item: $item)');
          continue;
        }
        final prod = produtoSnap.data() as Map<String, dynamic>;
        final tamanhosProduto = Map<String, dynamic>.from(
          prod['tamanhos'] ?? const {},
        );

        String? chaveTamanho;
        if (tamBruto != null && tamBruto.trim().isNotEmpty) {
          chaveTamanho =
              _resolverChaveTamanhoExistente(tamanhosProduto, tamBruto)
              // se não achou no produto, padroniza e cria
              ??
              tamBruto.trim().toUpperCase();
        }

        // 5) acumula increments
        updatesPorProduto.putIfAbsent(
          produtoId,
          () => {'qtdTotal': 0, 'porTamanho': <String, int>{}},
        );

        updatesPorProduto[produtoId]!['qtdTotal'] =
            (updatesPorProduto[produtoId]!['qtdTotal'] as int) + qty;

        if (chaveTamanho != null && chaveTamanho.isNotEmpty) {
          final mapSizes =
              (updatesPorProduto[produtoId]!['porTamanho'] as Map<String, int>);
          mapSizes[chaveTamanho] = (mapSizes[chaveTamanho] ?? 0) + qty;
        }
      }

      if (updatesPorProduto.isEmpty) {
        // ➜ Foi aqui que seu código caiu antes
        // Agora deixamos pistas no log para você ver qual item não tinha produtoId/qtd
        debugPrint('[cancelar] Nenhum update acumulado. Revise os logs acima.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nada a repor nesta venda.')),
        );
        return;
      }

      // 6) aplica em batch
      final batch = FirebaseFirestore.instance.batch();

      updatesPorProduto.forEach((produtoId, payload) {
        final produtoRef = FirebaseFirestore.instance
            .collection('produtos')
            .doc(produtoId);

        final qtdTotal = payload['qtdTotal'] as int;
        batch.update(produtoRef, {
          'quantidade': FieldValue.increment(qtdTotal),
        });

        final porTamanho = payload['porTamanho'] as Map<String, int>;
        porTamanho.forEach((chave, inc) {
          batch.update(produtoRef, {
            'tamanhos.$chave': FieldValue.increment(inc),
          });
        });

        // (Opcional) se mantém espelho em "estoque"
        final estoqueRef = FirebaseFirestore.instance
            .collection('estoque')
            .doc(produtoId);
        batch.set(estoqueRef, {
          'idProduto': produtoId,
          'quantidade': FieldValue.increment(qtdTotal),
          if (porTamanho.isNotEmpty)
            ...porTamanho.map(
              (k, v) => MapEntry('tamanhos.$k', FieldValue.increment(v)),
            ),
        }, SetOptions(merge: true));
      });

      // marcar venda como cancelada
      final vendaRef = FirebaseFirestore.instance
          .collection('vendas')
          .doc(vendaId);
      batch.update(vendaRef, {
        'cancelada': true,
        'status': 'cancelada',
        'canceladaEm': FieldValue.serverTimestamp(),
        'canceladaPorUid': user?.uid,
        'canceladaPorNome': nomeUsuario,
        if (motivo != null && motivo.isNotEmpty) 'motivoCancelamento': motivo,
      });

      await batch.commit();

      await vendaRef.collection('logs').add({
        'tipo': 'cancelamento',
        'quando': FieldValue.serverTimestamp(),
        'quemUid': user?.uid,
        'quemNome': nomeUsuario,
        'motivo': motivo ?? '',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Venda cancelada e estoque restabelecido.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, st) {
      debugPrint('Erro ao cancelar venda: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao cancelar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
  return ListTile(
    leading: Icon(icon, color: Colors.white),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    onTap: onTap,
  );
}
