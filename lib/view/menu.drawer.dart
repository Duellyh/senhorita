// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/relatorios.view.dart'; 

class MenuDrawer extends StatelessWidget {
  final String tipoUsuario;

  const MenuDrawer({super.key, required this.tipoUsuario});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.pink),
            child: Text(
              'Senhorita Cintas',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),

          // Páginas comuns (funcionário e admin)
          ListTile(
            leading: const Icon(Icons.point_of_sale),
            title: const Text('Vendas'),
            onTap: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendasView()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_bag),
            title: const Text('Produtos'),
            onTap: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProdutosView()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_box),
            title: const Text('Adicionar Produto'),
            onTap: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdicionarProdutosView()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Clientes'),
            onTap: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ClientesView()));
            },
          ),

          // Páginas apenas para administradores
          if (tipoUsuario == 'admin') ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Configurações'),
              onTap: () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ConfiguracoesView()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Relatórios'),
              onTap: () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RelatoriosView()));
              },
            ),
          ],

          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
            },
          ),
        ],
      ),
    );
  }
}
