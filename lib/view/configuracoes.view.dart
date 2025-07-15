import 'package:flutter/material.dart';

class ConfiguracoesView extends StatelessWidget {
  const ConfiguracoesView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _itemConfiguracao(
            icon: Icons.lock,
            title: 'Alterar Senha',
            onTap: () {
              // Navegar ou exibir dialog para mudar senha
            },
          ),
          const SizedBox(height: 10),
          _itemConfiguracao(
            icon: Icons.notifications,
            title: 'Notificações',
            onTap: () {
              // Abre configurações de notificação
            },
          ),
          const SizedBox(height: 10),
          _itemConfiguracao(
            icon: Icons.color_lens,
            title: 'Tema do Aplicativo',
            onTap: () {
              // Abrir opções de tema
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
            onTap: () {
              // Lógica para logout
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
}
