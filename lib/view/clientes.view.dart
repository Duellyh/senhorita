import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/configuracoes.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class ClientesView extends StatefulWidget {
  final String lojaSelecionada;
  const ClientesView({super.key, required this.lojaSelecionada});

  @override
  State<ClientesView> createState() => _ClientesViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);
const _erro = Color(0xFF9E2940);

class _ClientesViewState extends State<ClientesView> {
  final _db = FirebaseFirestore.instance;
  final _busca = TextEditingController();
  final _excluindo = <String>{};
  late Stream<_ListaClientes> _clientes;

  String _termo = '';
  String _tipoUsuario = '';
  String _nomeUsuario = '';
  bool _saindo = false;

  String get _loja => widget.lojaSelecionada.trim();

  @override
  void initState() {
    super.initState();
    _clientes = _observarClientes();
    _carregarPerfil();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Stream<_ListaClientes> _observarClientes() {
    final indice = <String, _Cliente>{};
    return _db.collection('clientes').orderBy('nome').snapshots().map((
      snapshot,
    ) {
      for (final alteracao in snapshot.docChanges) {
        indice.remove(alteracao.doc.id);
      }
      return _ListaClientes([
        for (final documento in snapshot.docs)
          indice.putIfAbsent(documento.id, () => _Cliente(documento)),
      ]);
    });
  }

  Future<void> _carregarPerfil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final perfil = (await _db.collection('usuarios').doc(uid).get()).data();
      if (!mounted) return;
      setState(() {
        _tipoUsuario = _campo(perfil?['tipo'], 'funcionario');
        _nomeUsuario = _campo(perfil?['nome'], 'Usuário');
      });
    } catch (erro) {
      debugPrint('Clientes • perfil: $erro');
      if (mounted) _avisar('Não foi possível carregar o perfil do usuário.');
    }
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  void _recarregar() {
    setState(() => _clientes = _observarClientes());
  }

  void _alterarBusca(String valor) {
    final termo = _normalizar(valor);
    if (termo == _termo) return;
    setState(() => _termo = termo);
  }

  void _limparBusca() {
    _busca.clear();
    _alterarBusca('');
  }

