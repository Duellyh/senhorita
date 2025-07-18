// ignore_for_file: unnecessary_to_list_in_spreads, avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class HistoricoVendasView extends StatefulWidget {
  const HistoricoVendasView({super.key});

  @override
  State<HistoricoVendasView> createState() => _HistoricoVendasViewState();
}

class _HistoricoVendasViewState extends State<HistoricoVendasView> {
  String filtroSelecionado = 'dia';
  DateTimeRange? intervaloPersonalizado;
  final List<String> filtros = ['dia', 'semana', 'mes', 'ano', 'personalizado'];
  List<String> usuarios = [];
  List<String> formasPagamento = [];
  String? filtroUsuario;
  String? filtroFormaPagamento;
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';




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

  DateTime _getDataFinal() {
    final agora = DateTime.now();
    return filtroSelecionado == 'personalizado'
        ? intervaloPersonalizado?.end ?? agora
        : agora;
  }
Stream<QuerySnapshot> _getVendasFiltradas() {
  final dataInicial = _getDataInicial();
  final dataFinal = _getDataFinal();

  Query query = FirebaseFirestore.instance
      .collection('vendas')
      .where('dataVenda', isGreaterThanOrEqualTo: dataInicial.toIso8601String())
      .where('dataVenda', isLessThanOrEqualTo: dataFinal.toIso8601String());

  if (filtroUsuario != null) {
    query = query.where('nomeUsuario', isEqualTo: filtroUsuario);
  }

  if (filtroFormaPagamento != null) {
    query = query.where('formasPagamento', arrayContains: filtroFormaPagamento);
  }


  return query.orderBy('dataVenda', descending: true).snapshots();
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
                title: Text('Início: ${DateFormat('dd/MM/yyyy').format(dataInicialTemp)}'),
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
                title: Text('Fim: ${DateFormat('dd/MM/yyyy').format(dataFinalTemp)}'),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  intervaloPersonalizado = DateTimeRange(start: dataInicialTemp, end: dataFinalTemp);
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelecionado ? Colors.purple[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelecionado ? Colors.purple : Colors.grey),
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
                        fontWeight: isSelecionado ? FontWeight.bold : FontWeight.normal,
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
              ...usuarios.map((u) =>
                  DropdownMenuItem(value: u, child: Text(u))),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Forma Pagamento'),
            value: filtroFormaPagamento,
            onChanged: (value) => setState(() => filtroFormaPagamento = value),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todas')),
              ...formasPagamento.map((f) =>
                  DropdownMenuItem(value: f, child: Text(f))),
            ],
          ),
        ),
      ],
    ),
  );
}



Widget _buildVendaCard(Map<String, dynamic> venda, int index) {
  final total = venda['total'] ?? 0;
  final data = DateTime.tryParse(venda['dataVenda'] ?? '');
  final itens = venda['itens'] as List<dynamic>? ?? [];
  final cliente = venda['cliente'] ?? 'Não informado';
  final frete = venda['frete'] ?? 0.0;
  final nomeUsuario = venda['nomeUsuario'] ?? 'Desconhecido';
  final pagamentos = venda['pagamentos'] as List<dynamic>? ?? [];
  final formaPagamento = pagamentos.isNotEmpty
      ? pagamentos.map((p) => '${p['forma']}: R\$ ${(p['valor'] ?? 0).toStringAsFixed(2)}').join(' | ')
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
        data != null ? DateFormat('dd/MM/yyyy – HH:mm').format(data) : 'Data inválida',
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
              const Text('Itens:', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        ...itens.map((item) {
          return ListTile(
            leading: const Icon(Icons.shopping_bag_outlined, color: Colors.purple),
            title: Text(item['produtoNome'] ?? 'Produto'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((item['tamanho'] ?? '').toString().isNotEmpty)
                  Text('Tamanho: ${item['tamanho']}'),
                Text('Qtd: ${item['quantidade']}'),
                Text('Valor unitário: R\$ ${(item['precoFinal'] ?? 0).toStringAsFixed(2)}'),
              ],
            ),
          );
        }).toList(),
      ],
    ),
  );
}
@override
void initState() {
  super.initState();
  _carregarFiltros();
}

Future<void> _carregarFiltros() async {
  try {
    final snapshot = await FirebaseFirestore.instance.collection('vendas').get();

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
        title: const Text('Histórico de Vendas', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
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
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),

                  ],
                ),
              ),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.dashboard, 'Home', () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeView()));
                }),
              _menuItem(Icons.attach_money, 'Vender', () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendasView()));
              }),
              _menuItem(Icons.checkroom, 'Produtos', () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProdutosView()));
              }),
              _menuItem(Icons.add_box, 'Adicionar Produto', () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdicionarProdutosView()));
              }),
              _menuItem(Icons.people, 'Clientes', () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ClientesView()));
              }),
              _menuItem(Icons.bar_chart, 'Vendas Realizadas', () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendasRealizadasView()));
               }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.bar_chart, 'Relatórios', () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RelatoriosView()));
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.settings, 'Configurações', () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ConfiguracoesView()));
                }),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _buildFiltros(),
          _buildFiltrosExtras(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getVendasFiltradas(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('Erro ao carregar vendas.'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final vendas = snapshot.data!.docs;

                if (vendas.isEmpty) {
                  return const Center(child: Text('Nenhuma venda registrada.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: vendas.length,
                  itemBuilder: (context, index) {
                    final venda = vendas[index].data() as Map<String, dynamic>;
                    return _buildVendaCard(venda, index);
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
