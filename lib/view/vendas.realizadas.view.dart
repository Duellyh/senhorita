import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class VendasRealizadasView extends StatefulWidget {
  const VendasRealizadasView({super.key});

  @override
  State<VendasRealizadasView> createState() => _VendasRealizadasViewState();
}

class _VendasRealizadasViewState extends State<VendasRealizadasView> {
  String filtroSelecionado = 'dia';
  DateTimeRange? intervaloPersonalizado;
  final user = FirebaseAuth.instance.currentUser;
  String tipoUsuario = '';
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  List<String> filtros = ['dia', 'semana', 'mes', 'ano', 'personalizado'];
  double frete = 0.0;
  final List<Map<String, dynamic>> pagamentos = [];
  String nomeUsuario = '';
  final TextEditingController clienteNomeController = TextEditingController();
  final List<Map<String, dynamic>> itensVendidos = [];
  bool carregandoUsuario = true;

  @override
  void initState() {
    super.initState();
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
        nomeUsuario = doc['nome'] ?? '';
        carregandoUsuario = false;
      });
    }
  }

  DateTime _getDataInicial() {
    final agora = DateTime.now();
    switch (filtroSelecionado) {
      case 'dia':
        return DateTime(agora.year, agora.month, agora.day);
      case 'semana':
        final inicioSemana = agora.subtract(Duration(days: agora.weekday - 1));
        return DateTime(
          inicioSemana.year,
          inicioSemana.month,
          inicioSemana.day,
        );
      case 'mes':
        return DateTime(agora.year, agora.month, 1);
      case 'ano':
        return DateTime(agora.year, 1, 1);
      case 'personalizado':
        return intervaloPersonalizado?.start ?? agora;
      default:
        return agora;
    }
  }

  DateTime _getDataFinal() {
    final agora = DateTime.now();
    switch (filtroSelecionado) {
      case 'dia':
      case 'semana':
      case 'mes':
      case 'ano':
        return DateTime(agora.year, agora.month, agora.day);
      case 'personalizado':
        return intervaloPersonalizado?.end ?? agora;
      default:
        return agora;
    }
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getVendasStream() {
    final dataInicial = _getDataInicial();
    final dataFinal = _getDataFinal().add(const Duration(days: 1));

    return FirebaseFirestore.instance
        .collection('vendas')
        .orderBy('dataVenda')
        .where('dataVenda', isGreaterThanOrEqualTo: dataInicial)
        .where('dataVenda', isLessThan: dataFinal)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.where((doc) {
            final data = doc.data();
            if (tipoUsuario == 'admin') return true;
            return data['usuarioId'] == user?.uid;
          }).toList();
          return docs;
        });
  }

  Future<void> _cancelarVenda(
    String vendaId,
    Map<String, dynamic> venda,
  ) async {
    if (tipoUsuario != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ação permitida apenas para administradores.'),
        ),
      );
      return;
    }

    final itens = List<Map<String, dynamic>>.from(venda['itens'] ?? []);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        // 1) Devolve estoque para cada item
        for (final item in itens) {
          // tenta descobrir o id do produto em diferentes chaves usuais
          final produtoId =
              (item['produtoId'] ??
                      item['idProduto'] ??
                      item['produtoDocId'] ??
                      item['id']) // se você usa outra chave, ajuste aqui
                  ?.toString();

          if (produtoId == null || produtoId.isEmpty) {
            throw Exception(
              'Item sem produtoId. Ajuste o campo do item da venda.',
            );
          }

          final prodRef = FirebaseFirestore.instance
              .collection('produtos')
              .doc(produtoId);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) {
            throw Exception('Produto $produtoId não encontrado.');
          }

          final prodData = prodSnap.data() as Map<String, dynamic>;
          final int qtdVendida = (item['quantidade'] ?? 1) is int
              ? (item['quantidade'] as int)
              : int.tryParse(item['quantidade'].toString()) ?? 1;

          final String? tam = (item['tamanho']?.toString().isNotEmpty ?? false)
              ? item['tamanho'].toString()
              : null;

          final Map<String, dynamic>? tamanhos =
              (prodData['tamanhos'] is Map<String, dynamic>)
              ? Map<String, dynamic>.from(prodData['tamanhos'])
              : null;

          // Atualiza estoque
          if (tamanhos != null && tam != null) {
            final atual = (tamanhos[tam] ?? 0) is int
                ? tamanhos[tam] as int
                : int.tryParse((tamanhos[tam] ?? '0').toString()) ?? 0;
            final novoTam = atual + qtdVendida;

            // Atualiza tamanho específico
            tx.update(prodRef, {'tamanhos.$tam': novoTam});

            // Se você mantém um campo 'quantidade' total, atualize também:
            final totalAtual = (prodData['quantidade'] ?? 0) is int
                ? prodData['quantidade'] as int
                : int.tryParse((prodData['quantidade'] ?? '0').toString()) ?? 0;
            tx.update(prodRef, {'quantidade': totalAtual + qtdVendida});
          } else {
            // Produto sem variação de tamanho
            final totalAtual = (prodData['quantidade'] ?? 0) is int
                ? prodData['quantidade'] as int
                : int.tryParse((prodData['quantidade'] ?? '0').toString()) ?? 0;
            tx.update(prodRef, {'quantidade': totalAtual + qtdVendida});
          }
        }

        // 2) Remove a venda da coleção
        final vendaRef = FirebaseFirestore.instance
            .collection('vendas')
            .doc(vendaId);
        tx.delete(vendaRef);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda cancelada e estoque devolvido.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao cancelar venda: $e')));
    }
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

  double _calcularTotalGeral() {
    return itensVendidos.fold(0.0, (total, item) {
      final precoFinal = _converterParaDouble(item['precoFinal'].toString());
      return total + (precoFinal * item['quantidade']);
    });
  }

  double _converterParaDouble(String valor) {
    return double.tryParse(valor.replaceAll(',', '.')) ?? 0.0;
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
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
        pageFormat: PdfPageFormat(58 * PdfPageFormat.mm, double.infinity),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Column(
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
              pw.Center(
                child: pw.Text(
                  "COMPROVANTE DE VENDA",
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                "Atendente: ${venda['nomeUsuario'] ?? '-'}",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.Text("Cliente: $cliente", style: pw.TextStyle(fontSize: 8)),
              if (telefone.isNotEmpty)
                pw.Text(
                  "Telefone: $telefone",
                  style: pw.TextStyle(fontSize: 8),
                ),
              pw.Text(
                "Data: ${DateFormat('dd/MM/yyyy HH:mm').format(dataVenda)}",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                "Itens:",
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
              ),
              pw.Divider(thickness: 1),
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
                          fontSize: 8,
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
                    pw.Divider(thickness: 0.5),
                  ],
                );
              }),
              pw.SizedBox(height: 4),
              pw.Text(
                "Frete: R\$ ${frete.toStringAsFixed(2)}",
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                "Total da Venda: R\$ ${venda['totalVenda']?.toStringAsFixed(2) ?? '0.00'}",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                "Total com Frete: R\$ ${(total + frete).toStringAsFixed(2)}",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
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
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  "Obrigada pela preferência!",
                  style: pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Printing.layoutPdf(onLayout: (format) => pdf.save());
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
                Text('Funcionario: $nomeUsuario'),
                if (telefone.isNotEmpty) Text('Telefone: $telefone'),
                Text(
                  'Data: ${DateFormat('dd/MM/yyyy HH:mm').format(dataVenda)}',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: const Text(
          'Vendas Realizadas',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
                          '${DateFormat('dd/MM/yyyy').format(intervaloPersonalizado!.start)} até ${DateFormat('dd/MM/yyyy').format(intervaloPersonalizado!.end)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                    stream: _getVendasStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
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
                          final vendaId =
                              vendaDoc.id; // <- precisamos para excluir
                          final venda = vendaDoc.data();
                          final dataVenda = (venda['dataVenda'] as Timestamp)
                              .toDate();
                          final cliente =
                              venda['cliente']?['nome'] ??
                              'Cliente não informado';

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: ListTile(
                              title: Text(
                                'Venda - R\$ ${venda['totalVenda'].toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '$cliente - ${DateFormat('dd/MM/yyyy HH:mm').format(dataVenda)}',
                              ),
                              onTap: () => _mostrarDetalhesVenda(venda),
                              trailing: tipoUsuario == 'admin'
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.cancel,
                                        color: Colors.redAccent,
                                      ),
                                      tooltip: 'Cancelar venda',
                                      onPressed: () async {
                                        final confirma = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Cancelar venda'),
                                            content: const Text(
                                              'Tem certeza que deseja cancelar esta venda? '
                                              'O estoque será devolvido e a venda será removida.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: const Text('Não'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: const Text(
                                                  'Sim, cancelar',
                                                ),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirma == true) {
                                          await _cancelarVenda(vendaId, venda);
                                        }
                                      },
                                    )
                                  : null,
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
