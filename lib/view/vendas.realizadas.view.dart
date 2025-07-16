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

    @override
  void initState() {
    super.initState();
    buscarTipoUsuario();
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

  DateTime _getDataFinal() {
    final agora = DateTime.now();
    switch (filtroSelecionado) {
      case 'personalizado':
        return intervaloPersonalizado?.end ?? agora;
      default:
        return agora;
    }
  }

  Stream<QuerySnapshot> _getVendasStream() {
    final dataInicial = _getDataInicial();
    final dataFinal = _getDataFinal();

    return FirebaseFirestore.instance
        .collection('vendas')
        .where('dataVenda', isGreaterThanOrEqualTo: dataInicial.toIso8601String())
        .where('dataVenda', isLessThanOrEqualTo: dataFinal.toIso8601String())
        .orderBy('dataVenda', descending: true)
        .snapshots();
  }
    Future<void> buscarTipoUsuario() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user!.uid).get();
      setState(() {
        tipoUsuario = doc['tipo'] ?? 'funcionario';
      });
    }
  }

  Future<void> _selecionarIntervaloDatas() async {
    final hoje = DateTime.now();
    final intervalo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(hoje.year, hoje.month, hoje.day + 1),
      initialDateRange: intervaloPersonalizado ??
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

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendas Realizadas', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          DropdownButton<String>(
            value: filtroSelecionado,
            dropdownColor: Colors.white,
            underline: const SizedBox(),
            icon: const Icon(Icons.filter_list, color: Colors.white),
            items: filtros
                .map((f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase())))
                .toList(),
            onChanged: (value) async {
              if (value != null) {
                if (value == 'personalizado') {
                  await _selecionarIntervaloDatas();
                }
                setState(() => filtroSelecionado = value);
              }
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
                    Text(user?.email ?? 'Bem-vindo!', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
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
      body: StreamBuilder<QuerySnapshot>(
        stream: _getVendasStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final vendas = snapshot.data?.docs ?? [];

          if (vendas.isEmpty) {
            return const Center(child: Text('Nenhuma venda encontrada para esse período.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const Divider(),
            itemCount: vendas.length,
            itemBuilder: (context, i) {
              final data = vendas[i].data() as Map<String, dynamic>;
              final total = (data['total'] ?? 0.0) as double;
              final dataVendaStr = data['dataVenda'] ?? '';
              final dataVenda = DateTime.tryParse(dataVendaStr);

              return ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: Text('R\$ ${total.toStringAsFixed(2)}'),
                subtitle: Text(
                  dataVenda != null
                      ? 'Data: ${DateFormat('dd/MM/yyyy – HH:mm').format(dataVenda)}'
                      : 'Data indisponível',
                ),
              );
            },
          );
        },
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
