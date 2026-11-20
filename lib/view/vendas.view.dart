import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:senhorita/service/nfce_service.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:share_plus/share_plus.dart';

class VendasView extends StatefulWidget {
  final String lojaSelecionada;
  const VendasView({super.key, required this.lojaSelecionada});

  @override
  State<VendasView> createState() => _VendasViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);
const _erro = Color(0xFF9E2940);
const _verde = Color(0xFF23603B);

const _formas = {
  'pix': 'Pix',
  'credito': 'Cartão de crédito',
  'debito': 'Cartão de débito',
  'dinheiro': 'Dinheiro',
};

const _nomeImpressoraNota = 'IMPRESSORA NOTA';
const _destinosVirtuais = ['PDF', 'XPS', 'ONENOTE', 'FAX'];

const _notas = {
  'pagamento': 'Nota de pagamento',
  'fiscal': 'Nota fiscal (NFC-e)',
};

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

class _VendasViewState extends State<VendasView> {
  final _db = FirebaseFirestore.instance;
  final _nfceService = NfceService();
  final _formProduto = GlobalKey<FormState>();
  final _focoBusca = FocusNode();
  final buscaController = TextEditingController();
  final precoPromocionalController = TextEditingController();
  final descontoController = TextEditingController();
  final valorPagamentoController = TextEditingController();
  final freteController = TextEditingController();
  final clienteNomeController = TextEditingController();
  final clienteTelefoneController = TextEditingController();
  final _quantidade = TextEditingController(text: '1');

  final itensVendidos = <Map<String, dynamic>>[];
  final pagamentos = <Map<String, dynamic>>[];
  Map<String, dynamic>? produtoEncontrado;
  Map<String, dynamic>? clienteSelecionado;

  Future<List<_RegistroBusca>>? _catalogo;
  Future<List<_RegistroBusca>>? _clientes;
  List<_RegistroBusca> _sugestoesProdutos = [];
  List<_RegistroBusca> _sugestoesClientes = [];
  Timer? _debounceProduto;
  Timer? _debounceCliente;
  int _revisaoBuscaProduto = 0;
  int _revisaoBuscaCliente = 0;
  bool _buscandoProduto = false;
  bool _buscandoCliente = false;
  bool _buscouProduto = false;
  bool _falhaBuscaProduto = false;
  bool _falhaBuscaCliente = false;

  String _tipoUsuario = '';
  String _nomeUsuario = '';
  String _lojaPerfil = '';
  List<String> _funcionarios = [];
  String? funcionarioSelecionado;
  bool _carregandoFuncionarios = true;
  bool _falhaFuncionarios = false;
  String? _tamanho;
  String? _cor;
  String? _forma;
  String _tipoNota = 'pagamento';
  bool _mostrarCliente = false;
  bool _mostrarFrete = false;
  bool _processandoVenda = false;
  bool _saindo = false;

  bool get _ocupado => _processandoVenda || _saindo;
  String get _lojaAtiva {
    final selecionada = widget.lojaSelecionada.trim();
    return selecionada.isEmpty ? _lojaPerfil : selecionada;
  }

  Future<String> buscarNomeLoja() async =>
      _lojaAtiva.isEmpty ? 'Loja N/A' : _lojaAtiva;

  double _freteAtual() => _arredondar(_valor(freteController.text) ?? 0.0);
  double _calcularTotalGeral() => _subtotalItens(itensVendidos);
  double _calcularTotalDesconto() => _arredondar(
    itensVendidos.fold<double>(
      0,
      (soma, item) =>
          soma + (_valor(item['desconto']) ?? 0) * _inteiro(item['quantidade']),
    ),
  );
  double _calcularTotalPago() => _arredondar(
    pagamentos.fold<double>(
      0,
      (soma, pagamento) => soma + (_valor(pagamento['valor']) ?? 0),
    ),
  );
  double get _totalComFrete =>
      _arredondar(_calcularTotalGeral() + _freteAtual());
  double get _restante => (_arredondar(
    _totalComFrete - _calcularTotalPago(),
  )).clamp(0.0, double.infinity).toDouble();
  double get _troco => (_arredondar(
    _calcularTotalPago() - _totalComFrete,
  )).clamp(0.0, double.infinity).toDouble();

  @override
  void initState() {
    super.initState();
    _carregarPerfil();
    _carregarFuncionarios();
  }

  @override
  void dispose() {
    _debounceProduto?.cancel();
    _debounceCliente?.cancel();
    _focoBusca.dispose();
    for (final campo in [
      buscaController,
      precoPromocionalController,
      descontoController,
      valorPagamentoController,
      freteController,
      clienteNomeController,
      clienteTelefoneController,
      _quantidade,
    ]) {
      campo.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarPerfil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final dados = (await _db.collection('usuarios').doc(uid).get()).data();
      if (!mounted) return;
      setState(() {
        _tipoUsuario = _textoDe(dados?['tipo'], 'funcionario');
        _nomeUsuario = _textoDe(dados?['nome'], 'Usuário');
        _lojaPerfil = _textoDe(dados?['lojaSelecionada']);
      });
    } catch (erro) {
      debugPrint('Vendas • perfil: $erro');
      if (mounted) _avisar('Não foi possível carregar o perfil do usuário.');
    }
  }

  Future<void> _carregarFuncionarios() async {
    try {
      final dados = await _db
          .collection('usuarios')
          .where('tipo', whereIn: ['funcionario', 'admin'])
          .get();
      final nomes = <String>{
        for (final doc in dados.docs)
          _textoDe(doc.data()['nomeUsuario'], _textoDe(doc.data()['nome'])),
      }..remove('');
      final lista = nomes.toList()..sort();
      if (!mounted) return;
      setState(() {
        _funcionarios = lista;
        if (!lista.contains(funcionarioSelecionado))
          funcionarioSelecionado = null;
        _carregandoFuncionarios = false;
        _falhaFuncionarios = false;
      });
    } catch (erro) {
      debugPrint('Vendas • funcionários: $erro');
      if (!mounted) return;
      setState(() {
        _carregandoFuncionarios = false;
        _falhaFuncionarios = true;
      });
    }
  }

