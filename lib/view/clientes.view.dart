// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class ClientesView extends StatefulWidget {
  const ClientesView({super.key});

  @override
  State<ClientesView> createState() => _ClientesViewState();
}

class _ClientesViewState extends State<ClientesView> {
  final nomeController = TextEditingController();
  final telefoneController = TextEditingController();
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

  void _adicionarOuEditarCliente({DocumentSnapshot? cliente}) {
    if (cliente != null) {
      nomeController.text = cliente['nome'];
      telefoneController.text = cliente['telefone'];
    } else {
      nomeController.clear();
      telefoneController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cliente == null ? 'Adicionar Cliente' : 'Editar Cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: telefoneController,
              decoration: const InputDecoration(labelText: 'Telefone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final nome = nomeController.text.trim();
              final telefone = telefoneController.text.trim();
              if (nome.isEmpty || telefone.isEmpty) return;

              final data = {
                'nome': nome,
                'telefone': telefone,
                'dataCadastro': DateTime.now().toIso8601String(),
              };

              if (cliente == null) {
                await FirebaseFirestore.instance.collection('clientes').add(data);
              } else {
                await cliente.reference.update(data);
              }

              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 196, 50, 99),
              foregroundColor: Colors.white,
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _excluirCliente(String id) async {
    await FirebaseFirestore.instance.collection('clientes').doc(id).delete();
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
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
                      ),
                    ),
                    const Center(
                      child: Text(
                        'CLIENTES',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('clientes').orderBy('nome').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Nenhum cliente cadastrado.'));

          final clientes = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: clientes.length,
            itemBuilder: (context, index) {
              final cliente = clientes[index];
              final data = cliente.data() as Map<String, dynamic>;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.person, color: Color.fromARGB(255, 194, 131, 178)),
                  title: Text(data['nome'] ?? ''),
                  subtitle: Text(data['telefone'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _adicionarOuEditarCliente(cliente: cliente),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _excluirCliente(cliente.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _adicionarOuEditarCliente(),
        icon: const Icon(Icons.person_add),
        label: const Text('Adicionar'),
        backgroundColor: const Color.fromARGB(255, 196, 50, 99),
        foregroundColor: Colors.white,
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