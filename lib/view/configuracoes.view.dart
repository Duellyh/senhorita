// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/gerencia.usuario.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class ConfiguracoesView extends StatefulWidget {
  const ConfiguracoesView({super.key});

  @override
  State<ConfiguracoesView> createState() => _ConfiguracoesViewState();
}

class _ConfiguracoesViewState extends State<ConfiguracoesView> {
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
  void _mostrarDialogAlterarSenha(BuildContext context) {
  final senhaAtualController = TextEditingController();
  final novaSenhaController = TextEditingController();
  final confirmarSenhaController = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Alterar Senha'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: senhaAtualController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha atual'),
              ),
              TextField(
                controller: novaSenhaController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nova senha'),
              ),
              TextField(
                controller: confirmarSenhaController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmar nova senha'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 194, 131, 178)),
            child: const Text('Salvar'),
            onPressed: () async {
              final senhaAtual = senhaAtualController.text.trim();
              final novaSenha = novaSenhaController.text.trim();
              final confirmarSenha = confirmarSenhaController.text.trim();

              if (novaSenha != confirmarSenha) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('As senhas não coincidem.')),
                );
                return;
              }

              try {
                final cred = EmailAuthProvider.credential(
                  email: user!.email!,
                  password: senhaAtual,
                );

                // Reautenticar usuário
                await user.reauthenticateWithCredential(cred);

                // Atualizar senha
                await user.updatePassword(novaSenha);

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Senha alterada com sucesso.')),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro ao alterar senha: $e')),
                );
              }
            },
          ),
        ],
      );
    },
  );
}


  @override
  Widget build(BuildContext context) {
    if (tipoUsuario.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Senhorita Cintas Modeladores',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Text(
              'CONFIGURAÇÕES',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _itemConfiguracao(
            icon: Icons.lock,
            title: 'Alterar Senha',
            onTap: () {
              _mostrarDialogAlterarSenha(context);
            },
          ),
          const SizedBox(height: 10),
          _itemConfiguracao(
            icon: Icons.notifications,
            title: 'Configurar Usuário',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GerenciarUsuariosView()),
              );
            },
          ),
          const SizedBox(height: 10),
          _itemConfiguracao(
            icon: Icons.info_outline,
            title: 'Sobre o App',
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'SystemVende',
                applicationVersion: '1.0.0',
                children: const [Text('Aplicativo de vendas desenvolvido com Flutter.')],
              );
            },
          ),
          const SizedBox(height: 10),
          _itemConfiguracao(
            icon: Icons.logout,
            title: 'Sair',
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginView()),
              );
            },
            color: Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _itemConfiguracao({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = const Color.fromARGB(255, 194, 131, 178),
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
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
}
