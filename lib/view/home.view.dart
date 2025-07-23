// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/estoque.view.dart';
import 'package:senhorita/view/financeiro.view.dart';
import 'package:senhorita/view/historico.vendas.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'login.view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';

  @override
  void initState() {
    super.initState();
    buscarTipoUsuario();
  }

  Future<void> buscarTipoUsuario() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user!.uid).get();
      setState(() {
        tipoUsuario = doc['tipo'] ?? 'funcionario';
        nomeUsuario = doc['nome'] ?? 'Usuário';
      });
    }
  }

  Future<int> _contarDocumentos(String colecao) async {
    final snapshot = await FirebaseFirestore.instance.collection(colecao).get();
    return snapshot.docs.length;
  }

  Future<int> contarProdutosComEstoqueBaixo() async {
  final snapshot = await FirebaseFirestore.instance.collection('produtos').get();

  int contador = 0;

  for (var doc in snapshot.docs) {
    final data = doc.data();
    final quantidade = data['quantidade'] ?? 0;
    final tamanhos = data['tamanhos'] as Map<String, dynamic>?;

    // Produto sem tamanho
    if ((tamanhos == null || tamanhos.isEmpty) && quantidade <= 3) {
      contador++;
    }

    // Produto com tamanhos
    if (tamanhos != null && tamanhos.isNotEmpty) {
      final hasBaixo = tamanhos.values.any((qtd) => qtd is int && qtd <= 2);
      if (hasBaixo) contador++;
    }
  }

  return contador;
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: Row(
          children: [
            const Icon(Icons.store_mall_directory, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
              'Senhorita Cintas Modeladores',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginView()));
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
                _menuItem(Icons.show_chart, 'Relatórios', () {
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
      body: Container(
        color: Colors.grey[100],
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
                            Row(
                  children: [
                    Expanded(
                 child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ProdutosView()),
                            );
                          },
                      child: FutureBuilder<int>(
                        future: _contarDocumentos('produtos'),
                        builder: (context, snapshot) {
                          final total = snapshot.data?.toString() ?? '...';
                          return _kpiCard('Produtos', total, Icons.checkroom, primaryColor);
                        },
                      ),
                    ),
                                      ),
                    ),
                    Expanded(
                        child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => HistoricoVendasView()),
                            );
                          },
                      child: FutureBuilder<int>(
                        future: _contarDocumentos('vendas'),
                        builder: (context, snapshot) {
                          final total = snapshot.data?.toString() ?? '...';
                          return _kpiCard('Vendas', total, Icons.attach_money, accentColor);
                        },
                      ),
                    ),
                                            ),
                      ),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ClientesView()),
                            );
                          },
                          child: FutureBuilder<int>(
                            future: _contarDocumentos('clientes'),
                            builder: (context, snapshot) {
                              final total = snapshot.data?.toString() ?? '...';
                              return _kpiCard('Clientes', total, Icons.people, primaryColor);
                            },
                          ),
                        ),
                      ),
                    ),
                                        Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => EstoqueView()),
                            );
                          },
                          child: FutureBuilder<int>(
                            future: contarProdutosComEstoqueBaixo(),
                            builder: (context, snapshot) {
                              final total = snapshot.data?.toString() ?? '...';
                              return _kpiCard('Produtos com Estoque baixo', total, Icons.inventory, accentColor);
                            },
                          ),
                        ),
                      ),
                    ),
                        Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => FinanceiroView()),
                            );
                          },
                          child: FutureBuilder<int>(
                            future: _contarDocumentos('totalRecebido'),
                            builder: (context, snapshot) {
                              final total = snapshot.data?.toString() ?? '...';
                              return _kpiCard('Dashboard Financeiro', total, Icons.monetization_on, primaryColor);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

            const SizedBox(height: 24),
            Text('Últimos Produtos Cadastrados', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            _productList(),
            const SizedBox(height: 24),
            Text('Últimas Vendas', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            _salesList(),
            const SizedBox(height: 32),
            Center(
              child: Text(
                '© 2025 Loja Senhorita Cintas Modeladores - Todos os direitos reservados.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        color: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('produtos').orderBy('dataCadastro', descending: true).limit(5).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Text('Nenhum produto encontrado.');

        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.checkroom, color: Colors.deepPurple),
                title: Text(data['nome'] ?? 'Sem nome'),
                subtitle: Text('Categoria: ${data['categoria'] ?? 'N/A'} | Preço: R\$ ${data['precoVenda']?.toStringAsFixed(2) ?? '0.00'}'),
              );
            },
          ),
        );
      },
    );
  }

Widget _salesList() {
  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('vendas')
        .orderBy('dataVenda', descending: true)
        .limit(5)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }

      if (snapshot.hasError) {
        return const Center(child: Text('Erro ao carregar vendas.'));
      }

      final docs = snapshot.data?.docs ?? [];
      if (docs.isEmpty) {
        return const Text('Nenhuma venda encontrada.');
      }

      return Card(
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;

            // Corrigido: agora usa 'totalVenda'
            double total = 0.0;
            final rawTotal = data['totalVenda'];
            if (rawTotal is int) {
              total = rawTotal.toDouble();
            } else if (rawTotal is double) {
              total = rawTotal;
            } else if (rawTotal is String) {
              total = double.tryParse(rawTotal) ?? 0.0;
            }

            String dataFormatada = 'Data inválida';
            final dataVendaRaw = data['dataVenda'];
            if (dataVendaRaw is Timestamp) {
              final dataVenda = dataVendaRaw.toDate();
              dataFormatada = DateFormat('dd/MM/yyyy HH:mm').format(dataVenda);
            }

            return ListTile(
              leading: const Icon(Icons.attach_money, color: Colors.pink),
              title: Text('Venda de R\$ ${total.toStringAsFixed(2)}'),
              subtitle: Text('Data: $dataFormatada'),
            );
          },
        ),
      );
    },
  );
}



}
