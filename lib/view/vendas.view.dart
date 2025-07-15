import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VendasView extends StatefulWidget {
  const VendasView({super.key});

  @override
  State<VendasView> createState() => _VendasViewState();
}

class _VendasViewState extends State<VendasView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController buscaController = TextEditingController();
  int quantidade = 1;
  bool carregandoBusca = false;
  Map<String, dynamic>? produtoEncontrado;
  String? tamanhoSelecionado;
  final List<Map<String, dynamic>> itensVendidos = [];
  final TextEditingController precoPromocionalController = TextEditingController();
  final TextEditingController precoVendaController = TextEditingController();
  final TextEditingController descontoController = TextEditingController();
  final TextEditingController valorPagamentoController = TextEditingController();
  String? formaSelecionada;
  final List<Map<String, dynamic>> pagamentos = [];


  String _formatarPreco(dynamic valor) {
    if (valor == null) return '--';
    final parsed = valor is num ? valor : double.tryParse(valor.toString());
    return parsed != null ? parsed.toStringAsFixed(2) : '--';
  }

  double _converterParaDouble(String valor) {
    return double.tryParse(valor.replaceAll(',', '.')) ?? 0.0;
  }
double _calcularTotalGeral() {
  return itensVendidos.fold(0.0, (total, item) {
    final precoFinal = _converterParaDouble(item['precoFinal'].toString());
    return total + (precoFinal * item['quantidade']);
  });
}
double _calcularDescontoTotal() {
  return itensVendidos.fold(0.0, (total, item) {
    final desconto = _converterParaDouble(item['desconto']?.toString() ?? '0');
    return total + (desconto * item['quantidade']);
  });
}
double _calcularTotalPago() {
  return pagamentos.fold(0.0, (total, p) => total + (p['valor'] as double));
}


  Future<void> buscarProduto() async {
    final termo = buscaController.text.trim();
    if (termo.isEmpty) return;

    setState(() {
      carregandoBusca = true;
      produtoEncontrado = null;
      tamanhoSelecionado = null;
    });

    try {
      final query = await FirebaseFirestore.instance.collection('produtos').get();

      final produto = query.docs
          .map((doc) => doc.data())
          .firstWhere(
            (p) =>
                p['id'] == termo ||
                p['codigoBarras'] == termo ||
                (p['nome'] as String).toLowerCase().contains(termo.toLowerCase()),
            orElse: () => {},
          );

      if (produto.isNotEmpty) {
        setState(() {
          produtoEncontrado = produto;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produto não encontrado')),
        );
      }
    } catch (e) {
      debugPrint('Erro ao buscar produto: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao buscar produto')),
      );
    } finally {
      setState(() => carregandoBusca = false);
    }
  }

void adicionarProdutoAtual() {
  if (_formKey.currentState!.validate() && produtoEncontrado != null) {
    final precoPadrao = _converterParaDouble(produtoEncontrado!['precoVenda'].toString());
    final precoPromocional = _converterParaDouble(precoPromocionalController.text);
    final precoBase = precoPromocional > 0 ? precoPromocional : precoPadrao;

    double desconto = 0.0;
    final descontoText = descontoController.text.trim();

    if (descontoText.endsWith('%')) {
      final perc = double.tryParse(descontoText.replaceAll('%', '').replaceAll(',', '.')) ?? 0.0;
      desconto = precoBase * (perc / 100);
    } else if (descontoText.isNotEmpty) {
      desconto = double.tryParse(descontoText.replaceAll(',', '.')) ?? 0.0;
    }

    final precoComDesconto = (precoBase - desconto).clamp(0, double.infinity);

    final item = {
      'produtoId': produtoEncontrado?['id'],
      'produtoNome': produtoEncontrado?['nome'],
      'codigoBarras': produtoEncontrado?['codigoBarras'],
      'precoVenda': precoPadrao,
      'precoPromocional': precoPromocional > 0 ? precoPromocional : null,
      'desconto': desconto > 0 ? desconto : null,
      'quantidade': quantidade,
      'tamanho': tamanhoSelecionado ?? '',
      'precoFinal': precoComDesconto,
    };

    setState(() {
      itensVendidos.add(item);
      buscaController.clear();
      precoPromocionalController.clear();
      descontoController.clear();
      produtoEncontrado = null;
      tamanhoSelecionado = null;
      quantidade = 1;
    });
  }
}

