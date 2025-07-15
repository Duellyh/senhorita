import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:senhorita/view/estoque.view.dart';

class ProdutosView extends StatefulWidget {
  const ProdutosView({super.key});

  @override
  State<ProdutosView> createState() => _ProdutosViewState();
}

class _ProdutosViewState extends State<ProdutosView> {
  String searchTerm = '';
  TextEditingController searchController = TextEditingController();

  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178); // Roxo
  final Color accentColor = const Color(0xFFec407a); // Rosa

  void _editarProduto(BuildContext context, DocumentSnapshot produto) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdicionarProdutosView(produto: produto),
      ),
    );
  }

Future<int> _buscarQuantidadeEstoque(String produtoId) async {
  final estoqueSnapshot = await FirebaseFirestore.instance
      .collection('estoque')
      .where('idProduto', isEqualTo: produtoId)
      .limit(1)
      .get();

  if (estoqueSnapshot.docs.isNotEmpty) {
    return estoqueSnapshot.docs.first.data()['quantidade'] ?? 0;
  }
  return 0;
}


  void _abrirEstoqueProduto(BuildContext context, String produtoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstoqueView(produtoId: produtoId),
      ),
    );
  }

  void _mostrarEtiquetaDialog(BuildContext context, DocumentSnapshot produto) {
    final data = produto.data() as Map<String, dynamic>;
    final tamanhos = data['tamanhos'] as Map<String, dynamic>?;
    final temTamanho = tamanhos != null && tamanhos.isNotEmpty;

    String? tamanhoSelecionado;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Imprimir Etiqueta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Produto: ${data['nome'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (temTamanho)
                DropdownButtonFormField<String>(
                  value: tamanhoSelecionado,
                  decoration: const InputDecoration(labelText: 'Selecione o Tamanho'),
                  items: tamanhos.keys.map((tam) {
                    return DropdownMenuItem(value: tam, child: Text(tam));
                  }).toList(),
                  onChanged: (value) => setState(() => tamanhoSelecionado = value),
                ),
              const SizedBox(height: 10),
              Text('Preço: R\$ ${data['precoVenda']?.toStringAsFixed(2) ?? '-'}'),
              const SizedBox(height: 8),
              SizedBox(
                width: 200,
                height: 60,
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: produto['codigoBarras'] ?? '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                if (temTamanho && tamanhoSelecionado == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Selecione um tamanho antes de imprimir.')),
                  );
                  return;
                }

                Navigator.pop(ctx);
                _imprimirEtiqueta(data, produto.id, tamanhoSelecionado);
              },
              child: const Text('Imprimir'),
            ),
          ],
        ),
      ),
    );
  }

  void _imprimirEtiqueta(Map<String, dynamic> data, String id, String? tamanhoSelecionado) {
    debugPrint('--- ETIQUETA ---');
    debugPrint('Nome: ${data['nome']}');
    if (tamanhoSelecionado != null) debugPrint('Tamanho: $tamanhoSelecionado');
    debugPrint('Preço: R\$ ${data['precoVenda']}');
    debugPrint('ID: $id');
    debugPrint('Código de Barras: ${data['codigoBarras']}');
  }

  Future<void> corrigirCampoAtivo() async {
  final produtos = await FirebaseFirestore.instance.collection('produtos').get();

  for (var doc in produtos.docs) {
    final data = doc.data();
    final ativo = data['ativo'];

    if (ativo is num) {
      final boolAtivo = ativo != 0;
      await doc.reference.update({'ativo': boolAtivo});
      debugPrint('Corrigido ${doc.id}: ativo = $boolAtivo');
    }
  }

  debugPrint('✅ Todos os campos "ativo" foram corrigidos.');
}


  void _excluirProduto(BuildContext context, String id, String nome) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Produto'),
        content: Text('Tem certeza que deseja excluir o produto "$nome"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('produtos').doc(id).delete();
    }
  }

  Stream<QuerySnapshot> _buscarProdutosFirestore(String termo) {
    final colecao = FirebaseFirestore.instance.collection('produtos');
    if (termo.isEmpty) return colecao.snapshots();
    final termoLower = termo.toLowerCase();
    return colecao.where('busca', arrayContains: termoLower).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: const Text('Produtos', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: searchController,
              onChanged: (value) => setState(() => searchTerm = value),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, categoria, ID...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
  stream: _buscarProdutosFirestore(searchTerm.trim()),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
      return const Center(child: Text('Nenhum produto encontrado.'));
    }

    final produtos = snapshot.data!.docs;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: produtos.length,
      itemBuilder: (context, index) {
        final produto = produtos[index];
        final data = produto.data() as Map<String, dynamic>;
        final tamanhos = data['tamanhos'] as Map<String, dynamic>?;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    data['foto'] != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              data['foto'],
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.image, size: 60),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['nome'] ?? 'Sem nome',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('ID: ${produto.id}', style: const TextStyle(fontSize: 12)),
                          Text('Categoria: ${data['categoria'] ?? '-'}', style: const TextStyle(fontSize: 12)),
                          Text('Cor: ${data['cor'] ?? '-'}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text('Valor: R\$ ${data['valorReal']?.toStringAsFixed(2) ?? '-'}'),
                    Text('Venda: R\$ ${data['precoVenda']?.toStringAsFixed(2) ?? '-'}'),
                    Text('Quantidade total: ${data['quantidade'] ?? 0}'),
                    if (tamanhos != null && tamanhos.isNotEmpty)
                      ...tamanhos.entries.map((e) => Text('${e.key}: ${e.value}')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                      onPressed: () => _editarProduto(context, produto),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.delete),
                      label: const Text('Excluir'),
                      onPressed: () => _excluirProduto(context, produto.id, data['nome']),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.print),
                      label: const Text('Etiqueta'),
                      onPressed: () => _mostrarEtiquetaDialog(context, produto),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  },
),

    );
  }
}