  void _avisar(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<List<_RegistroBusca>> _lerColecao(String colecao) async {
    final consulta = await _db.collection(colecao).get();
    return [
      for (final doc in consulta.docs)
        _RegistroBusca(doc.id, doc.data(), cliente: colecao == 'clientes'),
    ];
  }

  void _digitarProduto(String valor) {
    _debounceProduto?.cancel();
    final revisao = ++_revisaoBuscaProduto;
    final termo = _normalizar(valor);
    setState(() {
      _sugestoesProdutos = [];
      _buscouProduto = false;
      _falhaBuscaProduto = false;
      _buscandoProduto = termo.isNotEmpty;
      if (produtoEncontrado != null) _limparEscolha();
    });
    if (termo.isEmpty) return;
    _debounceProduto = Timer(
      const Duration(milliseconds: 250),
      () => _buscarProduto(termo, revisao),
    );
  }

  void _enviarBuscaProduto(String valor) {
    final termo = _normalizar(valor);
    if (termo.isEmpty) return;
    if (produtoEncontrado != null &&
        termo == _normalizar(_textoDe(produtoEncontrado!['nome'])))
      return;
    _debounceProduto?.cancel();
    final revisao = ++_revisaoBuscaProduto;
    setState(() {
      _buscandoProduto = true;
      _falhaBuscaProduto = false;
    });
    _buscarProduto(termo, revisao, selecionar: true);
  }

  Future<void> _buscarProduto(
    String termo,
    int revisao, {
    bool selecionar = false,
  }) async {
    final consulta = _catalogo ??= _lerColecao('produtos');
    try {
      final registros = await consulta;
      if (!mounted || revisao != _revisaoBuscaProduto) return;
      final resultados = _buscar(registros, termo, loja: _lojaAtiva);
      if (selecionar && resultados.isNotEmpty) {
        _selecionarProduto(resultados.first);
        return;
      }
      setState(() {
        _sugestoesProdutos = resultados;
        _buscandoProduto = false;
        _buscouProduto = true;
      });
    } catch (erro) {
      if (identical(_catalogo, consulta)) _catalogo = null;
      debugPrint('Vendas • busca de produtos: $erro');
      if (!mounted || revisao != _revisaoBuscaProduto) return;
      setState(() {
        _buscandoProduto = false;
        _falhaBuscaProduto = true;
      });
    }
  }

  void _selecionarProduto(_RegistroBusca produto) {
    _debounceProduto?.cancel();
    _revisaoBuscaProduto++;
    FocusScope.of(context).unfocus();
    setState(() {
      _limparEscolha();
      produtoEncontrado = produto.dados;
      buscaController.text = _textoDe(produto.dados['nome']);
      _sugestoesProdutos = [];
      _buscandoProduto = false;
      _buscouProduto = false;
      _falhaBuscaProduto = false;
    });
  }

  void _limparEscolha() {
    produtoEncontrado = null;
    _tamanho = null;
    _cor = null;
    _quantidade.text = '1';
    precoPromocionalController.clear();
    descontoController.clear();
  }

  void _digitarCliente(String valor) {
    _debounceCliente?.cancel();
    final revisao = ++_revisaoBuscaCliente;
    final termo = _normalizar(valor);
    setState(() {
      clienteSelecionado = null;
      _sugestoesClientes = [];
      _falhaBuscaCliente = false;
      _buscandoCliente = termo.isNotEmpty;
    });
    if (termo.isEmpty) return;
    _debounceCliente = Timer(const Duration(milliseconds: 250), () async {
      final consulta = _clientes ??= _lerColecao('clientes');
      try {
        final registros = await consulta;
        if (!mounted || revisao != _revisaoBuscaCliente) return;
        setState(() {
          _sugestoesClientes = _buscar(registros, termo, limite: 6);
          _buscandoCliente = false;
        });
      } catch (erro) {
        if (identical(_clientes, consulta)) _clientes = null;
        debugPrint('Vendas • busca de clientes: $erro');
        if (!mounted || revisao != _revisaoBuscaCliente) return;
        setState(() {
          _buscandoCliente = false;
          _falhaBuscaCliente = true;
        });
      }
    });
  }

  void _selecionarCliente(_RegistroBusca cliente) {
    _debounceCliente?.cancel();
    _revisaoBuscaCliente++;
    setState(() {
      clienteSelecionado = cliente.dados;
      clienteNomeController.text = _textoDe(cliente.dados['nome']);
      clienteTelefoneController.text = _textoDe(cliente.dados['telefone']);
      _sugestoesClientes = [];
      _buscandoCliente = false;
    });
  }

  void _atualizarBuscas() {
    _catalogo = null;
    _clientes = null;
    _revisaoBuscaCliente++;
    _debounceCliente?.cancel();
    setState(() {
      _sugestoesClientes = [];
      _buscandoCliente = false;
      _falhaBuscaCliente = false;
    });
    if (produtoEncontrado == null) {
      _digitarProduto(buscaController.text);
    } else {
      _avisar('A próxima busca vai recarregar o catálogo.');
    }
    if (!_carregandoFuncionarios &&
        (_falhaFuncionarios || _funcionarios.isEmpty)) {
      setState(() => _carregandoFuncionarios = true);
      _carregarFuncionarios();
    }
  }

  Future<void> _mostrarResumoVendaDialog(
    double subtotal,
    double totalPago,
  ) async {
    final valorFrete = _freteAtual();
    final totalComFrete = _arredondar(subtotal + valorFrete);
    final troco = _arredondar(
      totalPago - totalComFrete,
    ).clamp(0.0, double.infinity);
    final totalDesconto = _calcularTotalDesconto();
    final economiaPromocional = _arredondar(
      itensVendidos.fold<double>(0, (soma, item) {
        final promocional = _valor(item['precoPromocional']);
        final original = _valor(item['precoVenda']);
        if (promocional == null ||
            original == null ||
            promocional >= original) {
          return soma;
        }
        return soma + (original - promocional) * _inteiro(item['quantidade']);
      }),
    );
    final imprimir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogo) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, color: _marca),
        title: const Text('Venda concluída'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (clienteNomeController.text.trim().isNotEmpty)
              Text('Cliente: ${clienteNomeController.text.trim()}'),
            Text('Produtos: ${_moeda.format(subtotal)}'),
            if (valorFrete > 0) Text('Frete: ${_moeda.format(valorFrete)}'),
            if (totalDesconto > 0)
              Text('Descontos: ${_moeda.format(totalDesconto)}'),
            if (economiaPromocional > 0)
              Text('Promoções: ${_moeda.format(economiaPromocional)}'),
            Text('Total da venda: ${_moeda.format(totalComFrete)}'),
            Text('Pago: ${_moeda.format(totalPago)}'),
            Text('Troco: ${_moeda.format(troco)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _marca),
            onPressed: () => Navigator.of(dialogo).pop(true),
            icon: const Icon(Icons.print_outlined),
            label: Text(
              _tipoNota == 'fiscal' ? 'Emitir NFC-e' : 'Imprimir nota',
            ),
          ),
        ],
      ),
    );
    if (imprimir != true || !mounted) return;
    final itens = List<Map<String, dynamic>>.of(itensVendidos);
    final formas = List<Map<String, dynamic>>.of(pagamentos);
    if (_tipoNota == 'fiscal') {
      await _emitirNotaFiscal(itens, valorFrete, formas, totalPago);
    } else {
      await _imprimirNota(itens, valorFrete, formas, totalPago);
    }
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
      final response = await http.get(Uri.parse(danfeUrl.trim()));

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

      final Uint8List pdfBytes = response.bodyBytes;

      // 2) Buscar a impressora térmica pelo MESMO nome da nota de pagamento
      final impressoras = await Printing.listPrinters();
      final impressoraNota = impressoras.firstWhere(
        (p) => p.name.toUpperCase() == 'IMPRESSORA NOTA',
        orElse: () {
          throw Exception('Impressora IMPRESSORA NOTA não encontrada');
        },
      );

      // 3) Tentativa 1: rasterizar e remontar PDF 58mm
      final pw.Document docTermico = pw.Document();
      final double largura58mm = 58 * PdfPageFormat.mm;

      bool rasterizou = false;

      try {
        await for (final page in Printing.raster(
          pdfBytes,
          dpi: 203, // resolução típica da térmica
        )) {
          rasterizou = true;

          final pngBytes = await page.toPng();
          final image = pw.MemoryImage(pngBytes);

          final double scale = largura58mm / page.width;
          final double alturaPagina = page.height * scale;

          docTermico.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(largura58mm, alturaPagina),
              margin: pw.EdgeInsets.zero,
              build: (_) =>
                  pw.Center(child: pw.Image(image, width: largura58mm)),
            ),
          );
        }
      } on UnimplementedError catch (e) {
        // Plataforma não suporta raster -> vamos pro plano B
        debugPrint('Raster não implementado nesta plataforma: $e');
        rasterizou = false;
      } catch (e) {
        // Outro erro ao tentar rasterizar
        debugPrint('Falha ao rasterizar DANFE: $e');
        rasterizou = false;
      }

      if (rasterizou) {
        // 4A) Conseguimos rasterizar -> manda o PDF 58mm para a impressora
        await Printing.directPrintPdf(
          printer: impressoraNota,
          onLayout: (format) async => docTermico.save(),
        );
      } else {
        // 4B) NÃO conseguimos rasterizar -> envia o PDF original da Webmania
        debugPrint(
          'Enviando DANFE original para a impressora (fallback, sem raster).',
        );

        await Printing.directPrintPdf(
          printer: impressoraNota,
          onLayout: (format) async => pdfBytes,
        );
      }
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
    double totalPago,
  ) async {
    if (itensVendidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Adicione produtos antes de finalizar.")),
      );
      return;
    }

    try {
      // Total dos itens
      final double totalProdutos = _subtotalItens(itensVendidos);
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
      if (!mounted) return;

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
        await _imprimirDanfeCupom(
          List<Map<String, dynamic>>.from(itensVendidos), // cópia
          valorFrete, // mesmo frete
          List<Map<String, dynamic>>.from(pagamentos), // cópia
          totalPago, // veio do resumo
          Map<String, dynamic>.from(retorno as Map), // retorno da Webmania
        );
      } else {
        debugPrint('❌ Erro ao emitir NFC-e: $resultado');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao emitir NFC-e: $resultado')),
        );
      }
    } catch (e, stack) {
      debugPrint('❌ Erro ao emitir NFC-e: $e');
      debugPrint(stack.toString());
      if (!mounted) return;
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

    final data = DateFormat('yyyyMMdd-HHmmss-SSS').format(DateTime.now());
    await _entregarComprovante(
      pdf: pdf,
      nomeArquivo: 'comprovante-senhorita-$data.pdf',
      tipoDocumento: 'comprovante',
    );
  }

  Future<void> _entregarComprovante({
    required pw.Document pdf,
    required String nomeArquivo,
    required String tipoDocumento,
  }) async {
    final bytes = await pdf.save();
    var motivo = 'Nenhuma impressora de nota disponível.';
    try {
      final recursos = await Printing.info();
      if (recursos.canListPrinters && recursos.directPrint) {
        final impressoras = await Printing.listPrinters();
        Printer? impressoraPadrao;
        Printer? impressoraNota;
        for (final impressora in impressoras) {
          if (!impressora.isAvailable) continue;
          final nome = impressora.name.trim().toUpperCase();
          if (nome == _nomeImpressoraNota) {
            impressoraNota = impressora;
            break;
          }
          if (impressora.isDefault &&
              !_destinosVirtuais.any((destino) => nome.contains(destino))) {
            impressoraPadrao = impressora;
          }
        }

        final impressora = impressoraNota ?? impressoraPadrao;
        if (impressora != null && mounted) {
          motivo = 'Não foi possível enviar o documento para a impressora.';
          final enviado = await Printing.directPrintPdf(
            printer: impressora,
            name: nomeArquivo,
            onLayout: (_) async => bytes,
          );
          if (enviado) return;
        }
      }
    } catch (erro) {
      debugPrint('Vendas • impressão de $tipoDocumento: $erro');
    }
    if (!mounted) return;

    await _mostrarOpcoesDoComprovante(
      bytes: bytes,
      nomeArquivo: nomeArquivo,
      tipoDocumento: tipoDocumento,
      motivo: motivo,
    );
  }

  Future<void> _mostrarOpcoesDoComprovante({
    required Uint8List bytes,
    required String nomeArquivo,
    required String tipoDocumento,
    required String motivo,
  }) async {
    const anexarManual =
        'Salve o PDF e anexe o arquivo na conversa do WhatsApp.';
    const compartilharPdf =
        'Selecione o WhatsApp no menu de compartilhamento. '
        'Se ele não aparecer, salve o PDF e anexe o arquivo na conversa.';
    var ocupado = false;
    String? mensagem;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dialogo, atualizar) {
          Future<void> entregar({required bool compartilhar}) async {
            if (ocupado) return;
            atualizar(() {
              ocupado = true;
              mensagem = null;
            });

            String? resultado;
            try {
              if (compartilhar) {
                final caixa = dialogo.findRenderObject();
                final origem = caixa is RenderBox && caixa.hasSize
                    ? caixa.localToGlobal(Offset.zero) & caixa.size
                    : null;
                final envio = await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
                    fileNameOverrides: [nomeArquivo],
                    sharePositionOrigin: origem,
                    downloadFallbackEnabled: false,
                  ),
                );
                if (envio.status == ShareResultStatus.unavailable) {
                  resultado = anexarManual;
                }
              } else {
                final arquivo = await FilePicker.saveFile(
                  dialogTitle: 'Salvar $tipoDocumento em PDF',
                  fileName: nomeArquivo,
                  bytes: bytes,
                  mimeType: 'application/pdf',
                );
                if (arquivo != null) resultado = 'PDF salvo.';
              }
            } catch (erro) {
              debugPrint('Vendas • entrega de $tipoDocumento: $erro');
              resultado = compartilhar
                  ? anexarManual
                  : 'Não foi possível salvar o PDF. Tente novamente.';
            }

            if (!dialogo.mounted) return;
            atualizar(() {
              ocupado = false;
              mensagem = resultado;
            });
          }

          return PopScope(
            canPop: !ocupado,
            child: AlertDialog(
              title: const Text('Impressão indisponível'),
              scrollable: true,
              content: Text('$motivo\n\n${mensagem ?? compartilharPdf}'),
              actions: [
                TextButton(
                  onPressed: ocupado ? null : () => Navigator.of(dialogo).pop(),
                  child: const Text('Fechar'),
                ),
                OutlinedButton.icon(
                  onPressed: ocupado
                      ? null
                      : () => entregar(compartilhar: false),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Salvar em PDF'),
                ),
                FilledButton.icon(
                  onPressed: ocupado
                      ? null
                      : () => entregar(compartilhar: true),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Enviar pelo WhatsApp'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _imprimirDanfeCupom(
    List<Map<String, dynamic>> itens,
    double frete,
    List<Map<String, dynamic>> pagamentos,
    double totalPago,
    Map<String, dynamic> retornoNfce,
  ) async {
    final nomeLoja = await buscarNomeLoja();

    // ====== DADOS FISCAIS DA NFC-e (retorno Webmania) ======
    final String numeroNfe = (retornoNfce['nfe'] ?? '').toString();
    final String serie = (retornoNfce['serie'] ?? '').toString();
    final String chave = (retornoNfce['chave'] ?? '').toString();

    // alguns retornos vêm com 'protocolo' ou 'nProt'
    final String protocolo =
        (retornoNfce['protocolo'] ?? retornoNfce['nProt'] ?? '').toString();

    // ambiente: 1 produção, 2 homologação (nomes variam)
    final String ambienteRaw =
        (retornoNfce['ambiente'] ?? retornoNfce['tpAmb'] ?? '1').toString();
    final String ambiente = ambienteRaw == '2' ? 'Homologação' : 'Produção';

    // URL/STRING para gerar o QRCode (tenta vários campos comuns da Webmania)
    final String qrCodeDataRaw =
        (retornoNfce['qrcode'] ??
                retornoNfce['qr_code'] ??
                retornoNfce['url_qrcode'] ??
                retornoNfce['url_consulta'] ??
                '')
            .toString();

    // se não vier URL nenhuma, usamos a própria chave como fallback
    final String qrCodeString = qrCodeDataRaw.isNotEmpty
        ? qrCodeDataRaw
        : chave;

    // só pra debug:
    debugPrint('QR RAW: $qrCodeDataRaw');
    debugPrint('QR USADO: $qrCodeString');

    // Formata chave em blocos de 4
    String formatarChave(String c) {
      final digits = c.replaceAll(RegExp(r'\D'), '');
      return digits.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)} ');
    }

    final chaveFormatada = chave.isNotEmpty ? formatarChave(chave) : '---';

    // ====== MESMA LÓGICA DO COMPROVANTE DE PAGAMENTO ======
    final valorFrete = frete;

    double totalVenda = itens.fold(0.0, (total, item) {
      final preco = (item['precoFinal'] as num?) ?? 0.0;
      final qtd = (item['quantidade'] as num?) ?? 0;
      return total + (preco * qtd);
    });

    final formasPagamento = pagamentos
        .map((p) => p['forma'])
        .where((f) => f != null && f.toString().isNotEmpty)
        .join(", ");

    final troco = (totalPago - totalVenda - valorFrete).clamp(
      0,
      double.infinity,
    );

    debugPrint(
      'DANFE CUPOM -> itens: ${itens.length}, totalVenda: $totalVenda, totalPago: $totalPago, frete: $valorFrete',
    );

    final pdf = pw.Document();

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
                // ====== CABEÇALHO ======
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
                    "DANFE NFC-e",
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    "Documento Auxiliar da Nota Fiscal de Consumidor Eletrônica",
                    style: pw.TextStyle(fontSize: 7),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 4),

                pw.Text("Loja: $nomeLoja", style: pw.TextStyle(fontSize: 8)),
                pw.Text(
                  "Funcionário: ${funcionarioSelecionado ?? '-'}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  "Cliente: ${clienteNomeController.text.isNotEmpty ? clienteNomeController.text : 'CONSUMIDOR'}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  "NFC-e: ${numeroNfe.isNotEmpty ? numeroNfe : '-'}  Série: ${serie.isNotEmpty ? serie : '-'}",
                  style: pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  "Ambiente: $ambiente",
                  style: pw.TextStyle(fontSize: 8),
                ),
                if (protocolo.isNotEmpty)
                  pw.Text(
                    "Protocolo: $protocolo",
                    style: pw.TextStyle(fontSize: 8),
                  ),
                pw.Text("Chave de acesso:", style: pw.TextStyle(fontSize: 8)),
                pw.Text(chaveFormatada, style: pw.TextStyle(fontSize: 7)),
                pw.Text(
                  "Data: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}",
                  style: pw.TextStyle(fontSize: 8),
                ),

                pw.SizedBox(height: 6),

                // ====== ITENS ======
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
                  final qtd = (item['quantidade'] as num?)?.toInt() ?? 0;
                  final preco = (item['precoFinal'] as num?) ?? 0.0;
                  final precoPromocional =
                      (item['precoPromocional'] as num?) ?? 0.0;
                  final desconto = (item['desconto'] as num?) ?? 0.0;

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
                        "$nome ${tamanho.isNotEmpty ? '($tamanho' : ''}"
                        "${tamanho.isNotEmpty && cor.toString().isNotEmpty ? ' • ' : ''}"
                        "${cor.toString().isNotEmpty ? cor : ''}"
                        "${tamanho.isNotEmpty ? ')' : ''}",
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
                  "Total Produtos: R\$ ${totalVenda.toStringAsFixed(2)}",
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
                  "Forma de Pagamento: "
                  "${formasPagamento.isNotEmpty ? formasPagamento : 'Não informado'}",
                  style: pw.TextStyle(fontSize: 8),
                ),

                pw.SizedBox(height: 6),

                // ====== QR-CODE ======
                // ====== QR-CODE ======
                if (qrCodeString.isNotEmpty) ...[
                  pw.Center(
                    child: pw.Text(
                      "Consulta via QR Code:",
                      style: pw.TextStyle(fontSize: 7),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrCodeString,
                      width: 90, // pode aumentar um pouco
                      height: 90,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                ],

                pw.Center(
                  child: pw.Text(
                    "Consulta também pela chave de acesso no portal da Sefaz.",
                    style: pw.TextStyle(fontSize: 7),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 4),
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

    final chaveArquivo = chave.replaceAll(RegExp(r'\D'), '');
    final identificador = chaveArquivo.isEmpty
        ? DateFormat('yyyyMMdd-HHmmss-SSS').format(DateTime.now())
        : chaveArquivo;
    await _entregarComprovante(
      pdf: pdf,
      nomeArquivo: 'danfe-nfce-$identificador.pdf',
      tipoDocumento: 'DANFE',
    );
  }

  int _disponivel(
    _EstoqueVenda estoque,
    Object? docId, [
    String? tamanho,
    String? cor,
  ]) {
    var reservadasDoProduto = 0;
    var reservadasDaVariante = 0;
    for (final item in itensVendidos) {
      if (item['docId'] != docId) continue;
      final qtd = _inteiro(item['quantidade']);
      reservadasDoProduto += qtd;
      if (_textoDe(item['tamanho']) == (tamanho ?? '') &&
          _textoDe(item['cor']) == (cor ?? '')) {
        reservadasDaVariante += qtd;
      }
    }
    return min(
      estoque.quantidade - reservadasDoProduto,
      estoque.saldo(tamanho ?? '', cor ?? '') - reservadasDaVariante,
    );
  }

  void _adicionarProduto() {
    final produto = produtoEncontrado;
    if (_ocupado ||
        produto == null ||
        _formProduto.currentState?.validate() != true)
      return;
    final precoPadrao = _valor(produto['precoVenda']);
    if (precoPadrao == null || precoPadrao < 0) {
      _avisar('Este produto não tem um preço de venda válido.');
      return;
    }

    final estoque = _EstoqueVenda(produto);
    if ((estoque.usaTamanhos && _tamanho == null) ||
        (estoque.usaGrade && _cor == null)) {
      _avisar(
        estoque.usaGrade
            ? 'Selecione o tamanho e a cor.'
            : 'Selecione o tamanho.',
      );
      return;
    }

    final quantidade = _inteiro(_quantidade.text);
    if (quantidade <= 0 ||
        quantidade > _disponivel(estoque, produto['docId'], _tamanho, _cor)) {
      _avisar('Quantidade acima do estoque disponível.');
      return;
    }

    final promocional = _valor(precoPromocionalController.text);
    final preco = promocional ?? precoPadrao;
    final textoDesconto = descontoController.text.trim();
    final percentual = textoDesconto.endsWith('%');
    final informado =
        _valor(
          percentual
              ? textoDesconto.substring(0, textoDesconto.length - 1)
              : textoDesconto,
        ) ??
        0;
    final bruto = percentual ? preco * informado / 100 : informado;
    final precoFinal = _arredondar(
      (preco - bruto).clamp(0.0, double.infinity).toDouble(),
    );
    final desconto = _arredondar(preco - precoFinal);

    setState(() {
      itensVendidos.add({
        'produtoId': produto['id'],
        'docId': produto['docId'],
        'produtoNome': produto['nome'],
        'codigoBarras': produto['codigoBarras'],
        'precoVenda': precoPadrao,
        'precoPromocional': promocional,
        'desconto': desconto > 0 ? desconto : null,
        'quantidade': quantidade,
        'tamanho': _tamanho ?? '',
        'precoFinal': precoFinal,
        'cor': _cor ?? '',
        'categoria': produto['categoria'],
      });
      _limparEscolha();
      buscaController.clear();
    });
    _focoBusca.requestFocus();
  }

  void _adicionarPagamento() {
    final entrada = _valor(valorPagamentoController.text);
    final valor = entrada == null ? 0.0 : _arredondar(entrada);
    if (_forma == null || valor <= 0) {
      _avisar('Informe o valor e a forma de pagamento.');
      return;
    }
    setState(() {
      pagamentos.add({'forma': _forma, 'valor': valor});
      valorPagamentoController.clear();
      _forma = null;
    });
  }

  Future<void> _finalizarVenda() async {
    if (_ocupado) return;
    final loja = _lojaAtiva;
    if (loja.isEmpty) {
      _avisar('Selecione uma loja para registrar a venda.');
      return;
    }
    if (itensVendidos.isEmpty) {
      _avisar('Adicione ao menos um produto ao carrinho.');
      return;
    }
    final funcionario = funcionarioSelecionado;
    if (funcionario == null) {
      _avisar('Selecione o funcionário responsável pela venda.');
      return;
    }
    final freteDigitado = freteController.text.trim();
    final frete = _valor(freteDigitado);
    if (freteDigitado.isNotEmpty && (frete == null || frete < 0)) {
      _avisar('Informe um valor de frete válido.');
      return;
    }

    if (pagamentos.isEmpty || _restante > 0) {
      _avisar(
        'Registre o pagamento de ${_moeda.format(_totalComFrete)} para finalizar.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    final subtotal = _calcularTotalGeral();
    final totalPago = _calcularTotalPago();
    final nome = clienteNomeController.text.trim();
    final telefone = clienteTelefoneController.text.trim();
    setState(() => _processandoVenda = true);

    try {
      await _registrarVenda(
        loja: loja,
        funcionario: funcionario,
        subtotal: subtotal,
        totalPago: totalPago,
        frete: frete == null ? null : _arredondar(frete),
        nome: nome,
        telefone: telefone,
      );
    } on _ErroEstoque catch (erro) {
      _catalogo = null;
      if (mounted) {
        setState(() {
          _processandoVenda = false;
          _limparEscolha();
          _sugestoesProdutos = [];
          _revisaoBuscaProduto++;
          _debounceProduto?.cancel();
          _buscandoProduto = false;
          _buscouProduto = false;
          _falhaBuscaProduto = false;
          buscaController.clear();
        });
        _avisar(erro.mensagem);
      }
      return;
    } catch (erro, pilha) {
      debugPrint('Vendas • registro: $erro\n$pilha');
      if (mounted) {
        setState(() => _processandoVenda = false);
        _avisar(
          'Não foi possível registrar a venda. Confira a conexão e tente novamente.',
        );
      }
      return;
    }

    try {
      if (nome.isNotEmpty) await _salvarClienteDaVenda(nome, telefone);
      if (mounted) await _mostrarResumoVendaDialog(subtotal, totalPago);
    } catch (erro, pilha) {
      debugPrint('Vendas • comprovante: $erro\n$pilha');
      if (mounted)
        _avisar(
          'A venda foi registrada. Não foi possível concluir o comprovante.',
        );
    } finally {
      _catalogo = null;
      if (mounted) {
        setState(() {
          itensVendidos.clear();
          pagamentos.clear();
          _limparEscolha();
          _debounceProduto?.cancel();
          _debounceCliente?.cancel();
          _revisaoBuscaProduto++;
          _revisaoBuscaCliente++;
          _sugestoesProdutos = [];
          _sugestoesClientes = [];
          _buscandoProduto = false;
          _buscandoCliente = false;
          _buscouProduto = false;
          _falhaBuscaProduto = false;
          _falhaBuscaCliente = false;
          buscaController.clear();
          freteController.clear();
          valorPagamentoController.clear();
          clienteNomeController.clear();
          clienteTelefoneController.clear();
          clienteSelecionado = null;
          _forma = null;
          _processandoVenda = false;
        });
        _focoBusca.requestFocus();
      }
    }
  }

  Future<void> _registrarVenda({
    required String loja,
    required String funcionario,
    required double subtotal,
    required double totalPago,
    required double? frete,
    required String nome,
    required String telefone,
  }) async {
    final produtos = _db.collection('produtos');
    final venda = _db.collection('vendas').doc();
    final vendido = _db.collection('vendidos').doc(venda.id);
    final itens = itensVendidos
        .map((item) => Map<String, dynamic>.of(item))
        .toList();
    final formas = pagamentos.map((p) => Map<String, dynamic>.of(p)).toList();
    final dataVenda = Timestamp.now();
    final ids = itens.map((item) => _textoDe(item['docId'])).toSet();
    final idCliente = clienteSelecionado?['id'];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final tipoNota = _tipoNota;
    final totalDesconto = _calcularTotalDesconto();

    await _db.runTransaction<void>((transacao) async {
      final estoques = <String, _EstoqueVenda>{};
      for (final id in ids) {
        if (id.isEmpty)
          throw const _ErroEstoque(
            'Remova o item sem código e adicione-o novamente.',
          );
        final dados = (await transacao.get(produtos.doc(id))).data();
        if (dados == null) {
          throw const _ErroEstoque(
            'Um produto do carrinho foi removido do catálogo.',
          );
        }
        estoques[id] = _EstoqueVenda(dados);
      }

      final itensRegistrados = <Map<String, dynamic>>[];
      final lojasDosItens = <String>{};
      var custoReal = 0.0;
      for (final item in itens) {
        final estoque = estoques[_textoDe(item['docId'])]!;
        final tamanho = _textoDe(item['tamanho']);
        final cor = _textoDe(item['cor']);
        final quantidade = _inteiro(item['quantidade']);
        if (!estoque.baixar(tamanho, cor, quantidade)) {
          final nomeProduto = _textoDe(item['produtoNome'], 'Produto');
          final variante = [
            tamanho,
            cor,
          ].where((parte) => parte.isNotEmpty).join(' · ');
          final descricao = variante.isEmpty
              ? nomeProduto
              : '$nomeProduto ($variante)';
          throw _ErroEstoque(
            'Estoque insuficiente ou alterado para $descricao. Revise o carrinho.',
          );
        }
        final lojaProduto = _textoDe(estoque.dados['loja'], loja);
        final valorReal = _valor(estoque.dados['valorReal']) ?? 0.0;
        lojasDosItens.add(lojaProduto);
        custoReal += valorReal * quantidade;
        itensRegistrados.add({
          ...item,
          'valorReal': valorReal,
          'lojaProduto': lojaProduto,
          'loja': lojaProduto,
        });
      }

      final primeiro = itensRegistrados.first;
      final dadosVenda = <String, dynamic>{
        'produtoId': primeiro['produtoId'],
        'produtoNome': primeiro['produtoNome'],
        'codigoBarras': primeiro['codigoBarras'],
        'quantidade': primeiro['quantidade'],
        'tamanho': primeiro['tamanho'],
        'cor': primeiro['cor'],
        'dataVenda': dataVenda,
        'totalVenda': subtotal,
        'tipoNota': tipoNota,
        'itens': itensRegistrados,
        'pagamentos': formas,
        'totalPago': totalPago,
        'troco': _arredondar(
          totalPago - subtotal - (frete ?? 0),
        ).clamp(0.0, double.infinity),
        'frete': frete,
        'cliente': nome.isEmpty ? null : {'nome': nome, 'telefone': telefone},
        'clienteId': idCliente,
        'usuarioId': uid,
        'formasPagamento': formas.map((p) => p['forma']).toList(),
        'lojaCaixa': loja,
        'loja': loja,
        'lojaProdutoOficial': lojasDosItens.toList(),
        'funcionario': funcionario,
        'valorReal': custoReal,
        'categorias': itens
            .map((item) => item['categoria'] ?? 'Sem categoria')
            .toSet()
            .toList(),
        'precoPromocional': itens.any(
          (item) => item['precoPromocional'] != null,
        ),
        'desconto': totalDesconto > 0 ? totalDesconto : 0.0,
        'precoFinal': subtotal,
        'modelo': 'v2',
      };

      // Todas as leituras de estoque terminam antes de enfileirar as gravações.
      for (final registro in estoques.entries) {
        transacao.update(
          produtos.doc(registro.key),
          registro.value.camposParaGravar(),
        );
      }
      transacao.set(venda, dadosVenda);
      transacao.set(vendido, dadosVenda);
    });
  }

  Future<void> _salvarClienteDaVenda(String nome, String telefone) async {
    try {
      final clientes = _db.collection('clientes');
      final resposta = await clientes
          .where('nome', isEqualTo: nome)
          .where('telefone', isEqualTo: telefone)
          .limit(1)
          .get();
      if (resposta.docs.isNotEmpty) return;
      await clientes.add({
        'nome': nome,
        'telefone': telefone,
        'dataCadastro': DateTime.now().toIso8601String(),
      });
      _clientes = null;
    } catch (erro) {
      debugPrint('Vendas • cadastro após registrar a venda: $erro');
      if (mounted)
        _avisar('Venda registrada. O cadastro do cliente não foi atualizado.');
    }
  }

  Future<void> _sair() async {
    if (_ocupado) return;
    setState(() => _saindo = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    } catch (erro) {
      debugPrint('Vendas • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      _avisar('Não foi possível sair.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loja = _lojaAtiva;
    return PopScope(
      canPop: !_ocupado,
      child: Scaffold(
        backgroundColor: _fundo,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _marca,
          elevation: 0,
          toolbarHeight: 76,
          titleSpacing: 4,
          leading: Builder(
            builder: (contexto) => IconButton(
              tooltip: 'Abrir menu',
              onPressed: _ocupado
                  ? null
                  : () => Scaffold.of(contexto).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nova venda',
                style: TextStyle(
                  color: _texto,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    color: _marca,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      loja.isEmpty ? 'Nenhuma loja selecionada' : loja,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _marca,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Atualizar buscas',
              onPressed: _ocupado ? null : _atualizarBuscas,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Sair',
              onPressed: _ocupado ? null : _sair,
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: _borda),
          ),
        ),
        drawer: _menu(loja),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _ocupado,
            child: LayoutBuilder(
              builder: (context, limites) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  limites.maxWidth >= 720 ? 32 : 14,
                  20,
                  limites.maxWidth >= 720 ? 32 : 14,
                  24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: SizedBox(width: double.infinity, child: _conteudo()),
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _rodape(),
      ),
    );
  }

  Widget _conteudo() {
    final busca = _painel('Buscar produto', _painelBusca());
    final carrinho = _painel('Carrinho', _painelCarrinho());
    final pagamento = _painel('Pagamento', _painelPagamento());
    final fechamento = _painel('Dados da venda', _painelDados());
    return LayoutBuilder(
      builder: (_, limites) {
        if (limites.maxWidth < 860) {
          return _pilha([busca, carrinho, pagamento, fechamento]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _pilha([busca, carrinho])),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: _pilha([pagamento, fechamento])),
          ],
        );
      },
    );
  }

  Widget _painelBusca() {
    final produto = produtoEncontrado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: buscaController,
          focusNode: _focoBusca,
          textInputAction: TextInputAction.search,
          onChanged: _digitarProduto,
          onSubmitted: _enviarBuscaProduto,
          decoration: _campo('Nome, ID ou código de barras').copyWith(
            prefixIcon: const Icon(Icons.search, color: _marca),
            suffixIcon: _buscandoProduto
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _marca,
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      buscaController.clear();
                      _digitarProduto('');
                      _focoBusca.requestFocus();
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        if (_falhaBuscaProduto) ...[
          const SizedBox(height: 8),
          const Text(
            'Não foi possível carregar os produtos.',
            style: TextStyle(color: _erro),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _digitarProduto(buscaController.text),
              child: const Text('Tentar novamente'),
            ),
          ),
        ] else if (_buscouProduto && _sugestoesProdutos.isEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'Nenhum produto encontrado.',
            style: TextStyle(color: _suave),
          ),
        ],
        for (final sugestao in _sugestoesProdutos)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.inventory_2_outlined, color: _marca),
            title: Text(_textoDe(sugestao.dados['nome'], 'Produto sem nome')),
            subtitle: Text(
              [
                _textoDe(sugestao.dados['codigoBarras'], sugestao.id),
                _textoDe(sugestao.dados['loja']),
              ].where((texto) => texto.isNotEmpty).join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selecionarProduto(sugestao),
          ),
        if (produto != null) ...[
          const SizedBox(height: 14),
          _itemSelecionado(produto),
        ],
      ],
    );
  }

  Widget _itemSelecionado(Map<String, dynamic> produto) {
    final estoque = _EstoqueVenda(produto);
    final tamanhos = <String, String>{};
    final cores = <String, String>{};
    for (final tamanho in estoque.opcoesDeTamanho) {
      final qtd = estoque.usaGrade
          ? (estoque.grade[tamanho] ?? {}).keys.fold<int>(
              0,
              (soma, cor) =>
                  soma + _disponivel(estoque, produto['docId'], tamanho, cor),
            )
          : _disponivel(estoque, produto['docId'], tamanho);
      if (qtd > 0) tamanhos[tamanho] = '$tamanho · $qtd';
    }
    if (_tamanho != null) {
      for (final cor in (estoque.grade[_tamanho] ?? {}).keys) {
        final qtd = _disponivel(estoque, produto['docId'], _tamanho, cor);
        if (qtd > 0) cores[cor] = '$cor · $qtd';
      }
    }

    final saldo = _disponivel(estoque, produto['docId'], _tamanho, _cor);
    final selecionouVariacao =
        (!estoque.usaTamanhos || _tamanho != null) &&
        (!estoque.usaGrade || _cor != null);
    final bloqueado = estoque.usaTamanhos
        ? tamanhos.isEmpty || (selecionouVariacao && saldo <= 0)
        : saldo <= 0;
    final preco = _valor(produto['precoVenda']);
    final endereco = _textoDe(produto['foto']);
    final descricao = _textoDe(produto['descricao']);
    final lojaProduto = _textoDe(produto['loja']);

    return Form(
      key: _formProduto,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (endereco.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.square(
                    dimension: 62,
                    child: Image.network(
                      endereco,
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: _rosaClaro,
                        child: Icon(Icons.broken_image_outlined, color: _marca),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _textoDe(produto['nome'], 'Produto sem nome'),
                      style: const TextStyle(
                        color: _texto,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (lojaProduto.isNotEmpty)
                      Text(lojaProduto, style: const TextStyle(color: _suave)),
                    if (descricao.isNotEmpty)
                      Text(descricao, style: const TextStyle(color: _suave)),
                    Text(
                      preco == null
                          ? 'Preço indisponível'
                          : _moeda.format(preco),
                      style: const TextStyle(
                        color: _marca,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (estoque.usaTamanhos) ...[
            _seletor(
              'Tamanho',
              _tamanho,
              tamanhos,
              (valor) => setState(() {
                _tamanho = valor;
                _cor = null;
              }),
            ),
            const SizedBox(height: 10),
          ],
          if (estoque.usaGrade) ...[
            _seletor(
              'Cor',
              _cor,
              cores,
              (valor) => setState(() => _cor = valor),
            ),
            const SizedBox(height: 10),
          ],
          _camposEmLinha(
            TextFormField(
              controller: _quantidade,
              keyboardType: TextInputType.number,
              decoration: _campo('Quantidade'),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (valor) {
                final qtd = _inteiro(valor);
                if (qtd <= 0) return 'Informe a quantidade.';
                if (selecionouVariacao && qtd > saldo)
                  return 'Estoque insuficiente.';
                return null;
              },
            ),
            TextFormField(
              controller: precoPromocionalController,
              decoration: _campo('Preço promocional (opcional)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (texto) {
                if (_textoDe(texto).isEmpty) return null;
                final valor = _valor(texto);
                return valor == null || valor <= 0
                    ? 'Informe um preço válido.'
                    : null;
              },
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: descontoController,
            decoration: _campo('Desconto em R\$ ou %'),
            validator: (texto) {
              final entrada = _textoDe(texto);
              if (entrada.isEmpty) return null;
              final percentual = entrada.endsWith('%');
              final valor = _valor(
                percentual ? entrada.substring(0, entrada.length - 1) : entrada,
              );
              if (valor == null || valor < 0 || (percentual && valor > 100)) {
                return percentual
                    ? 'Informe de 0 a 100%.'
                    : 'Informe um desconto válido.';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          if (bloqueado)
            const Text(
              'Sem estoque disponível para adicionar.',
              style: TextStyle(color: _erro),
            )
          else if (selecionouVariacao)
            Text(
              'Disponível para o carrinho: $saldo',
              style: const TextStyle(color: _suave),
            ),
          const SizedBox(height: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _marca),
            onPressed: bloqueado ? null : _adicionarProduto,
            icon: const Icon(Icons.add_shopping_cart_outlined),
            label: const Text('Adicionar ao carrinho'),
          ),
        ],
      ),
    );
  }

  Widget _painelCarrinho() {
    if (itensVendidos.isEmpty) {
      return const Text(
        'Busque um produto para começar a venda.',
        style: TextStyle(color: _suave),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in itensVendidos) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${_inteiro(item['quantidade'])} × ${_textoDe(item['produtoNome'], 'Produto')}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                if (_textoDe(item['tamanho']).isNotEmpty)
                  _textoDe(item['tamanho']),
                if (_textoDe(item['cor']).isNotEmpty) _textoDe(item['cor']),
                '${_moeda.format(_valor(item['precoFinal']) ?? 0)} por unidade',
                if (item['precoPromocional'] != null)
                  'Promoção ${_moeda.format(item['precoPromocional'])}',
                if (item['desconto'] != null)
                  'Desconto ${_moeda.format(item['desconto'])}',
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: 'Remover produto',
              icon: const Icon(Icons.delete_outline, color: _erro),
              onPressed: () => setState(() => itensVendidos.remove(item)),
            ),
          ),
          const Divider(height: 1, color: _borda),
        ],
        const SizedBox(height: 10),
        if (_calcularTotalDesconto() > 0)
          _linhaResumo('Descontos', _calcularTotalDesconto()),
        _linhaResumo(
          'Subtotal dos produtos',
          _calcularTotalGeral(),
          destaque: true,
        ),
      ],
    );
  }

  Widget _painelPagamento() {
    if (itensVendidos.isEmpty) {
      return const Text(
        'Adicione um item ao carrinho para registrar o pagamento.',
        style: TextStyle(color: _suave),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _camposEmLinha(
          TextField(
            controller: valorPagamentoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _campo('Valor do pagamento'),
          ),
          _seletor(
            'Forma de pagamento',
            _forma,
            _formas,
            (valor) => setState(() => _forma = valor),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: _marca),
          onPressed: _adicionarPagamento,
          icon: const Icon(Icons.add_card_outlined),
          label: const Text('Adicionar pagamento'),
        ),
        for (final p in pagamentos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_formas[p['forma']] ?? _textoDe(p['forma'])),
            subtitle: Text(_moeda.format(p['valor'])),
            trailing: IconButton(
              tooltip: 'Remover pagamento',
              icon: const Icon(Icons.delete_outline, color: _erro),
              onPressed: () => setState(() => pagamentos.remove(p)),
            ),
          ),
        const SizedBox(height: 10),
        _linhaResumo('Itens + frete', _totalComFrete),
        _linhaResumo('Total pago', _calcularTotalPago()),
        if (_restante > 0)
          _linhaResumo('Falta pagar', _restante, cor: _erro, destaque: true),
        if (_troco > 0)
          _linhaResumo('Troco', _troco, cor: _verde, destaque: true),
      ],
    );
  }

  Widget _painelDados() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _seletor(
          'Funcionário',
          funcionarioSelecionado,
          {for (final funcionario in _funcionarios) funcionario: funcionario},
          (valor) => setState(() => funcionarioSelecionado = valor),
          vazio: _carregandoFuncionarios ? 'Carregando…' : 'Nenhum disponível',
        ),
        if (_falhaFuncionarios)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() {
                  _falhaFuncionarios = false;
                  _carregandoFuncionarios = true;
                });
                _carregarFuncionarios();
              },
              child: const Text('Recarregar funcionários'),
            ),
          ),
        const SizedBox(height: 10),
        _seletor('Tipo de nota', _tipoNota, _notas, (valor) {
          if (valor != null) setState(() => _tipoNota = valor);
        }),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: _marca),
              onPressed: () =>
                  setState(() => _mostrarCliente = !_mostrarCliente),
              icon: const Icon(Icons.person_outline),
              label: Text(
                _mostrarCliente ? 'Ocultar cliente' : 'Adicionar cliente',
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: _marca),
              onPressed: () => setState(() => _mostrarFrete = !_mostrarFrete),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(_mostrarFrete ? 'Ocultar frete' : 'Adicionar frete'),
            ),
          ],
        ),
        if (_mostrarCliente) ...[
          const SizedBox(height: 8),
          TextField(
            controller: clienteNomeController,
            decoration: _campo('Nome do cliente (opcional)'),
            onChanged: _digitarCliente,
          ),
          if (_buscandoCliente) const LinearProgressIndicator(color: _marca),
          if (_falhaBuscaCliente)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Busca indisponível. Você pode digitar os dados.',
                style: TextStyle(color: _suave),
              ),
            ),
          for (final cliente in _sugestoesClientes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline, color: _marca),
              title: Text(_textoDe(cliente.dados['nome'])),
              subtitle: Text(_textoDe(cliente.dados['telefone'])),
              onTap: () => _selecionarCliente(cliente),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: clienteTelefoneController,
            decoration: _campo('Telefone do cliente'),
            keyboardType: TextInputType.phone,
            onChanged: (_) {
              clienteSelecionado = null;
            },
          ),
        ],
        if (_mostrarFrete) ...[
          const SizedBox(height: 8),
          TextField(
            controller: freteController,
            decoration: _campo('Valor do frete'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
    );
  }

  Widget _rodape() {
    final habilitado = !_ocupado && itensVendidos.isNotEmpty;
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_processandoVenda)
              const LinearProgressIndicator(color: _marca)
            else
              const Divider(height: 1, color: _borda),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: LayoutBuilder(
                  builder: (context, limites) {
                    final total = Text(
                      'Total · ${_moeda.format(_totalComFrete)}',
                      style: const TextStyle(
                        color: _texto,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    );
                    final finalizar = FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _marca),
                      onPressed: habilitado ? _finalizarVenda : null,
                      icon: const Icon(
                        Icons.shopping_cart_checkout_outlined,
                        size: 20,
                      ),
                      label: Text(
                        _processandoVenda ? 'Processando…' : 'Finalizar venda',
                      ),
                    );
                    if (limites.maxWidth < 380) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [total, const SizedBox(height: 4), finalizar],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: total),
                        const SizedBox(width: 12),
                        finalizar,
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(String loja) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined, color: _marca),
              title: Text(_nomeUsuario.isEmpty ? 'Senhorita' : _nomeUsuario),
              subtitle: loja.isEmpty ? null : Text(loja),
            ),
            const Divider(color: _borda),
            if (_tipoUsuario == 'admin')
              _linkMenu(
                Icons.dashboard_outlined,
                'Início',
                () => HomeView(lojaSelecionada: loja),
              ),
            ListTile(
              leading: const Icon(Icons.point_of_sale),
              title: const Text('Nova venda'),
              selected: true,
              selectedColor: _marca,
              selectedTileColor: _rosaClaro,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
            _linkMenu(
              Icons.checkroom,
              'Produtos',
              () => ProdutosView(lojaSelecionada: loja),
            ),
            _linkMenu(
              Icons.add_box_outlined,
              'Adicionar produto',
              () => AdicionarProdutosView(lojaSelecionada: loja),
            ),
            _linkMenu(
              Icons.people_outline,
              'Clientes',
              () => ClientesView(lojaSelecionada: loja),
            ),
            if (_tipoUsuario == 'funcionario')
              _linkMenu(
                Icons.receipt_long_outlined,
                'Vendas realizadas',
                () => VendasRealizadasView(lojaSelecionada: loja),
              ),
            if (_tipoUsuario == 'admin') ...[
              _linkMenu(
                Icons.bar_chart,
                'Relatórios',
                () => RelatoriosView(lojaSelecionada: loja),
              ),
              _linkMenu(
                Icons.settings_outlined,
                'Configurações',
                () => ConfiguracoesView(lojaSelecionada: loja),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linkMenu(IconData icone, String rotulo, Widget Function() abrir) {
    return ListTile(
      leading: Icon(icone, color: _suave),
      title: Text(rotulo),
      onTap: () {
        if (_ocupado) return;
        final navegador = Navigator.of(context);
        navegador.pop();
        if (_lojaAtiva.isEmpty) {
          _avisar('Selecione uma loja primeiro.');
          return;
        }
        navegador.pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => abrir()),
        );
      },
    );
  }
}

