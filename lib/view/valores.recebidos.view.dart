import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ValoresRecebidosView extends StatefulWidget {
  const ValoresRecebidosView({super.key});

  @override
  State<ValoresRecebidosView> createState() => _RelatorioValoresViewState();
}

class _RelatorioValoresViewState extends State<ValoresRecebidosView> {
  double totalGasto = 0;
  double totalRecebido = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório de Valores'),
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vendas')
            .orderBy('dataVenda', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Erro ao carregar dados'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final vendasDocs = snapshot.data!.docs;

          // Resetar totais
          totalGasto = 0;
          totalRecebido = 0;

          // Calcular totais a partir das vendas
          for (final vendaDoc in vendasDocs) {
            final vendaData = vendaDoc.data() as Map<String, dynamic>;
            final itens = vendaData['itens'] as List<dynamic>? ?? [];
            final totalVenda = (vendaData['total'] ?? 0).toDouble();

            totalRecebido += totalVenda;

            for (final item in itens) {
              final precoVenda = (item['precoVenda'] ?? 0).toDouble();
              final quantidade = (item['quantidade'] ?? 0).toInt();
              totalGasto += precoVenda * quantidade;
            }
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildCard('Total Gasto (Preço Venda * Qtde)', totalGasto, Colors.redAccent),
                const SizedBox(height: 12),
                _buildCard('Total Recebido (Venda)', totalRecebido, Colors.green),
                const SizedBox(height: 24),

                const Text(
                  'Detalhes das Vendas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: ListView.separated(
                    itemCount: vendasDocs.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final vendaData = vendasDocs[index].data() as Map<String, dynamic>;
                      final dataVendaStr = vendaData['dataVenda'] ?? '';
                      final dataVenda = DateTime.tryParse(dataVendaStr);
                      final itens = vendaData['itens'] as List<dynamic>? ?? [];
                      final totalVenda = (vendaData['total'] ?? 0).toDouble();

                      return ExpansionTile(
                        title: Text(
                          'Venda #${index + 1} - R\$ ${totalVenda.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(dataVenda != null
                            ? '${dataVenda.day.toString().padLeft(2, '0')}/'
                              '${dataVenda.month.toString().padLeft(2, '0')}/'
                              '${dataVenda.year} ${dataVenda.hour.toString().padLeft(2, '0')}:'
                              '${dataVenda.minute.toString().padLeft(2, '0')}'
                            : 'Data indisponível'),
                        children: itens.map<Widget>((item) {
                          final produto = item['produtoNome'] ?? 'Produto';
                          final precoVenda = (item['precoVenda'] ?? 0).toDouble();
                          final quantidade = (item['quantidade'] ?? 0).toInt();
                          final subtotal = precoVenda * quantidade;

                          return ListTile(
                            title: Text(produto),
                            subtitle: Text(
                              'Preço Venda: R\$ ${precoVenda.toStringAsFixed(2)} x Qtde: $quantidade = R\$ ${subtotal.toStringAsFixed(2)}',
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(String titulo, double valor, Color cor) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: ListTile(
        leading: CircleAvatar(backgroundColor: cor, child: const Icon(Icons.monetization_on, color: Colors.white)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(
          'R\$ ${valor.toStringAsFixed(2)}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cor),
        ),
      ),
    );
  }
}
