import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistoricoVendasView extends StatefulWidget {
  const HistoricoVendasView({super.key});

  @override
  State<HistoricoVendasView> createState() => _HistoricoVendasViewState();
}

class _HistoricoVendasViewState extends State<HistoricoVendasView> {
  String filtroSelecionado = 'dia';
  DateTimeRange? intervaloPersonalizado;

  final List<String> filtros = ['dia', 'semana', 'mes', 'ano', 'personalizado'];

  DateTime _getDataInicial() {
    final agora = DateTime.now();
    switch (filtroSelecionado) {
      case 'semana':
        return agora.subtract(Duration(days: agora.weekday - 1));
      case 'mes':
        return DateTime(agora.year, agora.month);
      case 'ano':
        return DateTime(agora.year);
      case 'personalizado':
        return intervaloPersonalizado?.start ?? agora;
      default:
        return DateTime(agora.year, agora.month, agora.day);
    }
  }

  DateTime _getDataFinal() {
    final agora = DateTime.now();
    return filtroSelecionado == 'personalizado'
        ? intervaloPersonalizado?.end ?? agora
        : agora;
  }

  Stream<QuerySnapshot> _getVendasFiltradas() {
    final dataInicial = _getDataInicial();
    final dataFinal = _getDataFinal();

    return FirebaseFirestore.instance
        .collection('vendas')
        .where('dataVenda', isGreaterThanOrEqualTo: dataInicial.toIso8601String())
        .where('dataVenda', isLessThanOrEqualTo: dataFinal.toIso8601String())
        .orderBy('dataVenda', descending: true)
        .snapshots();
  }

Future<void> _selecionarIntervaloPersonalizado() async {
  DateTime dataInicialTemp = _getDataInicial();
  DateTime dataFinalTemp = _getDataFinal();

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Selecionar período'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Início: ${DateFormat('dd/MM/yyyy').format(dataInicialTemp)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final data = await showDatePicker(
                  context: context,
                  initialDate: dataInicialTemp,
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now(),
                  locale: const Locale('pt', 'BR'), // <-- português aqui
                );
                if (data != null) {
                  setState(() => dataInicialTemp = data);
                }
              },
            ),
            ListTile(
              title: Text('Fim: ${DateFormat('dd/MM/yyyy').format(dataFinalTemp)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final data = await showDatePicker(
                  context: context,
                  initialDate: dataFinalTemp,
                  firstDate: dataInicialTemp,
                  lastDate: DateTime.now(),
                  locale: const Locale('pt', 'BR'), // <-- português aqui
                );
                if (data != null) {
                  setState(() => dataFinalTemp = data);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                intervaloPersonalizado = DateTimeRange(start: dataInicialTemp, end: dataFinalTemp);
                filtroSelecionado = 'personalizado';
              });
              Navigator.pop(context);
            },
            child: const Text('Aplicar'),
          ),
        ],
      );
    },
  );
}



  Widget _buildFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: filtros.map((filtro) {
          final isSelecionado = filtroSelecionado == filtro;
          final bool isPersonalizado = filtro == 'personalizado';

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () async {
                if (isPersonalizado) {
                  await _selecionarIntervaloPersonalizado();
                } else {
                  setState(() => filtroSelecionado = filtro);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelecionado ? Colors.purple[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelecionado ? Colors.purple : Colors.grey),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPersonalizado ? Icons.date_range : Icons.filter_alt,
                      size: 18,
                      color: isSelecionado ? Colors.purple : Colors.grey[700],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPersonalizado
                          ? intervaloPersonalizado != null
                              ? '${DateFormat('dd/MM').format(intervaloPersonalizado!.start)} - ${DateFormat('dd/MM').format(intervaloPersonalizado!.end)}'
                              : 'Personalizado'
                          : filtro.toUpperCase(),
                      style: TextStyle(
                        fontWeight: isSelecionado ? FontWeight.bold : FontWeight.normal,
                        color: isSelecionado ? Colors.purple : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Vendas', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 194, 131, 178),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildFiltros(), // ⬅️ Filtros no topo da tela
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getVendasFiltradas(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('Erro ao carregar vendas.'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final vendas = snapshot.data!.docs;

                if (vendas.isEmpty) {
                  return const Center(child: Text('Nenhuma venda registrada.'));
                }

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
                          ? DateFormat('dd/MM/yyyy – HH:mm').format(data)
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
          ),
        ],
      ),
    );
  }
}
