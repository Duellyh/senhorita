import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class HistoricoVendasView extends StatelessWidget {
  const HistoricoVendasView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Vendas', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vendas')
            .orderBy('dataVenda', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Erro ao carregar vendas.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final vendas = snapshot.data!.docs;

          if (vendas.isEmpty) return const Center(child: Text('Nenhuma venda registrada.'));

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const Divider(),
            itemCount: vendas.length,
            itemBuilder: (context, index) {
              final venda = vendas[index].data() as Map<String, dynamic>;
              final total = venda['total'] ?? 0;
              final data = DateTime.tryParse(venda['dataVenda'] ?? '');
              final itens = venda['itens'] as List<dynamic>? ?? [];

              return ExpansionTile(
                title: Text(
                  'Venda ${index + 1} - R\$ ${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(data != null
                    ? '${data.day}/${data.month}/${data.year} - ${data.hour}:${data.minute.toString().padLeft(2, '0')}'
                    : 'Data inválida'),
                children: itens.map((item) {
                  return ListTile(
                    title: Text('${item['produtoNome']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((item['tamanho'] ?? '').toString().isNotEmpty)
                          Text('Tamanho: ${item['tamanho']}'),
                        Text('Qtd: ${item['quantidade']}'),
                        Text('Valor unitário: R\$ ${(item['precoFinal'] ?? 0).toStringAsFixed(2)}'),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}