Widget _painel(String titulo, Widget filho) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _borda),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: _texto,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          filho,
        ],
      ),
    ),
  );
}

Widget _pilha(List<Widget> paineis) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < paineis.length; i++) ...[
        if (i > 0) const SizedBox(height: 14),
        paineis[i],
      ],
    ],
  );
}

Widget _camposEmLinha(Widget primeiro, Widget segundo) {
  return LayoutBuilder(
    builder: (context, limites) {
      if (limites.maxWidth < 400) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [primeiro, const SizedBox(height: 10), segundo],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: primeiro),
          const SizedBox(width: 10),
          Expanded(child: segundo),
        ],
      );
    },
  );
}

InputDecoration _campo(String rotulo) {
  return InputDecoration(
    labelText: rotulo,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _borda),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _borda),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _marca, width: 1.5),
    ),
  );
}

Widget _seletor(
  String rotulo,
  String? selecionado,
  Map<String, String> opcoes,
  ValueChanged<String?> onChanged, {
  String vazio = 'Sem opções',
}) {
  final valor = opcoes.containsKey(selecionado) ? selecionado : null;
  return InputDecorator(
    decoration: _campo(
      rotulo,
    ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
    isEmpty: valor == null,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: valor,
        isExpanded: true,
        isDense: true,
        hint: const Text('Selecionar'),
        disabledHint: Text(vazio),
        items: [
          for (final opcao in opcoes.entries)
            DropdownMenuItem(
              value: opcao.key,
              child: Text(opcao.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: opcoes.isEmpty ? null : onChanged,
      ),
    ),
  );
}

Widget _linhaResumo(
  String rotulo,
  double valor, {
  bool destaque = false,
  Color? cor,
}) {
  final estilo = TextStyle(
    color: cor ?? (destaque ? _texto : _suave),
    fontWeight: destaque ? FontWeight.w800 : FontWeight.w500,
  );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(rotulo, style: estilo)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _moeda.format(valor),
            textAlign: TextAlign.right,
            style: estilo,
          ),
        ),
      ],
    ),
  );
}

