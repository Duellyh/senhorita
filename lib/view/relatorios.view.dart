// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/estoque.view.dart';
import 'package:senhorita/view/historico.vendas.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/financeiro.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class RelatoriosView extends StatefulWidget {
  final String lojaSelecionada; // 👈 guarda a loja

  const RelatoriosView({super.key, required this.lojaSelecionada});

  @override
  State<RelatoriosView> createState() => _RelatoriosViewState();
}

class _RelatoriosViewState extends State<RelatoriosView> {
  int totalVendas = 0;
  double totalRecebido = 0.0;
  int totalClientes = 0;
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';

  @override
  void initState() {
    super.initState();
    _carregarRelatorio();
    buscarTipoUsuario();
  }

  /// Se em algum momento você recriar o RelatoriosView com outra loja,
  /// recarrega o resumo automaticamente.
  @override
  void didUpdateWidget(covariant RelatoriosView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lojaSelecionada != widget.lojaSelecionada) {
      _carregarRelatorio();
    }
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

  Future<void> _carregarRelatorio() async {
    try {
      // 🔹 LOJA ATUAL
      final loja = widget.lojaSelecionada;

      if (loja.isEmpty) {
        // Se por algum motivo vier vazio, você pode decidir se:
        // - retorna tudo, ou
        // - simplesmente zera os resumos.
        setState(() {
          totalVendas = 0;
          totalRecebido = 0.0;
          totalClientes = 0;
        });
        return;
      }

      // 🔹 VENDAS APENAS DA LOJA SELECIONADA
      final vendasSnapshot = await FirebaseFirestore.instance
          .collection('vendas')
          .where('loja', isEqualTo: loja)
          .get();

      // 🔹 CLIENTES APENAS DA LOJA SELECIONADA
      // (isso só funciona se você salvar 'loja' em cada cliente)
      final clientesSnapshot = await FirebaseFirestore.instance
          .collection('clientes')
          .where('loja', isEqualTo: loja)
          .get();

      double somaRecebido = 0.0;

      for (var doc in vendasSnapshot.docs) {
        final data = doc.data();
        final totalPago = data['totalPago'];

        if (totalPago != null && totalPago is num) {
          somaRecebido += totalPago.toDouble();
        }
      }

      setState(() {
        totalVendas = vendasSnapshot.size;
        totalRecebido = somaRecebido;
        totalClientes = clientesSnapshot.size;
      });
    } catch (e, stack) {
      debugPrint('Erro ao carregar relatório: $e');
      debugPrint(stack.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar relatório: $e')),
        );
      }
    }
  }

  String formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
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
                'RELATÓRIOS',
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
                    const SizedBox(height: 4),
                    Text(
                      'Loja: ${widget.lojaSelecionada}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
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
        onRefresh: _carregarRelatorio,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '📊 Resumo Geral',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _infoCard(
              icon: Icons.shopping_bag,
              title: 'Total de Vendas',
              value: '$totalVendas',
              color: Colors.indigo,
            ),
            _infoCard(
              icon: Icons.attach_money,
              title: 'Total Recebido',
              value: formatCurrency(totalRecebido),
              color: Colors.green,
            ),
            _infoCard(
              icon: Icons.people,
              title: 'Clientes Ativos',
              value: '$totalClientes',
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 24),
            const Text(
              '📂 Relatórios Detalhados',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _actionCard(
              icon: Icons.inventory,
              title: 'Produtos com Estoque Baixo',
              color: Colors.blue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      EstoqueView(lojaSelecionada: widget.lojaSelecionada),
                ),
              ),
            ),
            _actionCard(
              icon: Icons.history,
              title: 'Histórico de Vendas',
              color: Colors.orange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoricoVendasView(
                    lojaSelecionada: widget.lojaSelecionada,
                  ),
                ),
              ),
            ),
            _actionCard(
              icon: Icons.monetization_on,
              title: 'Dashboard Financeiro',
              color: Colors.teal,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FinanceiroView(lojaSelecionada: widget.lojaSelecionada),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