Future<void> realizarVenda() async {
  final totalVenda = _calcularTotalGeral();
  final totalPago = _calcularTotalPago();

  if (itensVendidos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adicione ao menos um produto')),
    );
    return;
  }

  if (pagamentos.isEmpty || totalPago < totalVenda) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Valor pago insuficiente. Total: R\$ ${totalVenda.toStringAsFixed(2)}'),
      ),
    );
    return;
  }

  final firestore = FirebaseFirestore.instance;
  final batch = firestore.batch();

  try {
    final vendaRef = await firestore.collection('vendas').add({
      'dataVenda': DateTime.now().toIso8601String(),
      'itens': itensVendidos,
      'total': totalVenda,
      'pagamentos': pagamentos,
      'totalPago': totalPago,
      'troco': (totalPago - totalVenda).clamp(0, double.infinity),
    });

    for (final item in itensVendidos) {
      final produtoId = item['produtoId'];
      final tamanho = item['tamanho'];
      final quantidadeVendida = item['quantidade'];

      // Atualiza/remover estoque
      final estoqueQuery = await firestore
          .collection('estoque')
          .where('produtoId', isEqualTo: produtoId)
          .where('tamanho', isEqualTo: tamanho)
          .limit(1)
          .get();

      if (estoqueQuery.docs.isNotEmpty) {
        final estoqueDoc = estoqueQuery.docs.first;
        final estoqueRef = estoqueDoc.reference;
        final estoqueAtual = (estoqueDoc['quantidade'] ?? 0) as int;
        final novaQuantidade = estoqueAtual - quantidadeVendida;

        if (novaQuantidade > 0) {
          batch.update(estoqueRef, {'quantidade': novaQuantidade});
        } else {
          batch.delete(estoqueRef);
        }
      }

      // Atualiza o produto
      final produtoQuery = await firestore
          .collection('produtos')
          .where('id', isEqualTo: produtoId)
          .limit(1)
          .get();

      if (produtoQuery.docs.isNotEmpty) {
        final produtoDoc = produtoQuery.docs.first;
        final produtoRef = produtoDoc.reference;
        final produtoData = produtoDoc.data();

        Map<String, dynamic> tamanhos = {};
        if (produtoData.containsKey('tamanhos') && tamanho.isNotEmpty) {
          tamanhos = Map<String, dynamic>.from(produtoData['tamanhos']);
          final estoqueAtualTamanho = tamanhos[tamanho] ?? 0;
          final novoEstoqueTamanho = estoqueAtualTamanho - quantidadeVendida;

          if (novoEstoqueTamanho > 0) {
            tamanhos[tamanho] = novoEstoqueTamanho;
          } else {
            tamanhos.remove(tamanho);
          }
        }

        // Recalcula a quantidade total com base nos tamanhos atualizados
        final novaQuantidadeTotalProduto = tamanhos.values.fold<int>(0, (soma, qtd) => soma + (qtd as int));

        // ✅ Sempre atualiza o produto, nunca deleta
        batch.update(produtoRef, {
          'tamanhos': tamanhos,
          'quantidade': novaQuantidadeTotalProduto,
        });

        // Salva em vendidos
        await firestore.collection('vendidos').add({
          'produtoId': produtoId,
          'produtoNome': item['produtoNome'] ?? '',
          'codigoBarras': item['codigoBarras'] ?? '',
          'quantidade': quantidadeVendida,
          'tamanho': tamanho,
          'precoFinal': item['precoFinal'] ?? 0.0,
          'dataVenda': DateTime.now().toIso8601String(),
          'vendaId': vendaRef.id,
          'detalhesProduto': produtoData,
        });
      }
    }

    await batch.commit();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('✅ Venda registrada!'),
        content: Text(
          'Total: R\$ ${totalVenda.toStringAsFixed(2)}\n'
          'Pago: R\$ ${totalPago.toStringAsFixed(2)}\n'
          'Troco: R\$ ${(totalPago - totalVenda).clamp(0, double.infinity).toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );

    setState(() {
      itensVendidos.clear();
      pagamentos.clear();
    });
  } catch (e, stack) {
    debugPrint('❌ Erro ao registrar venda: $e');
    debugPrint(stack.toString());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erro ao registrar a venda: $e')),
    );
  }
}

  @override