class _RegistroBusca {
  _RegistroBusca(this.id, Map<String, dynamic> origem, {required bool cliente})
    : dados = {...origem, if (!cliente) 'docId': id},
      codigo = _normalizar(_textoDe(origem['codigoBarras'])),
      identificadores = {_normalizar(id), _normalizar(_textoDe(origem['id']))},
      loja = _textoDe(origem['loja']),
      nome = _normalizar(_textoDe(origem['nome'])),
      texto = _normalizar(
        [
          origem['nome'],
          if (cliente) ...[
            origem['telefone'],
            _textoDe(origem['telefone']).replaceAll(RegExp(r'\D'), ''),
          ] else ...[
            origem['id'],
            id,
            origem['codigoBarras'],
          ],
        ].whereType<Object>().join(' '),
      );

  final String id;
  final Map<String, dynamic> dados;
  final String codigo;
  final Set<String> identificadores;
  final String loja;
  final String nome;
  final String texto;

  int relevancia(String termo, String lojaCaixa) {
    if (codigo == termo || identificadores.contains(termo)) return 0;
    final naLoja = lojaCaixa.isEmpty || lojaCaixa == loja;
    if (nome == termo) return naLoja ? 1 : 2;
    return naLoja ? 3 : 4;
  }
}

List<_RegistroBusca> _buscar(
  List<_RegistroBusca> origem,
  String termo, {
  String loja = '',
  int limite = 12,
}) {
  final termos = termo.split(' ');
  final resultados = origem
      .where((item) => termos.every(item.texto.contains))
      .toList();
  resultados.sort((a, b) {
    final ordem = a
        .relevancia(termo, loja)
        .compareTo(b.relevancia(termo, loja));
    return ordem == 0 ? a.nome.compareTo(b.nome) : ordem;
  });
  return resultados.take(limite).toList();
}

