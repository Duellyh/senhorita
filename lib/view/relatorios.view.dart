import 'package:flutter/material.dart';
import 'package:senhorita/view/historico.vendas.dart';


class RelatoriosView extends StatelessWidget {
  const RelatoriosView({super.key});

  @override
  Widget build(BuildContext context) {
    // Simulando dados (substituir por Firestore futuramente)
    final int totalVendas = 25;
    final double totalRecebido = 1799.90;
    final int totalClientes = 10;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _cardRelatorio(
              icon: Icons.shopping_cart,
              titulo: 'Vendas Realizadas',
              valor: '$totalVendas',
              color: Colors.blueAccent,
            ),

            // 🔽 Card com redirecionamento
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoricoVendasView()),
                );
              },
              child: _cardRelatorio(
                icon: Icons.date_range,
                titulo: 'Histórico de Vendas',
                valor: 'Ver Histórico',
                color: Colors.orange,
              ),
            ),

            const SizedBox(height: 16),
            _cardRelatorio(
              icon: Icons.attach_money,
              titulo: 'Total Recebido',
              valor: 'R\$ ${totalRecebido.toStringAsFixed(2)}',
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            _cardRelatorio(
              icon: Icons.people,
              titulo: 'Clientes Ativos',
              valor: '$totalClientes',
              color: Colors.deepPurple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardRelatorio({
    required IconData icon,
    required String titulo,
    required String valor,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(valor, style: const TextStyle(fontSize: 16)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }
}
