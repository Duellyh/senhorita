// ignore_for_file: use_build_context_synchronously

import 'dart:typed_data';
import 'package:barcode_image/barcode_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;

class ProdutosView extends StatefulWidget {
  const ProdutosView({super.key});

  @override
  State<ProdutosView> createState() => _ProdutosViewState();
}

class _ProdutosViewState extends State<ProdutosView> {
  String searchTerm = '';
  TextEditingController searchController = TextEditingController();
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
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user!.uid)
          .get();
      setState(() {
        tipoUsuario = doc['tipo'] ?? 'funcionario';
        nomeUsuario = doc['nome'] ?? 'Usuário';
      });
    }
  }

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

  void _mostrarEtiquetaDialog(BuildContext context, DocumentSnapshot produto) {
    final data = produto.data() as Map<String, dynamic>;
    final tamanhos = data['tamanhos'] as Map<String, dynamic>?;
    final temTamanho = tamanhos != null && tamanhos.isNotEmpty;

    String? tamanhoSelecionado;

    showDialog(
      context: context,
      builder: (ctx) {
        Printer? impressoraSelecionada;

        return FutureBuilder<List<Printer>>(
          future: Printing.listPrinters(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final impressoras = snapshot.data!;

            // Seleciona automaticamente a impressora ELGIN L42PRO FULL, se disponível
            if (impressoraSelecionada == null) {
              impressoraSelecionada = impressoras.firstWhere(
                (p) => p.name == 'ELGIN L42PRO ETIQUETA',
                orElse: () => impressoras.first,
              );
            }

            return StatefulBuilder(
              builder: (ctx, setState) => AlertDialog(
                title: const Text('Imprimir Etiqueta'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Produto: ${data['nome'] ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (temTamanho)
                        DropdownButtonFormField<String>(
                          value: tamanhoSelecionado,
                          decoration: const InputDecoration(
                            labelText: 'Selecione o Tamanho',
                          ),
                          items: tamanhos.keys.map((tam) {
                            return DropdownMenuItem(
                              value: tam,
                              child: Text(tam),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => tamanhoSelecionado = value),
                        ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<Printer>(
                        value: impressoraSelecionada,
                        decoration: const InputDecoration(
                          labelText: 'Selecionar Impressora',
                        ),
                        items: impressoras.map((printer) {
                          return DropdownMenuItem(
                            value: printer,
                            child: Text(printer.name),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setState(() => impressoraSelecionada = value),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Preço: R\$ ${data['precoVenda']?.toStringAsFixed(2) ?? '-'}',
                      ),
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
                          const SnackBar(
                            content: Text(
                              'Selecione um tamanho antes de imprimir.',
                            ),
                          ),
                        );
                        return;
                      }

                      if (impressoraSelecionada == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Selecione uma impressora.'),
                          ),
                        );
                        return;
                      }

                      Navigator.pop(ctx);
                      _imprimirEtiquetaDupla(
                        data,
                        produto.id,
                        tamanhoSelecionado,
                        impressoraSelecionada!,
                      );
                    },
                    child: const Text('Imprimir'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _imprimirEtiquetaDupla(
    Map<String, dynamic> data,
    String id,
    String? tamanhoSelecionado,
    Printer impressoraSelecionada,
  ) async {
    final doc = pw.Document();

    // Tamanho ajustado para caber duas etiquetas na largura de 90mm
    const double etiquetaLargura = 36 * PdfPageFormat.mm;
    const double etiquetaAltura = 25 * PdfPageFormat.mm;

    final codigo = data['codigoBarras'] ?? '';

    pw.Widget _etiqueta() {
      return pw.Container(
        width: etiquetaLargura,
        height: etiquetaAltura,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              (data['nome'] ?? 'Sem nome').toString().length > 20
                  ? '${data['nome'].toString().substring(0, 20)}…'
                  : data['nome'] ?? 'Sem nome',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
              maxLines: 1,
              textAlign: pw.TextAlign.center,
            ),
            if (tamanhoSelecionado != null)
              pw.Text(
                'Tam: $tamanhoSelecionado',
                style: const pw.TextStyle(fontSize: 8),
                textAlign: pw.TextAlign.center,
              ),
            pw.Text(
              'R\$ ${data['precoVenda']?.toStringAsFixed(2) ?? '-'}',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
            pw.BarcodeWidget(
              barcode: Barcode.code128(),
              data: codigo,
              width: 100,
              height: 30,
              drawText: false,
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          90 * PdfPageFormat.mm, // largura total do papel
          etiquetaAltura,
        ),
        margin: const pw.EdgeInsets.symmetric(horizontal: 4 * PdfPageFormat.mm),
        build: (context) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              _etiqueta(),
              pw.SizedBox(width: 12), // espaço entre etiquetas
              _etiqueta(),
            ],
          );
        },
      ),
    );

    // Enviar diretamente para a impressora
    await Printing.directPrintPdf(
      printer: impressoraSelecionada,
      onLayout: (_) => doc.save(),
    );
  }

  Future<Uint8List> gerarImagemBarcodeParaEtiqueta30x12(String codigo) async {
    // Tamanho físico: 30x12mm em 203 DPI ≈ 240x96 pixels
    const largura = 240;
    const altura = 96;

    // Criar imagem branca
    final image = img.Image(width: largura, height: altura);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    // Margens mínimas para manter legibilidade
    const margemH = 8; // horizontal
    const margemV = 8; // vertical

    final larguraCodigo = largura - 2 * margemH;
    final alturaCodigo = altura - 2 * margemV;

    // Gerar código de barras com área útil ajustada
    drawBarcode(
      image,
      Barcode.code128(),
      codigo,
      x: margemH,
      y: margemV,
      width: larguraCodigo,
      height: alturaCodigo,
    );

    return Uint8List.fromList(img.encodePng(image));
  }

  Future<void> corrigirCampoAtivo() async {
    final produtos = await FirebaseFirestore.instance
        .collection('produtos')
        .get();

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
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Senhorita Cintas Modeladores',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
            const Center(
              child: Text(
                'PRODUTOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.dashboard, 'Home', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeView()),
                  );
                }),
              _menuItem(Icons.attach_money, 'Vender', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const VendasView()),
                );
              }),
              _menuItem(Icons.checkroom, 'Produtos', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ProdutosView()),
                );
              }),
              _menuItem(Icons.add_box, 'Adicionar Produto', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdicionarProdutosView(),
                  ),
                );
              }),
              _menuItem(Icons.people, 'Clientes', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ClientesView()),
                );
              }),
              if (tipoUsuario == 'funcionario')
                _menuItem(Icons.bar_chart, 'Vendas Realizadas', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VendasRealizadasView(),
                    ),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.show_chart, 'Relatórios', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const RelatoriosView()),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.settings, 'Configurações', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConfiguracoesView(),
                    ),
                  );
                }),
            ],
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
              bool estoqueBaixo = false;
              if (tamanhos == null || tamanhos.isEmpty) {
                final quantidade = data['quantidade'] ?? 0;
                estoqueBaixo = quantidade <= 3;
              } else {
                estoqueBaixo = tamanhos.values.any(
                  (qtd) => qtd is int && qtd <= 2,
                );
              }

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                                Text(
                                  data['nome'] ?? 'Sem nome',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: estoqueBaixo
                                        ? Colors.red
                                        : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ID: ${produto.id}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Categoria: ${data['categoria'] ?? '-'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Cor: ${data['cor'] ?? '-'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Loja: ${data['loja'] ?? '-'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
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
                          if (tipoUsuario == 'admin')
                            Text(
                              'Valor Real: R\$ ${data['valorReal']?.toStringAsFixed(2) ?? '-'}',
                            ),
                          Text(
                            'Preço Venda: R\$ ${data['precoVenda']?.toStringAsFixed(2) ?? '-'}',
                          ),
                          Text(
                            'Quantidade total: ${data['quantidade'] ?? 0}',
                            style: TextStyle(
                              color: estoqueBaixo ? Colors.red : Colors.black,
                            ),
                          ),

                          if (tamanhos != null && tamanhos.isNotEmpty)
                            ...tamanhos.entries.map(
                              (e) => Text('${e.key}: ${e.value}'),
                            ),
                          if (estoqueBaixo)
                            Icon(Icons.warning, color: Colors.red, size: 20),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.delete),
                            label: const Text('Excluir'),
                            onPressed: () => _excluirProduto(
                              context,
                              produto.id,
                              data['nome'],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.print),
                            label: const Text('Etiqueta'),
                            onPressed: () =>
                                _mostrarEtiquetaDialog(context, produto),
                          ),
                        ],
                      ),
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

Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
  return ListTile(
    leading: Icon(icon, color: Colors.white),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    onTap: onTap,
  );
}