  Future<void> _abrirCadastro([_Cliente? cliente]) async {
    FocusScope.of(context).unfocus();
    final referencia =
        cliente?.documento.reference ?? _db.collection('clientes').doc();
    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoCliente(referencia: referencia, cliente: cliente),
    );
    if (mounted && salvo == true) {
      _avisar(cliente == null ? 'Cliente cadastrado.' : 'Cliente atualizado.');
    }
  }

  Future<void> _excluirCliente(_Cliente cliente) async {
    final id = cliente.documento.id;
    if (_excluindo.contains(id)) return;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Excluir cliente?'),
        content: Text(
          'Deseja excluir “${cliente.nome}” do cadastro de clientes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _erro),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Excluir cliente'),
          ),
        ],
      ),
    );
    if (!mounted || confirmou != true || _excluindo.contains(id)) return;

    setState(() => _excluindo.add(id));
    try {
      await cliente.documento.reference.delete();
      if (mounted) _avisar('Cliente excluído.');
    } catch (erro) {
      debugPrint('Clientes • exclusão: $erro');
      if (mounted) _avisar('Não foi possível excluir o cliente.');
    } finally {
      if (mounted) setState(() => _excluindo.remove(id));
    }
  }

  Future<void> _sair() async {
    if (_saindo) return;
    setState(() => _saindo = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    } catch (erro) {
      debugPrint('Clientes • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      _avisar('Não foi possível sair.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _marca,
        elevation: 0,
        toolbarHeight: 76,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Clientes',
              style: TextStyle(
                color: _texto,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 16, color: _marca),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _loja.isEmpty ? 'Nenhuma loja selecionada' : _loja,
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
            tooltip: 'Atualizar clientes',
            onPressed: _saindo ? null : _recarregar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _saindo ? null : _sair,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _borda),
        ),
      ),
      drawer: _menu(),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saindo,
          child: LayoutBuilder(
            builder: (context, limites) {
              final margem = limites.maxWidth >= 720 ? 32.0 : 14.0;
              final largura = (limites.maxWidth - margem * 2)
                  .clamp(0.0, 1180.0)
                  .toDouble();
              return Center(
                child: SizedBox(
                  width: largura,
                  child: StreamBuilder<_ListaClientes>(
                    stream: _clientes,
                    builder: (context, snapshot) =>
                        _conteudo(snapshot, largura),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _conteudo(AsyncSnapshot<_ListaClientes> snapshot, double largura) {
    final cadastro = snapshot.data;
    final resultado = cadastro?.pesquisar(_termo) ?? const <_Cliente>[];
    final colunas = largura >= 780 ? 2 : 1;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: _barraBusca(
            largura,
            cadastro?.clientes.length,
            resultado.length,
          ),
        ),
        if (snapshot.hasError)
          SliverToBoxAdapter(
            child: _estadoLista(
              'Não foi possível carregar os clientes.',
              acao: TextButton(
                onPressed: _recarregar,
                child: const Text('Tentar novamente'),
              ),
            ),
          )
        else if (cadastro == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(color: _marca)),
            ),
          )
        else if (resultado.isEmpty)
          SliverToBoxAdapter(
            child: _estadoLista(
              _termo.isEmpty
                  ? 'Nenhum cliente cadastrado.'
                  : 'Nenhum cliente encontrado com essa busca.',
              acao: _termo.isEmpty
                  ? null
                  : TextButton(
                      onPressed: _limparBusca,
                      child: const Text('Limpar busca'),
                    ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, linha) {
                final inicio = linha * colunas;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var coluna = 0; coluna < colunas; coluna++) ...[
                        if (coluna > 0) const SizedBox(width: 12),
                        Expanded(
                          child: inicio + coluna < resultado.length
                              ? _cartaoCliente(resultado[inicio + coluna])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              }, childCount: (resultado.length + colunas - 1) ~/ colunas),
            ),
          ),
      ],
    );
  }

  Widget _barraBusca(double largura, int? total, int encontrados) {
    final campo = TextField(
      controller: _busca,
      textInputAction: TextInputAction.search,
      onChanged: _alterarBusca,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      decoration: _decoracao('Buscar por nome ou telefone').copyWith(
        prefixIcon: const Icon(Icons.search, color: _marca),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _busca,
          builder: (context, valor, _) => valor.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Limpar busca',
                  onPressed: _limparBusca,
                  icon: const Icon(Icons.clear),
                ),
        ),
      ),
    );
    final adicionar = FilledButton.icon(
      onPressed: () => _abrirCadastro(),
      style: FilledButton.styleFrom(
        backgroundColor: _marca,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
      ),
      icon: const Icon(Icons.person_add_outlined),
      label: const Text('Adicionar cliente'),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (largura >= 580)
            Row(
              children: [
                Expanded(child: campo),
                const SizedBox(width: 12),
                adicionar,
              ],
            )
          else ...[
            campo,
            const SizedBox(height: 10),
            adicionar,
          ],
          if (total != null) ...[
            const SizedBox(height: 12),
            Text(
              _termo.isEmpty
                  ? (total == 1
                        ? '1 cliente cadastrado'
                        : '$total clientes cadastrados')
                  : '$encontrados de $total no cadastro',
              style: const TextStyle(
                color: _suave,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cartaoCliente(_Cliente cliente) {
    final emExclusao = _excluindo.contains(cliente.documento.id);
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: _rosaClaro,
              foregroundColor: _marca,
              child: Icon(Icons.person_outline),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cliente.nome,
                    style: const TextStyle(
                      color: _texto,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    cliente.telefone.isEmpty
                        ? 'Telefone não informado'
                        : cliente.telefone,
                    style: const TextStyle(color: _suave),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Editar cliente',
              onPressed: emExclusao ? null : () => _abrirCadastro(cliente),
              icon: const Icon(Icons.edit_outlined, color: _marca, size: 20),
            ),
            if (emExclusao)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(color: _marca, strokeWidth: 2),
              )
            else
              IconButton(
                tooltip: 'Excluir cliente',
                onPressed: () => _excluirCliente(cliente),
                icon: const Icon(Icons.delete_outline, color: _erro, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  Widget _estadoLista(String texto, {Widget? acao}) {
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _suave),
            ),
            if (acao != null) acao,
          ],
        ),
      ),
    );
  }

  Widget _menu() {
    final loja = _loja;
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
            _linkMenu(
              Icons.point_of_sale,
              'Nova venda',
              () => VendasView(lojaSelecionada: loja),
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
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Clientes'),
              selected: true,
              selectedColor: _marca,
              selectedTileColor: _rosaClaro,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => Navigator.of(context).pop(),
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

  Widget _linkMenu(IconData icone, String nome, Widget Function() destino) {
    return ListTile(
      leading: Icon(icone, color: _suave),
      title: Text(nome),
      onTap: () {
        if (_saindo) return;
        final navegador = Navigator.of(context);
        navegador.pop();
        navegador.pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => destino()),
        );
      },
    );
  }
}

class _DialogoCliente extends StatefulWidget {
  const _DialogoCliente({required this.referencia, required this.cliente});

