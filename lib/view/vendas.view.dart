import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:senhorita/service/nfce_service.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';

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
  String? corSelecionada; // <-- NOVO: cor da variante escolhida
  final List<Map<String, dynamic>> itensVendidos = [];
  final TextEditingController precoPromocionalController =
      TextEditingController();
  final TextEditingController precoVendaController = TextEditingController();
  final TextEditingController descontoController = TextEditingController();
  final TextEditingController valorPagamentoController =
      TextEditingController();
  final TextEditingController freteController = TextEditingController();
  final TextEditingController clienteNomeController = TextEditingController();
  final TextEditingController clienteTelefoneController =
      TextEditingController();
  Map<String, dynamic>? clienteSelecionado;
  bool mostrarCamposCliente = false;
  bool mostrarCampoFrete = false;
  String? formaSelecionada;
  final List<Map<String, dynamic>> pagamentos = [];
  String tipoNotaSelecionada = 'pagamento';
  List<Map<String, dynamic>> sugestoesProdutos = [];
  Timer? debounceTimer;
  List<Map<String, dynamic>> sugestoesClientes = [];
  Timer? debounceClienteTimer;
  String tipoUsuario = '';
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryColor = const Color.fromARGB(255, 194, 131, 178);
  final Color accentColor = const Color(0xFFec407a);
  String nomeUsuario = '';
  String? formaPagamentoSelecionada;
  double frete = 0.0;
  double total = 0.0;
  String? nomeLoja;
  String? funcionarioSelecionado;
  List<String> funcionarios = [];
  double custoReal = 0.0; // Variável para armazenar o custo real do produto
  bool mostrarCampoFuncionario = false;
  bool _processandoVenda = false;
  final NfceService _nfceService = NfceService();

  @override
  void initState() {
    super.initState();
    buscarTipoUsuario();
    buscarFuncionarios().then((lista) {
      setState(() {
        funcionarios = lista;
      });
    });
    mostrarCampoFuncionario = false;
  }

  double _freteAtual() {
    final t = freteController.text.trim();
    return t.isEmpty ? 0.0 : _converterParaDouble(t);
  }

  double _totalComFrete() => _calcularTotalGeral() + _freteAtual();

  double _trocoAtual() {
    final t = _calcularTotalPago() - _totalComFrete();
    return t > 0 ? t : 0.0;
  }

  double _faltanteAtual() {
    final f = _totalComFrete() - _calcularTotalPago();
    return f > 0 ? f : 0.0;
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
      final desconto = _converterParaDouble(
        item['desconto']?.toString() ?? '0',
      );
      return total + (desconto * item['quantidade']);
    });
  }

  double _calcularTotalPago() {
    return pagamentos.fold(0.0, (total, p) => total + (p['valor'] as double));
  }

  Future<List<String>> buscarFuncionarios() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('tipo', whereIn: ['funcionario', 'admin'])
        .get();

    return snapshot.docs.map((doc) => doc['nomeUsuario'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> buscarSugestoesProduto(
    String query,
  ) async {
    final resultado = await FirebaseFirestore.instance
        .collection('produtos')
        .get();

    return resultado.docs
        .where((doc) {
          final p = doc.data();
          return (p['nome'] as String).toLowerCase().contains(
            query.toLowerCase(),
          );
        })
        .map((doc) {
          final dados = doc.data();
          dados['docId'] = doc.id;
          return dados;
        })
        .toList();
  }

  Future<String> buscarNomeLoja() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Loja N/A';

    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    if (doc.exists) {
      return doc.data()?['lojaSelecionada'] ?? 'Loja N/A';
    } else {
      return 'Loja N/A';
    }
  }

  Future<void> buscarProdutosSugestoes(String termo) async {
    if (termo.isEmpty) {
      setState(() => sugestoesProdutos = []);
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('produtos')
          .get();

      final resultados = query.docs
          .where((doc) {
            final p = doc.data();
            final nome = (p['nome'] ?? '').toString().toLowerCase();
            final codigoBarras = (p['codigoBarras'] ?? '')
                .toString()
                .toLowerCase();
            final id = (p['id'] ?? '').toString().toLowerCase();
            final termoLower = termo.toLowerCase();

            return nome.contains(termoLower) ||
                codigoBarras.contains(termoLower) ||
                id == termoLower;
          })
          .map((doc) {
            final data = doc.data();
            data['docId'] = doc.id;
            return data;
          })
          .toList();

      setState(() => sugestoesProdutos = resultados);
    } catch (e) {
      debugPrint('Erro ao buscar sugestões: $e');
    }
  }

  Future<void> buscarClientesDinamicamente(String termo) async {
    if (termo.trim().isEmpty) {
      setState(() => sugestoesClientes = []);
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('clientes')
          .get();

      final termoLower = termo.toLowerCase();
      final resultados = query.docs
          .where((doc) {
            final data = doc.data();
            final nome = (data['nome'] ?? '').toString().toLowerCase();
            final telefone = (data['telefone'] ?? '').toString().toLowerCase();
            return nome.contains(termoLower) || telefone.contains(termoLower);
          })
          .map((doc) => doc.data())
          .toList();

      setState(() => sugestoesClientes = resultados);
    } catch (e) {
      debugPrint('Erro ao buscar clientes dinamicamente: $e');
    }
  }

  Future<void> _mostrarResumoVendaDialog(
    double totalVenda,
    double totalPago,
  ) async {
    final nomeCliente = clienteNomeController.text.trim().isEmpty
        ? '---'
        : clienteNomeController.text.trim();
    final valorFrete = freteController.text.trim().isEmpty
        ? 0.0
        : _converterParaDouble(freteController.text.trim());

    final totalComFrete = totalVenda + valorFrete;
    final troco = (totalPago - totalComFrete).clamp(0, double.infinity);

    double totalDesconto = 0.0;
    double totalPromocional = 0.0;
    bool houvePromocao = false;

    for (var item in itensVendidos) {
      final desconto = item['desconto'] ?? 0.0;
      final promocional = item['precoPromocional'] ?? 0.0;
      final quantidade = item['quantidade'] ?? 1;

      if (desconto > 0) {
        totalDesconto += desconto * quantidade;
      }

      if (promocional > 0) {
        final precoOriginal = item['preco'] ?? 0.0;
        totalPromocional += (precoOriginal - promocional) * quantidade;
        houvePromocao = true;
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('✅ Venda Concluída'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('👤 Cliente: $nomeCliente'),
            Text('🚚 Frete: R\$ ${valorFrete.toStringAsFixed(2)}'),
            Text('💰 Total: R\$ ${totalVenda.toStringAsFixed(2)}'),
            if (totalDesconto > 0)
              Text('🔻 Descontos: R\$ ${totalDesconto.toStringAsFixed(2)}'),
            if (houvePromocao)
              Text('🔥 Promoções: R\$ ${totalPromocional.toStringAsFixed(2)}'),
            Text('💳 Pago: R\$ ${totalPago.toStringAsFixed(2)}'),
            Text('💵 Troco: R\$ ${troco.toStringAsFixed(2)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);

              if (tipoNotaSelecionada == 'fiscal') {
                _emitirNotaFiscal(itensVendidos, valorFrete, pagamentos);
              } else {
                _imprimirNota(
                  List.from(itensVendidos),
                  valorFrete,
                  List.from(pagamentos),
                  _calcularTotalPago(),
                );
              }
            },
            child: const Text('🖨️ Imprimir Nota'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('❌ Não Imprimir'),
          ),
        ],
      ),
    );
  }

  /// Função para definir automaticamente o NCM de acordo com a categoria
  String _definirNCM(String categoria) {
    switch (categoria.toUpperCase()) {
      case "LINGERIE":
      case "SUTIÃ":
      case "CALCINHA":
      case "CINTA MODELADORA":
      case "MODELADOR":
        return "62121000"; // Lingerie, cintas, sutiãs, etc.

      case "BOLSAS":
        return "42022220"; // Bolsas de uso pessoal

      case "MODA PRAIA":
      case "BIQUINI":
      case "MAIÔ":
        return "62111100"; // Roupas de banho femininas

      case "JALECOS":
      case "UNIFORMES":
        return "62113300"; // Vestuário de trabalho (jalecos/uniformes)

      case "ACESSÓRIOS":
        return "61171000"; // Acessórios de vestuário (ex: echarpes, lenços)

      case "PERFUMES":
      case "COSMÉTICOS":
        return "33030010"; // Perfumes e águas-de-colônia

      default:
        return "62121000"; // Outros (usar como fallback genérico)
    }
  }

  Future<void> _imprimirDanfeTermica(String danfeUrl) async {
    try {
      // 1) Baixar o PDF da DANFE pelo link da Webmania
      final response = await http.get(Uri.parse(danfeUrl));

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível baixar a DANFE (HTTP ${response.statusCode}).',
            ),
          ),
        );
        return;
      }

      final pdfBytes = response.bodyBytes;

      // 2) Buscar a impressora térmica pelo nome (igual você já faz)
      final impressoras = await Printing.listPrinters();
      final impressoraNota = impressoras.firstWhere(
        (p) => p.name.toUpperCase() == 'IMPRESSORA NOTA',
        orElse: () {
          throw Exception('Impressora IMPRESSORA NOTA não encontrada');
        },
      );

      // 3) Enviar o PDF da DANFE diretamente para a impressora
      await Printing.directPrintPdf(
        printer: impressoraNota,
        onLayout: (format) async => pdfBytes,
      );
    } catch (e) {
      debugPrint('Erro ao imprimir DANFE: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao imprimir DANFE: $e')));
    }
  }

  Future<void> _emitirNotaFiscal(
    List<Map<String, dynamic>> itensVendidos,
    double valorFrete,
    List<Map<String, dynamic>> pagamentos,
  ) async {
    if (itensVendidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Adicione produtos antes de finalizar.")),
      );
      return;
    }

    try {
      // Total dos itens
      final double totalProdutos = _calcularTotalGeral();
      final double frete = valorFrete;
      final double totalNota = totalProdutos + frete;

      // ===== PRODUTOS (formato Webmania) =====
      final List<Map<String, dynamic>> produtos = itensVendidos.map((item) {
        final int qtd = (item['quantidade'] ?? 1) as int;
        final double precoUnit = (item['precoFinal'] ?? 0.0 as num).toDouble();
        final double subtotal = precoUnit * qtd;

        final categoria = (item['categoria'] ?? '').toString();
        final ncm = _definirNCM(categoria);

        return {
          "nome": item['produtoNome'] ?? 'Produto',
          "ncm": ncm,
          "cest": "2806500", // depois podemos refinar
          "quantidade": qtd,
          "unidade": "UN",
          "peso": "0.000",
          "origem": 0,
          "subtotal": double.parse(subtotal.toStringAsFixed(2)),
          "total": double.parse(subtotal.toStringAsFixed(2)),
          "classe_imposto": "REF408415301", // sua classe criada no painel
        };
      }).toList();

      // ===== CLIENTE =====
      // Como na NFC-e o consumidor pode ser não identificado,
      // se você não tiver CPF salvo, mandamos só o indicador:
      final Map<String, dynamic> clienteJson;
      if (clienteSelecionado != null &&
          (clienteSelecionado!['cpf'] ?? '').toString().isNotEmpty) {
        clienteJson = {
          "cpf": (clienteSelecionado!['cpf'] ?? '').toString().replaceAll(
            RegExp(r'\D'),
            '',
          ),
          "nome_completo": clienteSelecionado!['nome'] ?? 'Consumidor',
        };
      } else {
        clienteJson = {
          "indicador_inscricao_estadual":
              9, // consumidor final não contribuinte
        };
      }

      // ===== PEDIDO (pagamento, frete, total) =====
      final Map<String, dynamic> pedidoJson = {
        "pagamento": 1, // 1 = pagamento à vista (básico p/ começar)
        "presenca": 1, // 1 = operação presencial
        "modalidade_frete": 9, // 9 = sem frete / por conta do destinatário
        "frete": double.parse(frete.toStringAsFixed(2)),
        "desconto": 0,
        "total": double.parse(totalNota.toStringAsFixed(2)),
      };

      // ===== CORPO FINAL (formato Webmania) =====
      final Map<String, dynamic> body = {
        "operacao": 1, // 1 = saída
        "natureza_operacao": "Venda ao consumidor",
        "modelo": 2, // 2 = NFC-e
        "finalidade": 1, // 1 = normal
        "ambiente": 1, // 1 = produção
        "cliente": clienteJson,
        "produtos": produtos,
        "pedido": pedidoJson,
      };

      // Envia para o backend (que chama a Webmania)
      final resultado = await _nfceService.emitirNfce(body);

      // Esperado algo como { ok: true, retorno: { status: 'aprovado', ... } }
      final retorno =
          resultado['retorno'] ?? resultado['resultado'] ?? resultado;

      if (resultado['ok'] == true &&
          retorno is Map &&
          retorno['status'] == 'aprovado') {
        debugPrint('✅ NFC-e aprovada. Chave: ${retorno['chave']}');
        debugPrint('DANFE: ${retorno['danfe']}');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC-e emitida com sucesso!')),
        );

        // 👇 aqui vem a mágica: imprimir a DANFE automaticamente
        final danfeUrl = retorno['danfe'] as String?;
        if (danfeUrl != null && danfeUrl.isNotEmpty) {
          await _imprimirDanfeTermica(danfeUrl);
        } else {
          debugPrint('⚠ DANFE não retornada pela API.');
        }
      } else {
        debugPrint('❌ Erro ao emitir NFC-e: $resultado');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao emitir NFC-e: $resultado')),
        );
      }
    } catch (e, stack) {
      debugPrint('❌ Erro ao emitir NFC-e: $e');
      debugPrint(stack.toString());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao emitir NFC-e: $e')));
    }
  }

  Map<String, dynamic> montarNfce(
    List<Map<String, dynamic>> itens,
    double frete,
    List<Map<String, dynamic>> pagamentos,
  ) {
    return {
      "infNFe": {
        "versao": "4.00",
        "ide": {
          "cUF": 15,
          "natOp": "Venda ao consumidor",
          "serie": 2,
          "nNF": DateTime.now().millisecondsSinceEpoch % 999999,
          "dhEmi": DateTime.now().toIso8601String(),
          "tpNF": 1,
          "idDest": 1,
          "cMunFG": "1500107",
          "tpImp": 4,
          "tpEmis": 1,
          "finNFe": 1,
          "indFinal": 1,
          "indPres": 1,
          "procEmi": 0,
          "verProc": "1.0",
        },
        "emit": {
          "CNPJ": "47179855000195",
          "xNome": "SENHORITA CINTA MODELADORAS LTDA",
          "xFant": "SENHORITA CINTA MODELADORAS",
          "enderEmit": {
            "xLgr": "Rua Barao do Rio Branco",
            "nro": "1836",
            "xBairro": "Centro",
            "cMun": "1500107",
            "xMun": "Abaetetuba",
            "UF": "PA",
            "CEP": "68440000",
            "Fone": "9181480881",
          },
          "IE": "158462106",
          "CRT": 1,
        },
        "det": itens.map((item) {
          final quantidade = item['quantidade'] ?? 1;
          final preco = item['precoFinal'] ?? 0.0;

          return {
            "nItem": itens.indexOf(item) + 1,
            "prod": {
              "cProd": item['produtoId'],
              "xProd": item['produtoNome'],
              "NCM": "62121000",
              "CFOP": "5102",
              "uCom": "UN",
              "qCom": quantidade.toString(),
              "vUnCom": preco.toStringAsFixed(2),
              "vProd": (preco * quantidade).toStringAsFixed(2),
              "indTot": "1",
            },
            "imposto": {
              "ICMS": {
                "ICMSSN102": {"orig": 0, "CSOSN": "102"},
              },
            },
          };
        }).toList(),
        "total": {
          "ICMSTot": {
            "vProd": itens.fold(
              0.0,
              (total, item) =>
                  total + (item['precoFinal'] * item['quantidade']),
            ),
            "vNF":
                itens.fold(
                  0.0,
                  (total, item) =>
                      total + (item['precoFinal'] * item['quantidade']),
                ) +
                frete,
          },
        },
        "pag": {
          "detPag": pagamentos
              .map((p) => {"tPag": "01", "vPag": p['valor']})
              .toList(),
        },
      },
      "ambiente": "producao",
    };
  }

  Future<void> _imprimirNota(
    List<Map<String, dynamic>> itens,
    double frete,
    List<Map<String, dynamic>> pagamentos,
    double totalPago,
  ) async {
    final nomeLoja = await buscarNomeLoja();

    // Cria o documento sem fontes personalizadas (usa padrão)
    final pdf = pw.Document();

    final valorFrete = frete;

    // Calcular total dos produtos vendidos
    double totalVenda = itens.fold(0.0, (total, item) {
      final preco = item['precoFinal'] ?? 0.0;
      final qtd = item['quantidade'] ?? 0;
      return total + (preco * qtd);
    });

    final formasPagamento = pagamentos.map((p) => p['forma']).join(", ");
    final troco = (totalPago - totalVenda - frete).clamp(0, double.infinity);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(58 * PdfPageFormat.mm, double.infinity),
        margin: pw.EdgeInsets.zero,
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    "SENHORITA CINTAS",
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    "COMPROVANTE PAGAMENTO",
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  "Funcionário: ${funcionarioSelecionado ?? '-'}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  "Cliente: ${clienteNomeController.text.isNotEmpty ? clienteNomeController.text : 'CONSUMIDOR'}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.Text("Loja: $nomeLoja", style: pw.TextStyle(fontSize: 8)),
                pw.Text(
                  "Data: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  "Itens:",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
                pw.Divider(thickness: 1),
                ...itens.map((item) {
                  final nome = item['produtoNome'] ?? '';
                  final tamanho = item['tamanho'] ?? '';
                  final cor = item['cor'] ?? '';
                  final qtd = item['quantidade'] ?? 0;
                  final preco = item['precoFinal'] ?? 0.0;
                  final precoPromocional = item['precoPromocional'] ?? 0.0;
                  final desconto = item['desconto'] ?? 0.0;

                  final precoUnitario = preco;
                  final precoTotal = precoUnitario * qtd;

                  final temPromocao =
                      precoPromocional > 0 && precoPromocional < preco;
                  final temDesconto = desconto > 0;

                  final precoUnitarioTexto = temPromocao
                      ? "R\$ ${precoPromocional.toStringAsFixed(2)} (Promo)"
                      : temDesconto
                      ? "R\$ ${preco.toStringAsFixed(2)} (-R\$ ${desconto.toStringAsFixed(2)})"
                      : "R\$ ${preco.toStringAsFixed(2)}";

                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "$nome ${tamanho.isNotEmpty ? '($tamanho' : ''}${tamanho.isNotEmpty && cor.toString().isNotEmpty ? ' • ' : ''}${cor.toString().isNotEmpty ? cor : ''}${tamanho.isNotEmpty ? ')' : ''}",
                        style: pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        "Qtd: $qtd x $precoUnitarioTexto = R\$ ${precoTotal.toStringAsFixed(2)}",
                        style: pw.TextStyle(fontSize: 8),
                      ),
                      pw.SizedBox(height: 2),
                    ],
                  );
                }),
                pw.Divider(thickness: 0.5),
                if (valorFrete > 0)
                  pw.Text(
                    "Frete: R\$ ${valorFrete.toStringAsFixed(2)}",
                    style: pw.TextStyle(fontSize: 8),
                  ),
                if (valorFrete > 0)
                  pw.Text(
                    "Total c/ Frete: R\$ ${(totalVenda + valorFrete).toStringAsFixed(2)}",
                    style: pw.TextStyle(fontSize: 8),
                  ),
                pw.Text(
                  "Total Venda: R\$ ${totalVenda.toStringAsFixed(2)}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  "Total Pago: R\$ ${totalPago.toStringAsFixed(2)}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  "Troco: R\$ ${troco.toStringAsFixed(2)}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  "Forma de Pagamento: ${formasPagamento.isNotEmpty ? formasPagamento : 'Não informado'}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pw.Text(
                    "Obrigada pela preferência!",
                    style: pw.TextStyle(fontSize: 9),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // Buscar impressora pelo nome
    final impressoras = await Printing.listPrinters();
    final impressoraNota = impressoras.firstWhere(
      (p) => p.name.toUpperCase() == 'IMPRESSORA NOTA',
      orElse: () =>
          throw Exception('Impressora IMPRESSORA NOTA não encontrada'),
    );

    // Imprimir diretamente
    await Printing.directPrintPdf(
      printer: impressoraNota,
      onLayout: (format) async => pdf.save(),
    );
  }

  void adicionarProdutoAtual() {
    if (_formKey.currentState!.validate() && produtoEncontrado != null) {
      final precoPadrao = _converterParaDouble(
        produtoEncontrado!['precoVenda'].toString(),
      );
      final precoPromocional = _converterParaDouble(
        precoPromocionalController.text,
      );
      final precoBase = precoPromocional > 0 ? precoPromocional : precoPadrao;

      double desconto = 0.0;
      final descontoText = descontoController.text.trim();

      if (descontoText.endsWith('%')) {
        final perc =
            double.tryParse(
              descontoText.replaceAll('%', '').replaceAll(',', '.'),
            ) ??
            0.0;
        desconto = precoBase * (perc / 100);
      } else if (descontoText.isNotEmpty) {
        desconto = double.tryParse(descontoText.replaceAll(',', '.')) ?? 0.0;
      }

      final precoComDesconto = (precoBase - desconto).clamp(0, double.infinity);

      final item = {
        'produtoId': produtoEncontrado?['id'],
        'docId': produtoEncontrado?['docId'], // ✅ Inclui o document ID aqui
        'produtoNome': produtoEncontrado?['nome'],
        'codigoBarras': produtoEncontrado?['codigoBarras'],
        'precoVenda': precoPadrao,
        'precoPromocional': precoPromocional > 0 ? precoPromocional : null,
        'desconto': desconto > 0 ? desconto : null,
        'quantidade': quantidade,
        'tamanho': tamanhoSelecionado ?? '',
        'precoFinal': precoComDesconto,
        'cor': corSelecionada ?? '', // <-- NOVO
        'categoria':
            produtoEncontrado?['categoria'], // <-- Útil para relatórios
      };
      // Se o produto usa grade Tamanho×Cor, exigir ambos
      final usaGrade =
          (produtoEncontrado?['tamanhosCores'] as Map?)?.isNotEmpty == true;
      if (usaGrade) {
        if (tamanhoSelecionado == null || corSelecionada == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecione tamanho e cor.')),
          );
          return;
        }
      }

      setState(() {
        itensVendidos.add(item);
        buscaController.clear();
        precoPromocionalController.clear();
        descontoController.clear();
        produtoEncontrado = null;
        tamanhoSelecionado = null;
        quantidade = 1;
        corSelecionada = null; // <-- limpar seleção de cor
      });
    }
  }

  Future<void> realizarVenda() async {
    // trava: se já estiver processando, ignora novas chamadas
    if (_processandoVenda) return;
    _processandoVenda = true;

    final totalVenda = _calcularTotalGeral();
    final totalPago = _calcularTotalPago();

    if (itensVendidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um produto')),
      );
      _processandoVenda = false;
      return;
    }

    if (pagamentos.isEmpty || totalPago < totalVenda) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Valor pago insuficiente. Total: R\$ ${totalVenda.toStringAsFixed(2)}',
          ),
        ),
      );
      _processandoVenda = false;
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    try {
      double custoRealTotal = 0;
      final List<Map<String, dynamic>> itensComValorReal = [];

      // 1) Enriquecer itens com valorReal (lendo da coleção 'produtos')
      for (final item in itensVendidos) {
        final produtoId = item['produtoId'];
        final quantidadeVendida = item['quantidade'];

        double valorReal = 0;

        final produtoQuery = await firestore
            .collection('produtos')
            .where('codigoBarras', isEqualTo: produtoId)
            .limit(1)
            .get();

        if (produtoQuery.docs.isNotEmpty) {
          final data = produtoQuery.docs.first.data();
          valorReal = (data['valorReal'] ?? 0).toDouble();
        }

        custoRealTotal += valorReal * (quantidadeVendida as num).toDouble();

        final itemAtualizado = Map<String, dynamic>.from(item);
        itemAtualizado['valorReal'] = valorReal;
        itensComValorReal.add(itemAtualizado);
      }

      final categorias = itensVendidos
          .map((item) => item['categoria'] ?? 'Sem categoria')
          .toSet()
          .toList();

      // 2) Registrar a venda (apenas 1x)
      await firestore.collection('vendas').add({
        'produtoId': produtoEncontrado?['docId'] ?? produtoEncontrado?['id'],
        'produtoNome': produtoEncontrado?['nome'],
        'codigoBarras': produtoEncontrado?['codigoBarras'],
        'quantidade': quantidade,
        'tamanho': tamanhoSelecionado ?? '',
        'cor': corSelecionada ?? '',
        'dataVenda': DateTime.now(),
        'totalVenda': totalVenda,
        'tipoNota': tipoNotaSelecionada,
        'itens': itensComValorReal,
        'pagamentos': pagamentos,
        'totalPago': totalPago,
        'troco': (totalPago - totalVenda).clamp(0, double.infinity),
        'frete': freteController.text.trim().isNotEmpty
            ? _converterParaDouble(freteController.text.trim())
            : null,
        'cliente': clienteNomeController.text.trim().isNotEmpty
            ? {
                'nome': clienteNomeController.text.trim(),
                'telefone': clienteTelefoneController.text.trim(),
              }
            : null,
        'clienteId': clienteSelecionado?['id'],
        'usuarioId': FirebaseAuth.instance.currentUser?.uid,
        'formasPagamento': pagamentos.map((p) => p['forma']).toList(),
        'lojaSelecionada': FirebaseAuth.instance.currentUser?.uid,
        'funcionario': funcionarioSelecionado ?? '---',
        'valorReal': custoRealTotal,
        'categorias': categorias,
        'precoPromocional': itensComValorReal.any(
          (item) => item['precoPromocional'] != null,
        ),
        'desconto': itensComValorReal.any((item) => item['desconto'] != null)
            ? _calcularDescontoTotal()
            : 0.0,
        'precoFinal': itensComValorReal.fold<double>(
          0.0,
          (total, item) =>
              total +
              (item['precoFinal'] as double) * (item['quantidade'] as int),
        ),
      });

      // 3) Dar baixa SOMENTE na coleção 'produtos'
      for (final item in itensComValorReal) {
        final String? produtoDocId = item['docId'] as String?;
        if (produtoDocId == null || produtoDocId.isEmpty) {
          final cb = item['produtoId'];
          final q = await firestore
              .collection('produtos')
              .where('codigoBarras', isEqualTo: cb)
              .limit(1)
              .get();
          if (q.docs.isEmpty) continue;

          final produtoRef = q.docs.first.reference;

          final tamanho = (item['tamanho'] ?? '') as String;
          final cor = (item['cor'] ?? '') as String;
          final quantidadeVendida = (item['quantidade'] ?? 0) as int;

          if (tamanho.isNotEmpty && cor.isNotEmpty) {
            batch.update(produtoRef, {
              'tamanhosCores.$tamanho.$cor': FieldValue.increment(
                -quantidadeVendida,
              ),
              'tamanhos.$tamanho': FieldValue.increment(
                -quantidadeVendida,
              ), // retrocompat
              'quantidade': FieldValue.increment(-quantidadeVendida),
            });
          } else if (tamanho.isNotEmpty) {
            batch.update(produtoRef, {
              'tamanhos.$tamanho': FieldValue.increment(-quantidadeVendida),
              'quantidade': FieldValue.increment(-quantidadeVendida),
            });
          } else {
            batch.update(produtoRef, {
              'quantidade': FieldValue.increment(-quantidadeVendida),
            });
          }
          continue;
        }

        final produtoRef = firestore.collection('produtos').doc(produtoDocId);

        final tamanho = (item['tamanho'] ?? '') as String;
        final cor = (item['cor'] ?? '') as String;
        final quantidadeVendida = (item['quantidade'] ?? 0) as int;

        if (tamanho.isNotEmpty && cor.isNotEmpty) {
          batch.update(produtoRef, {
            'tamanhosCores.$tamanho.$cor': FieldValue.increment(
              -quantidadeVendida,
            ),
            'tamanhos.$tamanho': FieldValue.increment(
              -quantidadeVendida,
            ), // retrocompat
            'quantidade': FieldValue.increment(-quantidadeVendida),
          });
        } else if (tamanho.isNotEmpty) {
          batch.update(produtoRef, {
            'tamanhos.$tamanho': FieldValue.increment(-quantidadeVendida),
            'quantidade': FieldValue.increment(-quantidadeVendida),
          });
        } else {
          batch.update(produtoRef, {
            'quantidade': FieldValue.increment(-quantidadeVendida),
          });
        }
      }

      await batch.commit();

      // 4) Cadastrar cliente se ainda não existe
      if (clienteNomeController.text.trim().isNotEmpty) {
        final clienteExiste = await firestore
            .collection('clientes')
            .where('nome', isEqualTo: clienteNomeController.text.trim())
            .where('telefone', isEqualTo: clienteTelefoneController.text.trim())
            .get();

        if (clienteExiste.docs.isEmpty) {
          await firestore.collection('clientes').add({
            'nome': clienteNomeController.text.trim(),
            'telefone': clienteTelefoneController.text.trim(),
            'dataCadastro': DateTime.now().toIso8601String(),
          });
        }
      }

      await _mostrarResumoVendaDialog(totalVenda, totalPago);

      setState(() {
        itensVendidos.clear();
        pagamentos.clear();
        freteController.clear();
        clienteNomeController.clear();
        clienteTelefoneController.clear();
        clienteSelecionado = null;
      });
    } catch (e, stack) {
      debugPrint('❌ Erro ao registrar venda: $e');
      debugPrint(stack.toString());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao registrar a venda: $e')));
    } finally {
      _processandoVenda = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamanhosMap = produtoEncontrado?['tamanhos'] as Map<String, dynamic>?;
    final Map<String, dynamic>? tamanhosCoresMap =
        produtoEncontrado?['tamanhosCores'] as Map<String, dynamic>?;

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
                'VENDER PRODUTO',
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
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                '🔎 Buscar Produto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
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
                      : const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (debounceTimer?.isActive ?? false) debounceTimer!.cancel();
                  debounceTimer = Timer(const Duration(milliseconds: 300), () {
                    buscarProdutosSugestoes(value.trim());
                  });
                },
                onFieldSubmitted: (value) async {
                  FocusScope.of(context).unfocus(); // <- remove o foco do campo
                  await buscarProdutosSugestoes(value.trim());
                  if (sugestoesProdutos.isNotEmpty) {
                    final produto = sugestoesProdutos.first;
                    setState(() {
                      produtoEncontrado = produto;
                      buscaController.text = produto['nome'];
                      sugestoesProdutos = [];
                    });
                  }
                },
              ),

              if (sugestoesProdutos.isNotEmpty)
                ...sugestoesProdutos.map(
                  (produto) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.inventory),
                      title: Text(produto['nome'] ?? 'Produto sem nome'),
                      subtitle: Text('Código: ${produto['codigoBarras']}'),
                      onTap: () {
                        setState(() {
                          produtoEncontrado = produto;
                          sugestoesProdutos = [];
                          buscaController.text = produto['nome'];
                        });
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (produtoEncontrado != null)
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((produtoEncontrado?['foto'] ?? '')
                            .toString()
                            .isNotEmpty)
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                produtoEncontrado!['foto'],
                                height: 120,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          '🛍️ Produto: ${produtoEncontrado?['nome'] ?? '---'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '🆔 Código: ${produtoEncontrado?['codigoBarras'] ?? '---'}',
                        ),
                        Text(
                          '📋 Descrição: ${produtoEncontrado?['descricao'] ?? '---'}',
                        ),
                        Text(
                          '💲 Preço: R\$ ${_formatarPreco(produtoEncontrado?['precoVenda'])}',
                        ),

                        const SizedBox(height: 10),
                        TextFormField(
                          controller: precoPromocionalController,
                          decoration: const InputDecoration(
                            labelText: 'Preço Promocional (opcional)',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) return null;
                            final val = double.tryParse(
                              value.replaceAll(',', '.'),
                            );
                            if (val == null || val <= 0)
                              return 'Digite um valor válido ou deixe em branco';
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: descontoController,
                          decoration: const InputDecoration(
                            labelText: 'Desconto (R\$ ou %)',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.text,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty)
                              return null;
                            final text = value.trim();
                            if (text.endsWith('%')) {
                              final parsed = double.tryParse(
                                text.replaceAll('%', '').replaceAll(',', '.'),
                              );
                              if (parsed == null || parsed < 0 || parsed > 100)
                                return 'Porcentagem inválida';
                            } else {
                              final parsed = double.tryParse(
                                text.replaceAll(',', '.'),
                              );
                              if (parsed == null || parsed < 0)
                                return 'Valor inválido';
                            }
                            return null;
                          },
                        ),

                        // Preferência: se houver grade Tamanho×Cor, usa ela
                        if (tamanhosCoresMap != null &&
                            tamanhosCoresMap.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: tamanhoSelecionado,
                            decoration: const InputDecoration(
                              labelText: 'Tamanho',
                              border: OutlineInputBorder(),
                            ),
                            items: tamanhosCoresMap.keys
                                .where((tam) {
                                  final cores =
                                      (tamanhosCoresMap[tam] as Map?)
                                          ?.cast<String, dynamic>() ??
                                      {};
                                  // só mostra tamanhos que possuem alguma cor com estoque > 0
                                  return cores.values.any(
                                    (q) => (q is num) && q.toInt() > 0,
                                  );
                                })
                                .map(
                                  (tam) => DropdownMenuItem<String>(
                                    value: tam,
                                    child: Text(tam),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() {
                              tamanhoSelecionado = value;
                              corSelecionada = null; // reset ao trocar tamanho
                            }),
                            validator: (value) =>
                                value == null ? 'Selecione um tamanho' : null,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: corSelecionada,
                            decoration: const InputDecoration(
                              labelText: 'Cor',
                              border: OutlineInputBorder(),
                            ),
                            items: (tamanhoSelecionado == null)
                                ? const []
                                : ((tamanhosCoresMap[tamanhoSelecionado]
                                                  as Map?)
                                              ?.cast<String, dynamic>() ??
                                          {})
                                      .entries
                                      .where(
                                        (e) =>
                                            (e.value is num) &&
                                            (e.value as num).toInt() > 0,
                                      )
                                      .map(
                                        (e) => DropdownMenuItem<String>(
                                          value: e.key,
                                          child: Text(
                                            '${e.key} (Estoque: ${(e.value as num).toInt()})',
                                          ),
                                        ),
                                      )
                                      .toList(),
                            onChanged: (value) =>
                                setState(() => corSelecionada = value),
                            validator: (value) =>
                                value == null ? 'Selecione uma cor' : null,
                          ),
                        ]
                        // fallback para o modelo antigo por Tamanho apenas
                        else if (tamanhosMap != null &&
                            tamanhosMap.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: tamanhoSelecionado,
                            decoration: const InputDecoration(
                              labelText: 'Tamanho',
                              border: OutlineInputBorder(),
                            ),
                            items: tamanhosMap.entries
                                .where(
                                  (e) =>
                                      (e.value is num) &&
                                      (e.value as num).toInt() > 0,
                                )
                                .map(
                                  (e) => DropdownMenuItem<String>(
                                    value: e.key,
                                    child: Text(
                                      '${e.key} (Estoque: ${(e.value as num).toInt()})',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => tamanhoSelecionado = value),
                            validator: (value) =>
                                value == null ? 'Selecione um tamanho' : null,
                          ),
                        ],

                        const SizedBox(height: 10),
                        TextFormField(
                          initialValue: quantidade.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Quantidade',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final val = int.tryParse(value ?? '');
                            if (val == null || val <= 0)
                              return 'Quantidade inválida';

                            int estoque = 9999;

                            // 1) Modelo novo: Tamanho×Cor
                            if (tamanhosCoresMap != null &&
                                tamanhosCoresMap.isNotEmpty) {
                              if (tamanhoSelecionado == null ||
                                  corSelecionada == null) {
                                return 'Selecione tamanho e cor';
                              }
                              final cores =
                                  (tamanhosCoresMap[tamanhoSelecionado] as Map?)
                                      ?.cast<String, dynamic>() ??
                                  {};
                              final q = (cores[corSelecionada] ?? 0);
                              estoque = (q is num) ? q.toInt() : 0;
                            }
                            // 2) Modelo antigo: só Tamanho
                            else if (tamanhosMap != null &&
                                tamanhosMap.isNotEmpty) {
                              if (tamanhoSelecionado == null)
                                return 'Selecione um tamanho';
                              final q = (tamanhosMap[tamanhoSelecionado] ?? 0);
                              estoque = (q is num) ? q.toInt() : 0;
                            }
                            // 3) Sem variação: usa 'quantidade' total
                            else if (produtoEncontrado?['quantidade'] != null) {
                              estoque =
                                  (produtoEncontrado!['quantidade'] as num)
                                      .toInt();
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (itensVendidos.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  '🧾 Itens Vendidos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                ...itensVendidos.map(
                  (item) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      title: Text(
                        '${item['produtoNome']} (${item['quantidade']})',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item['precoPromocional'] != null)
                            Text(
                              'Promo: R\$ ${_formatarPreco(item['precoPromocional'])}',
                            ),
                          if (item['desconto'] != null)
                            Text(
                              'Desconto: -R\$ ${_formatarPreco(item['desconto'])}',
                            ),
                          Text(
                            'Final: R\$ ${_formatarPreco(item['precoFinal'])}',
                          ),
                          Text('Tam: ${item['tamanho']}'),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            setState(() => itensVendidos.remove(item)),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                Text(
                  '🔻 Desconto Total: R\$ ${_calcularDescontoTotal().toStringAsFixed(2)}',
                ),
                Text(
                  '💰 Total Geral: R\$ ${_calcularTotalGeral().toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],

              if (itensVendidos.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  '💳 Pagamento',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: valorPagamentoController,
                  decoration: const InputDecoration(
                    labelText: 'Valor do pagamento',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: formaSelecionada,
                  decoration: const InputDecoration(
                    labelText: 'Forma de Pagamento',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pix', child: Text('Pix')),
                    DropdownMenuItem(
                      value: 'credito',
                      child: Text('Cartão de Crédito'),
                    ),
                    DropdownMenuItem(
                      value: 'debito',
                      child: Text('Cartão de Débito'),
                    ),
                    DropdownMenuItem(
                      value: 'dinheiro',
                      child: Text('Dinheiro'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => formaSelecionada = value),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    final valor =
                        double.tryParse(
                          valorPagamentoController.text.replaceAll(',', '.'),
                        ) ??
                        0;

                    if (valor <= 0 || formaSelecionada == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Preencha valor e forma de pagamento válidos',
                          ),
                        ),
                      );
                      return;
                    }

                    setState(() {
                      pagamentos.add({
                        'forma': formaSelecionada,
                        'valor': valor,
                      });
                      mostrarCampoFuncionario = true;
                      valorPagamentoController.clear();
                      formaSelecionada = null;
                    });

                    // 💡 calcula após adicionar
                    final totalPago = _calcularTotalPago();
                    final totalComFrete = _totalComFrete();
                    final troco = (totalPago - totalComFrete).clamp(
                      0,
                      double.infinity,
                    );
                    final faltante = (totalComFrete - totalPago).clamp(
                      0,
                      double.infinity,
                    );

                    // Mostra feedback instantâneo
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          troco > 0
                              ? '💵 Troco: R\$ ${troco.toStringAsFixed(2)}'
                              : '💳 Falta pagar: R\$ ${faltante.toStringAsFixed(2)}',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },

                  icon: const Icon(Icons.attach_money),
                  label: const Text('Adicionar Pagamento'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, // Fundo verde
                    foregroundColor: Colors.black, // Texto e ícone pretos
                  ),
                ),
                const SizedBox(height: 10),
                ...pagamentos.map(
                  (p) => ListTile(
                    title: Text('R\$ ${p['valor'].toStringAsFixed(2)}'),
                    subtitle: Text('Forma: ${p['forma']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => setState(() => pagamentos.remove(p)),
                    ),
                  ),
                ),
                const Divider(),
                Text(
                  'Total Pago: R\$ ${_calcularTotalPago().toStringAsFixed(2)}',
                ),
                Text(
                  'Total (itens + frete): R\$ ${_totalComFrete().toStringAsFixed(2)}',
                ),
                if (_faltanteAtual() > 0)
                  Text(
                    'Restante: R\$ ${_faltanteAtual().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                if (_trocoAtual() > 0)
                  Text(
                    'Troco: R\$ ${_trocoAtual().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
              ],
              const SizedBox(height: 20),

              // Botão para exibir campos de cliente
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => mostrarCamposCliente = !mostrarCamposCliente);
                },
                icon: const Icon(Icons.person_add),
                label: Text(
                  mostrarCamposCliente
                      ? 'Ocultar Cliente'
                      : 'Adicionar Cliente',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade100,
                  foregroundColor: Colors.black,
                ),
              ),
              if (mostrarCamposCliente) ...[
                const SizedBox(height: 10),
                const Text(
                  '👤 Cliente (opcional)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: clienteNomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do cliente',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    if (debounceClienteTimer?.isActive ?? false)
                      debounceClienteTimer!.cancel();
                    debounceClienteTimer = Timer(
                      const Duration(milliseconds: 300),
                      () {
                        buscarClientesDinamicamente(value);
                      },
                    );
                  },
                ),
                if (sugestoesClientes.isNotEmpty)
                  ...sugestoesClientes.map(
                    (cliente) => ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(cliente['nome'] ?? ''),
                      subtitle: Text(cliente['telefone'] ?? ''),
                      onTap: () {
                        setState(() {
                          clienteSelecionado = cliente;
                          clienteNomeController.text = cliente['nome'] ?? '';
                          clienteTelefoneController.text =
                              cliente['telefone'] ?? '';
                          sugestoesClientes = [];
                        });
                      },
                    ),
                  ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: clienteTelefoneController,
                  decoration: const InputDecoration(
                    labelText: 'Telefone do cliente',
                    hintText: 'Ex: (99) 99999-9999',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
              const SizedBox(height: 20),
              // Botão para exibir campo de frete
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => mostrarCampoFrete = !mostrarCampoFrete);
                },
                icon: const Icon(Icons.local_shipping),
                label: Text(
                  mostrarCampoFrete ? 'Ocultar Frete' : 'Adicionar Frete',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade100,
                  foregroundColor: Colors.black,
                ),
              ),

              if (mostrarCampoFrete) ...[
                const SizedBox(height: 10),
                const Text(
                  '🚚 Frete (opcional)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: freteController,
                  decoration: const InputDecoration(
                    labelText: 'Valor do frete',
                    hintText: 'Ex: 10.00',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],

              const SizedBox(height: 20),
              const Text(
                '🖨️ Tipo de Nota',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: tipoNotaSelecionada,
                decoration: const InputDecoration(
                  labelText: 'Escolha o tipo de nota',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'pagamento',
                    child: Text('Nota de Pagamento'),
                  ),

                  DropdownMenuItem(value: 'fiscal', child: Text('Nota Fiscal')),
                ],
                onChanged: (value) {
                  setState(() {
                    tipoNotaSelecionada = value!;
                  });
                },
              ),
              const SizedBox(height: 20),
              if (mostrarCampoFuncionario)
                DropdownButtonFormField<String>(
                  value: funcionarioSelecionado,
                  hint: const Text('Selecionar Funcionário'),
                  items: funcionarios.map((String nome) {
                    return DropdownMenuItem<String>(
                      value: nome,
                      child: Text(nome),
                    );
                  }).toList(),
                  onChanged: (String? novoValor) {
                    setState(() {
                      funcionarioSelecionado = novoValor;
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'Funcionário',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null ? 'Selecione um funcionário' : null,
                ),

              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _processandoVenda
                    ? null // 🔒 Desabilita o botão enquanto processa
                    : () {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_formKey.currentState!.validate()) {
                            realizarVenda();
                          }
                        });
                      },
                icon: _processandoVenda
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.shopping_cart_checkout),

                label: _processandoVenda
                    ? const Text(
                        'Processando...',
                        style: TextStyle(color: Colors.white),
                      )
                    : const Text('Finalizar Venda'),

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

Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
  return ListTile(
    leading: Icon(icon, color: Colors.white),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    onTap: onTap,
  );
}
