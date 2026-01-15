// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/estoque.view.dart';
import 'package:senhorita/view/financeiro.especifico.dart';
import 'package:senhorita/view/financeiro.view.dart';
import 'package:senhorita/view/historico.vendas.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';
import 'login.view.dart';

class HomeView extends StatefulWidget {
  final String lojaSelecionada;
  const HomeView({super.key, required this.lojaSelecionada});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';
  String? _lojaSelecionada;

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

      final data = doc.data();

      setState(() {
        tipoUsuario = data?['tipo'] ?? 'funcionario';
        nomeUsuario = data?['nome'] ?? 'Usuário';
        final lojaUser = (data?['lojaSelecionada'] ?? '').toString().trim();
        _lojaSelecionada = widget.lojaSelecionada.trim().isNotEmpty
            ? widget.lojaSelecionada.trim()
            : (lojaUser.isNotEmpty ? lojaUser : null);
      });
    }
  }

  String? get _lojaAtual {
    final l = (widget.lojaSelecionada).trim();
    if (l.isNotEmpty) return l;

    final u = (_lojaSelecionada ?? '').trim();
    if (u.isNotEmpty) return u;

    return null;
  }

  Future<int> _contarDocumentos(String colecao) async {
    final loja = _lojaAtual;
    if (loja == null) return 0;

    final ref = FirebaseFirestore.instance.collection(colecao);

    // Se a coleção tiver campo "loja"
    final snap = await ref.where('loja', isEqualTo: loja).get();
    return snap.docs.length;
  }

  bool _ehEstoqueBaixo(Map<String, dynamic> data, {int threshold = 1}) {
    // 1) Campo "quantidade" (sem grade)
    final q = data['quantidade'];
    if (q is num && q <= threshold) return true;

    // 2) Campo "tamanhos": { 'P': 1, 'M': 0, ... }
    final tamanhos = data['tamanhos'];
    if (tamanhos is Map) {
      for (final v in tamanhos.values) {
        if (v is num && v <= threshold) return true;
      }
    }

    // 3) Campo "tamanhosCores": { 'P': { 'PRETO': 1, 'BRANCO': 0 }, ... }
    final tamanhosCores = data['tamanhosCores'];
    if (tamanhosCores is Map) {
      for (final corMap in tamanhosCores.values) {
        if (corMap is Map) {
          for (final v in corMap.values) {
            if (v is num && v <= threshold) return true;
          }
        }
      }
    }

    return false;
  }

  Future<int> contarProdutosComEstoqueBaixo({int threshold = 1}) async {
    final loja = _lojaAtual;
    if (loja == null) return 0;

    final snap = await FirebaseFirestore.instance
        .collection('produtos')
        .where('loja', isEqualTo: loja)
        .get();

    var count = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (_ehEstoqueBaixo(data, threshold: threshold)) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: Row(
          children: [
            const Icon(Icons.store_mall_directory, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
              'Senhorita Cintas Modeladores',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
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
                    MaterialPageRoute(
                      builder: (_) => HomeView(
                        lojaSelecionada:
                            _lojaSelecionada ?? widget.lojaSelecionada,
                      ),
                    ),
                  );
                }),
              _menuItem(Icons.attach_money, 'Vender', () {
                final loja = _lojaAtual;
                if (loja == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Selecione uma loja primeiro.'),
                    ),
                  );
                  return;
                }

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VendasView(lojaSelecionada: loja),
                  ),
                );
              }),
              _menuItem(Icons.checkroom, 'Produtos', () {
                if (_lojaSelecionada == null) {
                  // mensagem simples avisando
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Selecione uma loja primeiro.'),
                    ),
                  );
                  return;
                }

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProdutosView(
                      lojaSelecionada:
                          _lojaSelecionada!, // 👈 vamos ajustar essa tela depois
                    ),
                  ),
                );
              }),

              _menuItem(Icons.add_box, 'Adicionar Produto', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdicionarProdutosView(
                      lojaSelecionada: widget.lojaSelecionada,
                    ),
                  ),
                );
              }),
              _menuItem(Icons.people, 'Clientes', () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ClientesView(lojaSelecionada: widget.lojaSelecionada),
                  ),
                );
              }),
              if (tipoUsuario == 'funcionario')
                _menuItem(Icons.bar_chart, 'Vendas Realizadas', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VendasRealizadasView(
                        lojaSelecionada: widget.lojaSelecionada,
                      ),
                    ),
                  );
                }),
              if (tipoUsuario == 'admin')
                _menuItem(Icons.show_chart, 'Relatórios', () {
                  if (_lojaSelecionada == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Selecione uma loja primeiro.'),
                      ),
                    );
                    return;
                  }

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RelatoriosView(
                        lojaSelecionada:
                            _lojaSelecionada!, // vamos ajustar depois também
                      ),
                    ),
                  );
                }),

              if (tipoUsuario == 'admin')
                _menuItem(Icons.settings, 'Configurações', () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConfiguracoesView(
                        lojaSelecionada: widget.lojaSelecionada,
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      body: Container(
        color: Colors.grey[100],
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (_lojaSelecionada == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecione uma loja primeiro.'),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProdutosView(
                              lojaSelecionada: _lojaSelecionada!,
                            ),
                          ),
                        );
                      },

                      child: FutureBuilder<int>(
                        future: _contarDocumentos('produtos'),
                        builder: (context, snapshot) {
                          final total = snapshot.data?.toString() ?? '...';
                          return _kpiCard(
                            'Produtos',
                            total,
                            Icons.checkroom,
                            primaryColor,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final loja = _lojaAtual;
                        if (loja == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecione uma loja primeiro.'),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                HistoricoVendasView(lojaSelecionada: loja),
                          ),
                        );
                      },
                      child: FutureBuilder<int>(
                        future: _contarDocumentos('vendas'),
                        builder: (context, snapshot) {
                          final total = snapshot.data?.toString() ?? '...';
                          return _kpiCard(
                            'Vendas',
                            total,
                            Icons.attach_money,
                            accentColor,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClientesView(
                              lojaSelecionada: widget.lojaSelecionada,
                            ),
                          ),
                        );
                      },
                      child: FutureBuilder<int>(
                        future: _contarDocumentos('clientes'),
                        builder: (context, snapshot) {
                          final total = snapshot.data?.toString() ?? '...';
                          return _kpiCard(
                            'Clientes',
                            total,
                            Icons.people,
                            primaryColor,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final loja = _lojaAtual;
                        if (loja == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecione uma loja primeiro.'),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EstoqueView(lojaSelecionada: loja),
                          ),
                        );
                      },
                      child: FutureBuilder<int>(
                        future:
                            contarProdutosComEstoqueBaixo(), // ou threshold: 2
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return _kpiCard(
                              'Produtos com Estoque baixo',
                              '...',
                              Icons.inventory,
                              accentColor,
                            );
                          }
                          if (snapshot.hasError) {
                            return _kpiCard(
                              'Produtos com Estoque baixo',
                              '!',
                              Icons.inventory,
                              accentColor,
                            );
                          }
                          final total = (snapshot.data ?? 0).toString();
                          return _kpiCard(
                            'Produtos com Estoque baixo',
                            total,
                            Icons.inventory,
                            accentColor,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final loja = _lojaAtual;
                        if (loja == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecione uma loja primeiro.'),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                FinanceiroView(lojaSelecionada: loja),
                          ),
                        );
                      },
                      child: FutureBuilder<int>(
                        future: _contarDocumentos('totalRecebido'),
                        builder: (context, snapshot) {
                          final total = snapshot.data?.toString() ?? '...';
                          return _kpiCard(
                            'Dashboard Financeiro Geral',
                            total,
                            Icons.monetization_on,
                            primaryColor,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final loja = _lojaAtual;
                        if (loja == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecione uma loja primeiro.'),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                FinanceiroEspecificoView(lojaSelecionada: loja),
                          ),
                        );
                      },
                      child: FutureBuilder<int>(
                        future: _contarDocumentos('totalRecebido'),
                        builder: (context, snapshot) {
                          final total = snapshot.data?.toString() ?? '...';
                          return _kpiCard(
                            'Financeiro Específico',
                            total,
                            Icons.monetization_on,
                            accentColor,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            Text(
              'Últimos Produtos Cadastrados',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            _productList(),
            const SizedBox(height: 24),
            Text(
              'Últimas Vendas',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            _salesList(),
            const SizedBox(height: 32),
            Center(
              child: Text(
                '© 2025 Loja Senhorita Cintas Modeladores - Todos os direitos reservados.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Card(
      // Removi o Expanded daqui
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
    );
  }

  Widget _productList() {
    final loja = _lojaAtual;

    if (loja == null) {
      return const Text('Selecione uma loja para ver os produtos.');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('produtos')
          .where('loja', isEqualTo: loja)
          .orderBy('dataCadastro', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint('🔥 ERRO produtos: ${snapshot.error}');
          return Text('Erro ao carregar produtos: ${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Text('Nenhum produto encontrado.');

        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final nome = (data['nome'] ?? 'Sem nome').toString();
              final categoria = (data['categoria'] ?? 'N/A').toString();

              // evita crash se vier String/int/double
              final rawPreco = data['precoVenda'];
              final double preco = rawPreco is num
                  ? rawPreco.toDouble()
                  : double.tryParse(rawPreco?.toString() ?? '') ?? 0.0;

              return ListTile(
                leading: const Icon(Icons.checkroom, color: Colors.deepPurple),
                title: Text(nome),
                subtitle: Text(
                  'Categoria: $categoria | Preço: R\$ ${preco.toStringAsFixed(2)}',
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _salesList() {
    final loja = _lojaAtual;

    if (loja == null) {
      return const Text('Selecione uma loja para ver as vendas.');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vendas')
          .orderBy('dataVenda', descending: true)
          .limit(30) // pega mais pra conseguir filtrar e ainda mostrar 5
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Erro ao carregar vendas.'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Text('Nenhuma venda encontrada.');

        return FutureBuilder<List<QueryDocumentSnapshot>>(
          future: _filtrarVendasPorLoja(docs, loja, maxRetorno: 5),
          builder: (context, snapFiltradas) {
            if (snapFiltradas.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapFiltradas.hasError) {
              return const Text('Erro ao filtrar vendas por loja.');
            }

            final filtradas = snapFiltradas.data ?? [];
            if (filtradas.isEmpty) {
              return Text('Nenhuma venda encontrada para "$loja".');
            }

            return Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtradas.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final data = filtradas[i].data() as Map<String, dynamic>;

                  // totalVenda seguro
                  final rawTotal = data['totalVenda'];
                  final double total = rawTotal is num
                      ? rawTotal.toDouble()
                      : double.tryParse(rawTotal?.toString() ?? '') ?? 0.0;

                  // dataVenda segura
                  String dataFormatada = 'Data inválida';
                  final dv = data['dataVenda'];
                  if (dv is Timestamp) {
                    dataFormatada = DateFormat(
                      'dd/MM/yyyy HH:mm',
                    ).format(dv.toDate());
                  }

                  return ListTile(
                    leading: const Icon(Icons.attach_money, color: Colors.pink),
                    title: Text('Venda de R\$ ${total.toStringAsFixed(2)}'),
                    subtitle: Text('Data: $dataFormatada'),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Filtra vendas pela loja atual olhando os itens e puxando a loja do produto.
  /// Regra: se a venda tiver pelo menos 1 item cuja loja do produto == lojaSelecionada, ela entra.
  /// Se quiser exigir que TODOS os itens sejam da loja, eu ajusto a regra.
  Future<List<QueryDocumentSnapshot>> _filtrarVendasPorLoja(
    List<QueryDocumentSnapshot> docs,
    String lojaSelecionada, {
    int maxRetorno = 5,
  }) async {
    // 1) Coletar todos os códigos (codigoBarras) das vendas analisadas
    final Set<String> codigos = {};

    for (final d in docs) {
      final data = d.data() as Map<String, dynamic>;
      final itens = (data['itens'] as List?) ?? const [];
      for (final it in itens) {
        if (it is Map) {
          final c = (it['codigoBarras'] ?? it['codigo'] ?? it['barcode'] ?? '')
              .toString()
              .trim();
          if (c.isNotEmpty) codigos.add(c);
        }
      }
    }

    // Se não tem códigos, não dá pra descobrir loja
    if (codigos.isEmpty) return [];

    // 2) Buscar produtos em lote: codigoBarras -> loja
    final Map<String, String> lojaPorCodigo = {};
    final codesList = codigos.toList();

    for (var i = 0; i < codesList.length; i += 10) {
      final chunk = codesList.skip(i).take(10).toList();

      final qs = await FirebaseFirestore.instance
          .collection('produtos')
          .where('codigoBarras', whereIn: chunk)
          .get();

      for (final p in qs.docs) {
        final pd = p.data();
        final codigo = (pd['codigoBarras'] ?? '').toString().trim();
        final loja = (pd['loja'] ?? '').toString().trim();
        if (codigo.isNotEmpty && loja.isNotEmpty) {
          lojaPorCodigo[codigo] = loja;
        }
      }
    }

    // 3) Filtrar vendas
    final List<QueryDocumentSnapshot> filtradas = [];

    for (final d in docs) {
      if (filtradas.length >= maxRetorno) break;

      final data = d.data() as Map<String, dynamic>;
      final itens = (data['itens'] as List?) ?? const [];

      bool pertence = false;

      for (final it in itens) {
        if (it is Map) {
          final c = (it['codigoBarras'] ?? it['codigo'] ?? it['barcode'] ?? '')
              .toString()
              .trim();
          final lojaItem = lojaPorCodigo[c];

          if (lojaItem != null && lojaItem == lojaSelecionada) {
            pertence = true;
            break;
          }
        }
      }

      if (pertence) filtradas.add(d);
    }

    return filtradas;
  }
}