class _EstoqueVenda {
  _EstoqueVenda(this.dados)
    : tamanhos = _mapa(dados['tamanhos']),
      grade = _mapa(
        dados['tamanhosCores'],
      ).map((tamanho, cores) => MapEntry(tamanho, _mapa(cores))) {
    grade.removeWhere((_, cores) => cores.isEmpty);
    final total = _valor(dados['quantidade']);
    quantidade =
        total?.toInt() ??
        (usaGrade
            ? grade.values.fold<int>(
                0,
                (soma, cores) => soma + _somarQuantidades(cores),
              )
            : _somarQuantidades(tamanhos));
  }

  final Map<String, dynamic> dados;
  final Map<String, dynamic> tamanhos;
  final Map<String, Map<String, dynamic>> grade;
  late int quantidade;

  bool get usaGrade => grade.isNotEmpty;
  bool get usaTamanhos => usaGrade || tamanhos.isNotEmpty;
  Iterable<String> get opcoesDeTamanho => usaGrade ? grade.keys : tamanhos.keys;

  int saldo(String tamanho, String cor) {
    if (usaGrade) {
      return _inteiro(grade[tamanho]?[cor]);
    }
    if (usaTamanhos) {
      return cor.isEmpty ? _inteiro(tamanhos[tamanho]) : 0;
    }
    return tamanho.isEmpty && cor.isEmpty ? quantidade : 0;
  }