Widget build(BuildContext context) {
  final tamanhosMap = produtoEncontrado?['tamanhos'] as Map<String, dynamic>?;

  return Scaffold(
    appBar: AppBar(
      title: const Text('Vender Produto', style: TextStyle(color: Colors.white)),
      backgroundColor: const Color.fromARGB(255, 194, 131, 178),
      centerTitle: true,
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: Padding(
      padding: const EdgeInsets.all(12),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            const Text('🔎 Buscar Produto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: buscaController,
              decoration: InputDecoration(
                labelText: 'Nome, ID ou código de barras',
                suffixIcon: carregandoBusca
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(icon: const Icon(Icons.search), onPressed: buscarProduto),
                border: OutlineInputBorder(),
              ),
              onFieldSubmitted: (_) => buscarProduto(),
            ),
            const SizedBox(height: 16),

            if (produtoEncontrado != null)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((produtoEncontrado?['foto'] ?? '').toString().isNotEmpty)
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(produtoEncontrado!['foto'], height: 120),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text('🛍️ Produto: ${produtoEncontrado?['nome'] ?? '---'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('🆔 Código: ${produtoEncontrado?['codigoBarras'] ?? '---'}'),
                      Text('📋 Descrição: ${produtoEncontrado?['descricao'] ?? '---'}'),
                      Text('💲 Preço: R\$ ${_formatarPreco(produtoEncontrado?['precoVenda'])}'),

                      const SizedBox(height: 10),
                      TextFormField(
                        controller: precoPromocionalController,
                        decoration: const InputDecoration(labelText: 'Preço Promocional (opcional)', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          final val = double.tryParse(value.replaceAll(',', '.'));
                          if (val == null || val <= 0) return 'Digite um valor válido ou deixe em branco';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: descontoController,
                        decoration: const InputDecoration(labelText: 'Desconto (R\$ ou %)', border: OutlineInputBorder()),
                        keyboardType: TextInputType.text,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final text = value.trim();
                          if (text.endsWith('%')) {
                            final parsed = double.tryParse(text.replaceAll('%', '').replaceAll(',', '.'));
                            if (parsed == null || parsed < 0 || parsed > 100) return 'Porcentagem inválida';
                          } else {
                            final parsed = double.tryParse(text.replaceAll(',', '.'));
                            if (parsed == null || parsed < 0) return 'Valor inválido';
                          }
                          return null;
                        },
                      ),

                      if (tamanhosMap != null && tamanhosMap.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: tamanhoSelecionado,
                          decoration: const InputDecoration(labelText: 'Tamanho', border: OutlineInputBorder()),
                          items: tamanhosMap.entries
                              .where((e) => e.value > 0)
                              .map((e) => DropdownMenuItem<String>(
                                    value: e.key,
                                    child: Text('${e.key} (Estoque: ${e.value})'),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => tamanhoSelecionado = value),
                          validator: (value) => value == null ? 'Selecione um tamanho' : null,
                        ),
                      ],

                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: quantidade.toString(),
                        decoration: const InputDecoration(labelText: 'Quantidade', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final val = int.tryParse(value ?? '');
                          if (val == null || val <= 0) return 'Quantidade inválida';
                          int estoque = 9999;
                          if (tamanhosMap != null && tamanhoSelecionado != null) {
                            estoque = tamanhosMap[tamanhoSelecionado] ?? 0;
                          } else if (produtoEncontrado?['quantidade'] != null) {
                            estoque = produtoEncontrado!['quantidade'];
                          }
                          if (val > estoque) return 'Estoque insuficiente';
                          return null;
                        },
                        onChanged: (value) {
                          final val = int.tryParse(value);
                          if (val != null) setState(() => quantidade = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: adicionarProdutoAtual,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Adicionar Produto'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ],
                  ),
                ),
              ),

            if (itensVendidos.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('🧾 Itens Vendidos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ...itensVendidos.map((item) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      title: Text('${item['produtoNome']} (${item['quantidade']})'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item['precoPromocional'] != null)
                            Text('Promo: R\$ ${_formatarPreco(item['precoPromocional'])}'),
                          if (item['desconto'] != null)
                            Text('Desconto: -R\$ ${_formatarPreco(item['desconto'])}'),
                          Text('Final: R\$ ${_formatarPreco(item['precoFinal'])}'),
                          Text('Tam: ${item['tamanho']}'),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => setState(() => itensVendidos.remove(item)),
                      ),
                    ),
                  )),
              const Divider(),
              Text('🔻 Desconto Total: R\$ ${_calcularDescontoTotal().toStringAsFixed(2)}'),
              Text('💰 Total Geral: R\$ ${_calcularTotalGeral().toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],

            if (itensVendidos.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('💳 Pagamento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(
                controller: valorPagamentoController,
                decoration: const InputDecoration(labelText: 'Valor do pagamento', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: formaSelecionada,
                decoration: const InputDecoration(labelText: 'Forma de Pagamento', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'pix', child: Text('Pix')),
                  DropdownMenuItem(value: 'credito', child: Text('Cartão de Crédito')),
                  DropdownMenuItem(value: 'debito', child: Text('Cartão de Débito')),
                  DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                ],
                onChanged: (value) => setState(() => formaSelecionada = value),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  final valor = double.tryParse(valorPagamentoController.text.replaceAll(',', '.')) ?? 0;
                  if (valor <= 0 || formaSelecionada == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Preencha valor e forma de pagamento válidos')),
                    );
                    return;
                  }
                  setState(() {
                    pagamentos.add({'forma': formaSelecionada, 'valor': valor});
                    valorPagamentoController.clear();
                    formaSelecionada = null;
                  });
                },
                icon: const Icon(Icons.attach_money),
                label: const Text('Adicionar Pagamento'),
              ),
              const SizedBox(height: 10),
              ...pagamentos.map((p) => ListTile(
                    title: Text('R\$ ${p['valor'].toStringAsFixed(2)}'),
                    subtitle: Text('Forma: ${p['forma']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => setState(() => pagamentos.remove(p)),
                    ),
                  )),
              const Divider(),
              Text('Total Pago: R\$ ${_calcularTotalPago().toStringAsFixed(2)}'),
              Text(
                'Restante: R\$ ${(_calcularTotalGeral() - _calcularTotalPago()).clamp(0, double.infinity).toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _calcularTotalPago() >= _calcularTotalGeral() ? Colors.green : Colors.red,
                ),
              ),
            ],

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: realizarVenda,
              icon: const Icon(Icons.shopping_cart_checkout),
              label: const Text('Finalizar Venda'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 196, 50, 99),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

}