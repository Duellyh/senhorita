import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'login.view.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  Future<int> _contarDocumentos(String colecao) async {
    final snapshot = await FirebaseFirestore.instance.collection(colecao).get();
    return snapshot.docs.length;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    const Color primaryColor = Color.fromARGB(255, 194, 131, 178);
    const Color accentColor = Color(0xFFec407a);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: Row(
          children: [
            Icon(Icons.store_mall_directory, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Senhorita Cintas Modeladores',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.white),
            onPressed: () {},
          ),
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
                    Icon(Icons.store, color: Colors.white, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      user?.email ?? 'Bem-vindo!',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: Icon(Icons.dashboard, color: Colors.white),
                title: const Text('Home', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HomeView()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.attach_money, color: Colors.white),
                title: const Text('Vender', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const VendasView()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.checkroom, color: Colors.white),
                title: const Text('Produtos', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ProdutosView()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.add_box, color: Colors.white),
                title: const Text('Adicionar Produto', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdicionarProdutosView()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.people, color: Colors.white),
                title: const Text('Clientes', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ClientesView()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.bar_chart, color: Colors.white),
                title: const Text('Relatórios', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RelatoriosView()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.settings, color: Colors.white),
                title: const Text('Configurações', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ConfiguracoesView()),
                  );
                },
              ),
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
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FutureBuilder<int>(
                  future: _contarDocumentos('produtos'),
                  builder: (context, snapshot) {
                    final total = snapshot.data?.toString() ?? '...';
                    return _kpiCard('Produtos', total, Icons.checkroom, primaryColor);
                  },
                ),
                FutureBuilder<int>(
                  future: _contarDocumentos('vendas'),
                  builder: (context, snapshot) {
                    final total = snapshot.data?.toString() ?? '...';
                    return _kpiCard('Vendas', total, Icons.attach_money, accentColor);
                  },
                ),
                FutureBuilder<int>(
                  future: _contarDocumentos('clientes'),
                  builder: (context, snapshot) {
                    final total = snapshot.data?.toString() ?? '...';
                    return _kpiCard('Clientes', total, Icons.people, primaryColor);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Últimos Produtos Cadastrados',
              style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
            const SizedBox(height: 8),
            _productList(),
            const SizedBox(height: 24),   
            Text('Últimas Vendas',
              style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
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
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('produtos')
          .orderBy('dataCadastro', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
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
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Text('Nenhuma venda encontrada.');

        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final total = data['total'] ?? 0.0;
              final dataVenda = data['dataVenda']?.toString().substring(0, 10) ?? '';
              return ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.pink),
                title: Text('Venda de R\$ ${total.toStringAsFixed(2)}'),
                subtitle: Text('Data: $dataVenda'),
              );
            },
          ),
        );
      },
    );
  }
}