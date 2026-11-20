import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diacritic/diacritic.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'adicionar.produtos.view.dart';
import 'clientes.view.dart';
import 'configuracoes.view.dart';
import 'home.view.dart';
import 'login.view.dart';
import 'produtos.view.dart';
import 'relatorios.view.dart';
import 'vendas.realizadas.view.dart';
import 'vendas.view.dart';

class GerenciarUsuariosView extends StatefulWidget {
  final String lojaSelecionada;
  const GerenciarUsuariosView({super.key, required this.lojaSelecionada});

  @override
  State<GerenciarUsuariosView> createState() => _GerenciarUsuariosViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);
const _perfis = {'admin': 'Administrador', 'funcionario': 'Funcionário'};

class _GerenciarUsuariosViewState extends State<GerenciarUsuariosView> {
  var _formKey = GlobalKey<FormState>();
  final _inicioFormulario = GlobalKey();
  final _nome = TextEditingController();
  final _usuario = TextEditingController();
  final _cpf = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _busca = TextEditingController();
  final _usuarios = FirebaseFirestore.instance.collection('usuarios');
  late Stream<QuerySnapshot<Map<String, dynamic>>> _lista;

  String _perfil = 'funcionario';
  String _filtroPerfil = '';
  String _tipoUsuario = '';
  String _nomeUsuario = '';
  String? _editandoId;
  bool _ocupado = false;
  bool _mostrarSenha = false;

  @override
  void initState() {
    super.initState();
    _lista = _usuarios.snapshots();
    _carregarDadosUsuario();
  }