  final DocumentReference<Map<String, dynamic>> referencia;
  final _Cliente? cliente;

  @override
  State<_DialogoCliente> createState() => _DialogoClienteState();
}

class _DialogoClienteState extends State<_DialogoCliente> {
  final _formulario = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _telefone;
  bool _salvando = false;
  bool _falhou = false;

  bool get _editando => widget.cliente != null;

  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.cliente?.nomeOriginal);
    _telefone = TextEditingController(text: widget.cliente?.telefone);
  }

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || _formulario.currentState?.validate() != true) return;
    final dados = {
      'nome': _nome.text.trim(),
      'telefone': _telefone.text.trim(),
      if (!_editando) 'dataCadastro': DateTime.now().toIso8601String(),
    };
    FocusScope.of(context).unfocus();
    setState(() {
      _salvando = true;
      _falhou = false;
    });

    try {
      if (_editando) {
        await widget.referencia.update(dados);
      } else {
        await widget.referencia.set(dados);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (erro) {
      debugPrint('Clientes • salvamento: $erro');
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _falhou = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        scrollable: true,
        icon: Icon(
          _editando ? Icons.edit_outlined : Icons.person_add_outlined,
          color: _marca,
        ),
        title: Text(_editando ? 'Editar cliente' : 'Adicionar cliente'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _formulario,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nome,
                  enabled: !_salvando,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: _decoracao('Nome'),
                  validator: (valor) => _campo(valor).isEmpty
                      ? 'Informe o nome do cliente.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefone,
                  enabled: !_salvando,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: _decoracao('Telefone'),
                  validator: (valor) => _campo(valor).isEmpty
                      ? 'Informe o telefone do cliente.'
                      : null,
                  onFieldSubmitted: (_) => _salvar(),
                ),
                if (_falhou) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Não foi possível salvar. Tente novamente.',
                    style: TextStyle(color: _erro),
                  ),
                ],
                if (_salvando) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(color: _marca),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _salvando ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _marca),
            onPressed: _salvando ? null : _salvar,
            child: Text(_salvando ? 'Salvando…' : 'Salvar cliente'),
          ),
        ],
      ),
    );
  }
}

class _Cliente {
  factory _Cliente(QueryDocumentSnapshot<Map<String, dynamic>> documento) {
    final dados = documento.data();
    final nome = _campo(dados['nome']);
    final telefone = _campo(dados['telefone']);
    return _Cliente._(
      documento,
      nome,
      telefone,
      _normalizar(nome),
      telefone.replaceAll(_naoDigitos, ''),
    );
  }

  const _Cliente._(
    this.documento,
    this.nomeOriginal,
    this.telefone,
    this.nomeBusca,
    this.telefoneBusca,
  );

  final QueryDocumentSnapshot<Map<String, dynamic>> documento;
  final String nomeOriginal;
  final String telefone;
  final String nomeBusca;
  final String telefoneBusca;

  String get nome => nomeOriginal.isEmpty ? 'Cliente sem nome' : nomeOriginal;
}

class _ListaClientes {
  _ListaClientes(this.clientes);

  final List<_Cliente> clientes;
  String? _termoAnterior;
  List<_Cliente> _resultadoAnterior = const [];

  List<_Cliente> pesquisar(String termo) {
    if (termo.isEmpty) return clientes;
    if (termo == _termoAnterior) return _resultadoAnterior;

    if (_entradaTelefone.hasMatch(termo)) {
      final digitos = termo.replaceAll(_naoDigitos, '');
      _resultadoAnterior = clientes
          .where((cliente) => cliente.telefoneBusca.contains(digitos))
          .toList();
    } else {
      final palavras = termo.split(' ');
      _resultadoAnterior = clientes
          .where((cliente) => palavras.every(cliente.nomeBusca.contains))
          .toList();
    }
    _termoAnterior = termo;
    return _resultadoAnterior;
  }
}

final _naoDigitos = RegExp(r'\D');
final _entradaTelefone = RegExp(r'^[+()\- .]*\d[\d+()\- .]*$');
final _espacos = RegExp(r'\s+');

String _campo(Object? valor, [String padrao = '']) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}

String _normalizar(String texto) {
  const acentos = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const letras = 'aaaaaeeeeiiiiooooouuuucn';
  var resultado = texto.toLowerCase().trim();
  for (var i = 0; i < acentos.length; i++) {
    resultado = resultado.replaceAll(acentos[i], letras[i]);
  }
  return resultado.replaceAll(_espacos, ' ');
}

InputDecoration _decoracao(String rotulo) {
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

Widget _cartao(Widget filho) {
  return Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _borda),
    ),
    clipBehavior: Clip.antiAlias,
    child: filho,
  );
}