  bool baixar(String tamanho, String cor, int qtd) {
    final atual = saldo(tamanho, cor);
    if (qtd <= 0 || qtd > atual || qtd > quantidade) return false;

    if (usaGrade) {
      final cores = grade[tamanho]!;
      cores[cor] = atual - qtd;
      tamanhos[tamanho] = _somarQuantidades(cores);
    } else if (usaTamanhos) {
      tamanhos[tamanho] = atual - qtd;
    }
    quantidade -= qtd;
    return true;
  }

  Map<String, dynamic> camposParaGravar() => {
    'quantidade': quantidade,
    if (usaTamanhos) 'tamanhos': tamanhos,
    if (usaGrade) 'tamanhosCores': grade,
  };
}

class _ErroEstoque implements Exception {
  const _ErroEstoque(this.mensagem);

  final String mensagem;
}

Map<String, dynamic> _mapa(Object? valor) {
  if (valor is! Map) return {};
  return {for (final item in valor.entries) item.key.toString(): item.value};
}

int _somarQuantidades(Map<String, dynamic> mapa) =>
    mapa.values.fold<int>(0, (soma, qtd) => soma + _inteiro(qtd));

String _textoDe(Object? valor, [String padrao = '']) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}

double? _valor(Object? entrada) {
  if (entrada is num) return entrada.isFinite ? entrada.toDouble() : null;
  var texto = _textoDe(
    entrada,
  ).replaceAll('R\$', '').replaceAll(RegExp(r'\s+'), '');
  if (texto.contains(',')) {
    texto = texto.replaceAll('.', '').replaceAll(',', '.');
  }
  final numero = double.tryParse(texto);
  return numero != null && numero.isFinite ? numero : null;
}

int _inteiro(Object? entrada) => _valor(entrada)?.toInt() ?? 0;

double _arredondar(double valor) => double.parse(valor.toStringAsFixed(2));

double _subtotalItens(List<Map<String, dynamic>> itens) => _arredondar(
  itens.fold<double>(
    0,
    (soma, item) =>
        soma +
        (_valor(item['precoFinal']) ?? 0.0) * _inteiro(item['quantidade']),
  ),
);

String _normalizar(String texto) {
  const acentos = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const letras = 'aaaaaeeeeiiiiooooouuuucn';
  var resultado = texto.toLowerCase().trim();
  for (var i = 0; i < acentos.length; i++) {
    resultado = resultado.replaceAll(acentos[i], letras[i]);
  }
  return resultado.replaceAll(RegExp(r'\s+'), ' ');
}
