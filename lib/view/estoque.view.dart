// ignore_for_file: use_build_context_synchronously, avoid_types_as_parameter_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/login.view.dart';

class EstoqueView extends StatelessWidget {
  final String produtoId;

  const EstoqueView({super.key, required this.produtoId});

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color.fromARGB(255, 194, 131, 178);
    const Color accentColor = Color(0xFFec407a);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: const [
            Icon(Icons.inventory_2, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Controle de Estoque',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_none, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.account_circle, color: Colors.white), onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginView()));
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.grey[100],
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('estoque')
                  .where('produtoId', isEqualTo: produtoId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();

                final docs = snapshot.data!.docs;
                int totalProdutos = docs.fold(0, (sum, doc) {
                  final quantidade = doc['quantidade'] ?? 0;
                  return sum + (quantidade as num).toInt();
                });

                int baixoEstoque = docs.where((doc) {
                  final qtd = doc['quantidade'] ?? 0;
                  return qtd > 0 && qtd < 5;
                }).length;

                int esgotados = docs.where((doc) => (doc['quantidade'] ?? 0) == 0).length;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _kpiCard('Produtos', '$totalProdutos', Icons.checkroom, primaryColor),
                    _kpiCard('Baixo Estoque', '$baixoEstoque', Icons.warning, accentColor),
                    _kpiCard('Esgotados', '$esgotados', Icons.close, Colors.redAccent),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Expanded(child: _estoqueList(context)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accentColor,
        child: const Icon(Icons.add),
        onPressed: () => _mostrarDialogEstoque(context),
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
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estoqueList(BuildContext context) {
    final estoqueRef = FirebaseFirestore.instance
        .collection('estoque')
        .where('produtoId', isEqualTo: produtoId);

    return StreamBuilder<QuerySnapshot>(
      stream: estoqueRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados.'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;

        final ordemTamanhos = ['P', 'M', 'G', 'GG', 'XG', '50', '52', '54'];
        docs.sort((a, b) {
          final ta = a['tamanho'] ?? '';
          final tb = b['tamanho'] ?? '';
          return ordemTamanhos.indexOf(ta).compareTo(ordemTamanhos.indexOf(tb));
        });

        if (docs.isEmpty) return const Center(child: Text('Nenhum estoque cadastrado para este produto.'));

        return Card(
          child: ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final tamanho = data['tamanho'] ?? '-';
              final quantidade = data['quantidade'] ?? 0;

              Icon statusIcon;
              if (quantidade == 0) {
                statusIcon = const Icon(Icons.close, color: Colors.redAccent);
              } else if (quantidade < 5) {
                statusIcon = const Icon(Icons.warning, color: Colors.orange);
              } else {
                statusIcon = const Icon(Icons.check_circle, color: Colors.green);
              }

              return ListTile(
                leading: const Icon(Icons.checkroom, color: Colors.deepPurple),
                title: Text('Tamanho: $tamanho'),
                subtitle: Text('Quantidade: $quantidade'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusIcon,
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.grey),
                      onPressed: () => _mostrarDialogEstoque(context, docId: docs[i].id, data: data),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmarExcluir(context, docs[i].id),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _mostrarDialogEstoque(BuildContext context, {String? docId, Map<String, dynamic>? data}) {
    final formKey = GlobalKey<FormState>();
    final TextEditingController tamanhoController = TextEditingController(
        text: data != null ? data['tamanho']?.toString() ?? '' : '');
    final TextEditingController quantidadeController = TextEditingController(
        text: data != null ? data['quantidade']?.toString() ?? '' : '');

    final bool isEdit = docId != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Editar Estoque' : 'Adicionar Estoque'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: tamanhoController,
                decoration: const InputDecoration(labelText: 'Tamanho'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Informe o tamanho' : null,
              ),
              TextFormField(
                controller: quantidadeController,
                decoration: const InputDecoration(labelText: 'Quantidade'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value == null || int.tryParse(value) == null ? 'Informe um número válido' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final tamanho = tamanhoController.text.toUpperCase().trim();
              final quantidade = int.parse(quantidadeController.text.trim());
              final estoqueRef = FirebaseFirestore.instance.collection('estoque');

              if (isEdit) {
                await estoqueRef.doc(docId).update({
                  'tamanho': tamanho,
                  'quantidade': quantidade,
                });
              } else {
                final existing = await estoqueRef
                    .where('produtoId', isEqualTo: produtoId)
                    .where('tamanho', isEqualTo: tamanho)
                    .limit(1)
                    .get();

                if (existing.docs.isNotEmpty) {
                  final currentQtd = existing.docs.first['quantidade'] ?? 0;
                  await estoqueRef.doc(existing.docs.first.id).update({
                    'quantidade': currentQtd + quantidade,
                  });
                } else {
                  await estoqueRef.add({
                    'produtoId': produtoId,
                    'tamanho': tamanho,
                    'quantidade': quantidade,
                  });
                }
              }

              // Atualiza quantidade total no produto
                  final estoqueDocs = await estoqueRef.where('produtoId', isEqualTo: produtoId).get();

                  final tamanhosAtualizados = <String, int>{};
                  int total = 0;

                  for (final doc in estoqueDocs.docs) {
                    final data = doc.data();
                    final tamanho = data['tamanho'] ?? '';
                    final quantidade = (data['quantidade'] ?? 0) as int;
                    total += quantidade;
                    tamanhosAtualizados[tamanho] = quantidade;
                  }

                  await FirebaseFirestore.instance.collection('produtos').doc(produtoId).update({
                    'quantidade': total,
                    'tamanhos': tamanhosAtualizados,
                  });

              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _confirmarExcluir(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Tamanho'),
        content: const Text('Deseja realmente excluir este item de estoque?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              final estoqueRef = FirebaseFirestore.instance.collection('estoque');
              await estoqueRef.doc(docId).delete();

              // Atualiza a quantidade total no produto
             final estoqueDocs = await estoqueRef.where('produtoId', isEqualTo: produtoId).get();

              final tamanhosAtualizados = <String, int>{};
              int total = 0;

              for (final doc in estoqueDocs.docs) {
                final data = doc.data();
                final tamanho = data['tamanho'] ?? '';
                final quantidade = (data['quantidade'] ?? 0) as int;
                total += quantidade;
                tamanhosAtualizados[tamanho] = quantidade;
              }

              await FirebaseFirestore.instance.collection('produtos').doc(produtoId).update({
                'quantidade': total,
                'tamanhos': tamanhosAtualizados,
              });

              Navigator.pop(ctx);
            },
            child: const Text('Excluir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