  @override
  void dispose() {
    _nome.dispose();
    _usuario.dispose();
    _cpf.dispose();
    _email.dispose();
    _senha.dispose();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregarDadosUsuario() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final dados = (await _usuarios.doc(uid).get()).data();
      if (!mounted || dados == null) return;
      setState(() {
        _nomeUsuario = _campo(dados['nomeUsuario']);
        _tipoUsuario = _campo(dados['tipo']);
      });
    } catch (erro) {
      debugPrint('Gerenciar usuários • perfil: $erro');
    }
  }

  void _editar(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final dados = doc.data();
    final perfil = _campo(dados['tipo']);
    setState(() {
      _editandoId = doc.id;
      _nome.text = _campo(dados['nome']);
      _usuario.text = _campo(dados['nomeUsuario']);
      _cpf.text = _campo(dados['cpf']);
      _email.text = _campo(dados['email']);
      _senha.clear();
      _mostrarSenha = false;
      _perfil = _perfis.containsKey(perfil) ? perfil : 'funcionario';
      _formKey = GlobalKey<FormState>();
    });
    final formulario = _inicioFormulario.currentContext;
    if (formulario != null) {
      Scrollable.ensureVisible(
        formulario,
        duration: const Duration(milliseconds: 260),
      );
    }
  }

  void _limparFormulario() {
    setState(() {
      _editandoId = null;
      _nome.clear();
      _usuario.clear();
      _cpf.clear();
      _email.clear();
      _senha.clear();
      _mostrarSenha = false;
      _perfil = 'funcionario';
      _formKey = GlobalKey<FormState>();
    });
  }

  void _mensagem(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _salvarUsuario() async {
    if (_ocupado || !(_formKey.currentState?.validate() ?? false)) return;
    final editandoId = _editandoId;
    final login = _usuario.text.trim().toLowerCase();
    final email = _email.text.trim();
    final senha = _senha.text.trim();
    final dados = {
      'nome': _nome.text.trim(),
      'nomeUsuario': login,
      'cpf': _cpf.text.trim(),
      'email': email,
      'tipo': _perfil,
      if (editandoId == null) 'dataCadastro': DateTime.now().toIso8601String(),
    };

    setState(() => _ocupado = true);
    try {
      if (editandoId != null) {
        await _usuarios.doc(editandoId).update(dados);
      } else {
        final existente = await _usuarios
            .where('nomeUsuario', isEqualTo: login)
            .limit(1)
            .get();
        if (existente.docs.isNotEmpty) {
          _mensagem('Nome de usuário já está em uso.');
          return;
        }

        final credenciais = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: senha);
        await _usuarios.doc(credenciais.user!.uid).set(dados);
      }

      if (!mounted) return;
      _limparFormulario();
      _mensagem(
        editandoId == null ? 'Usuário cadastrado.' : 'Usuário atualizado.',
      );
    } on FirebaseAuthException catch (erro) {
      _mensagem(switch (erro.code) {
        'email-already-in-use' => 'Este e-mail já está em uso.',
        'invalid-email' => 'E-mail inválido.',
        _ => 'Não foi possível cadastrar o usuário.',
      });
    } catch (erro) {
      debugPrint('Gerenciar usuários • salvar: $erro');
      _mensagem('Não foi possível salvar o cadastro.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _confirmarExclusao(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (_ocupado) return;
    final nome = _campo(doc.data()['nome']);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Excluir cadastro?'),
        content: Text(nome.isEmpty ? 'Usuário sem nome.' : nome),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogo).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Excluir cadastro'),
          ),
        ],
      ),
    );
    if (!mounted || confirmou != true || _ocupado) return;

    setState(() => _ocupado = true);
    try {
      await doc.reference.delete();
      if (mounted && _editandoId == doc.id) _limparFormulario();
      _mensagem('Cadastro excluído.');
    } catch (erro) {
      debugPrint('Gerenciar usuários • excluir: $erro');
      _mensagem('Não foi possível excluir o cadastro.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _sair() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    } catch (erro) {
      debugPrint('Gerenciar usuários • saída: $erro');
      _mensagem('Não foi possível sair.');
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loja = widget.lojaSelecionada.trim();
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _marca,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 76,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gerenciar usuários',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _texto,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.storefront_outlined, color: _marca, size: 16),
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
            tooltip: 'Sair',
            onPressed: _ocupado ? null : _sair,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _borda),
        ),
      ),
      drawer: _menu(loja),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1232),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _lista,
              builder: (context, snapshot) {
                final docs =
                    snapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final termo = removeDiacritics(
                  _busca.text.trim().toLowerCase(),
                );
                final filtrados = docs.where((doc) {
                  final dados = doc.data();
                  if (_filtroPerfil.isNotEmpty &&
                      dados['tipo'] != _filtroPerfil) {
                    return false;
                  }
                  return termo.isEmpty ||
                      ['nome', 'nomeUsuario', 'email'].any(
                        (campo) => removeDiacritics(
                          _campo(dados[campo]).toLowerCase(),
                        ).contains(termo),
                      );
                }).toList();
                filtrados.sort(
                  (a, b) => _campo(a.data()['nome']).toLowerCase().compareTo(
                    _campo(b.data()['nome']).toLowerCase(),
                  ),
                );

                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _formulario(),
                            const SizedBox(height: 20),
                            _filtros(),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    if (snapshot.hasError)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: _cartao(
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Wrap(
                                spacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'Não foi possível carregar os usuários.',
                                  ),
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _lista = _usuarios.snapshots(),
                                    ),
                                    child: const Text('Tentar novamente'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (!snapshot.hasData)
                      const SliverToBoxAdapter(
                        child: Center(
                          child: CircularProgressIndicator(color: _marca),
                        ),
                      )
                    else if (filtrados.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: _cartao(
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                docs.isEmpty
                                    ? 'Nenhum usuário cadastrado.'
                                    : 'Nenhum usuário encontrado com esses filtros.',
                                style: const TextStyle(color: _suave),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _cardUsuario(filtrados[index]),
                            ),
                            childCount: filtrados.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _formulario() {
    final editando = _editandoId != null;
    return KeyedSubtree(
      key: _inicioFormulario,
      child: _cartao(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _titulo(editando ? 'Editar usuário' : 'Novo usuário'),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, limites) {
                    const espaco = 12.0;
                    final largura = limites.maxWidth >= 620
                        ? (limites.maxWidth - espaco) / 2
                        : limites.maxWidth;
                    final campos = [
                      _campoObrigatorio(
                        _nome,
                        'Nome completo',
                        'Informe o nome',
                      ),
                      _campoObrigatorio(
                        _usuario,
                        'Nome de usuário',
                        'Informe o nome de usuário',
                      ),
                      _campoObrigatorio(
                        _cpf,
                        'CPF',
                        'Informe o CPF',
                        teclado: TextInputType.number,
                      ),
                      _campoObrigatorio(
                        _email,
                        'E-mail',
                        'Informe o e-mail',
                        teclado: TextInputType.emailAddress,
                      ),
                      if (!editando)
                        TextFormField(
                          controller: _senha,
                          enabled: !_ocupado,
                          obscureText: !_mostrarSenha,
                          decoration: _decoracao('Senha').copyWith(
                            suffixIcon: IconButton(
                              tooltip: _mostrarSenha
                                  ? 'Ocultar senha'
                                  : 'Mostrar senha',
                              icon: Icon(
                                _mostrarSenha
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: _ocupado
                                  ? null
                                  : () => setState(
                                      () => _mostrarSenha = !_mostrarSenha,
                                    ),
                            ),
                          ),
                          validator: (valor) => (valor?.trim().length ?? 0) < 6
                              ? 'Informe uma senha de pelo menos 6 caracteres'
                              : null,
                        ),
                      DropdownButtonFormField<String>(
                        value: _perfil,
                        isExpanded: true,
                        decoration: _decoracao('Perfil'),
                        items: [
                          for (final perfil in _perfis.entries)
                            DropdownMenuItem(
                              value: perfil.key,
                              child: Text(perfil.value),
                            ),
                        ],
                        onChanged: _ocupado
                            ? null
                            : (valor) {
                                if (valor != null)
                                  setState(() => _perfil = valor);
                              },
                      ),
                    ];
                    return Wrap(
                      spacing: espaco,
                      runSpacing: espaco,
                      children: [
                        for (final campo in campos)
                          SizedBox(width: largura, child: campo),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (editando)
                      OutlinedButton(
                        onPressed: _ocupado ? null : _limparFormulario,
                        child: const Text('Cancelar edição'),
                      ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _marca),
                      onPressed: _ocupado ? null : _salvarUsuario,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        editando ? 'Salvar alterações' : 'Cadastrar usuário',
                      ),
                    ),
                  ],
                ),
                if (_ocupado) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(color: _marca),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _campoObrigatorio(
    TextEditingController controller,
    String rotulo,
    String mensagem, {
    TextInputType? teclado,
  }) => TextFormField(
    controller: controller,
    enabled: !_ocupado,
    keyboardType: teclado,
    decoration: _decoracao(rotulo),
    validator: (valor) =>
        (valor == null || valor.trim().isEmpty) ? mensagem : null,
  );

  Widget _filtros() {
    return _cartao(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titulo('Usuários cadastrados'),
            const SizedBox(height: 12),
            TextField(
              controller: _busca,
              onChanged: (_) => setState(() {}),
              decoration: _decoracao('Buscar por nome, usuário ou e-mail')
                  .copyWith(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busca.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () => setState(_busca.clear),
                            icon: const Icon(Icons.clear),
                          ),
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chipPerfil('', 'Todos'),
                for (final perfil in _perfis.entries)
                  _chipPerfil(perfil.key, perfil.value),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipPerfil(String valor, String rotulo) => ChoiceChip(
    label: Text(rotulo),
    selected: _filtroPerfil == valor,
    selectedColor: _rosaClaro,
    onSelected: (selecionado) {
      if (selecionado) setState(() => _filtroPerfil = valor);
    },
  );

  Widget _cardUsuario(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final dados = doc.data();
    final nome = _campo(dados['nome']);
    final usuario = _campo(dados['nomeUsuario']);
    final email = _campo(dados['email']);
    final perfil = _campo(dados['tipo']);
    return _cartao(
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: const CircleAvatar(
          backgroundColor: _rosaClaro,
          foregroundColor: _marca,
          child: Icon(Icons.person_outline),
        ),
        title: Text(nome.isEmpty ? 'Sem nome' : nome),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (usuario.isNotEmpty)
              Text(usuario, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (email.isNotEmpty)
              Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              _perfis[perfil] ??
                  (perfil.isEmpty ? 'Perfil não informado' : perfil),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Editar usuário',
              color: _marca,
              icon: const Icon(Icons.edit_outlined),
              onPressed: _ocupado ? null : () => _editar(doc),
            ),
            IconButton(
              tooltip: 'Excluir cadastro',
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_outline),
              onPressed: _ocupado ? null : () => _confirmarExclusao(doc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(String loja) => Drawer(
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
            _link(
              Icons.dashboard_outlined,
              'Início',
              () => HomeView(lojaSelecionada: loja),
            ),
          _link(
            Icons.point_of_sale,
            'Nova venda',
            () => VendasView(lojaSelecionada: loja),
          ),
          _link(
            Icons.checkroom,
            'Produtos',
            () => ProdutosView(lojaSelecionada: loja),
          ),
          _link(
            Icons.add_box_outlined,
            'Adicionar produto',
            () => AdicionarProdutosView(lojaSelecionada: loja),
          ),
          _link(
            Icons.people_outline,
            'Clientes',
            () => ClientesView(lojaSelecionada: loja),
          ),
          if (_tipoUsuario == 'funcionario')
            _link(
              Icons.receipt_long_outlined,
              'Vendas realizadas',
              () => VendasRealizadasView(lojaSelecionada: loja),
            ),
          if (_tipoUsuario == 'admin') ...[
            _link(
              Icons.bar_chart,
              'Relatórios',
              () => RelatoriosView(lojaSelecionada: loja),
            ),
            _link(
              Icons.settings_outlined,
              'Configurações',
              () => ConfiguracoesView(lojaSelecionada: loja),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _link(IconData icone, String rotulo, Widget Function() abrir) =>
      ListTile(
        leading: Icon(icone, color: _suave),
        title: Text(rotulo),
        onTap: _ocupado
            ? null
            : () {
                final navegador = Navigator.of(context);
                navegador.pop();
                navegador.pushReplacement<void, void>(
                  MaterialPageRoute<void>(builder: (_) => abrir()),
                );
              },
      );
}

Widget _cartao(Widget filho) => Material(
  color: Colors.white,
  clipBehavior: Clip.antiAlias,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: _borda),
  ),
  child: filho,
);

Widget _titulo(String texto) => Text(
  texto,
  style: const TextStyle(
    color: _texto,
    fontSize: 18,
    fontWeight: FontWeight.w800,
  ),
);

InputDecoration _decoracao(String rotulo) => InputDecoration(
  labelText: rotulo,
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _borda),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _marca),
  ),
);

String _campo(Object? valor) => valor?.toString().trim() ?? '';
