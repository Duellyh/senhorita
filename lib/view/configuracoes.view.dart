import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/adicionar.produtos.view.dart';
import 'package:senhorita/view/clientes.view.dart';
import 'package:senhorita/view/gerencia.usuario.view.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/login.view.dart';
import 'package:senhorita/view/produtos.view.dart';
import 'package:senhorita/view/relatorios.view.dart';
import 'package:senhorita/view/vendas.realizadas.view.dart';
import 'package:senhorita/view/vendas.view.dart';

class ConfiguracoesView extends StatefulWidget {
  final String lojaSelecionada;
  const ConfiguracoesView({super.key, required this.lojaSelecionada});

  @override
  State<ConfiguracoesView> createState() => _ConfiguracoesViewState();
}

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);
const _erro = Color(0xFF9E2940);

class _ConfiguracoesViewState extends State<ConfiguracoesView> {
  final _auth = FirebaseAuth.instance;
  late Future<_PerfilConfiguracoes?> _perfil;
  bool _saindo = false;

  String get _loja => widget.lojaSelecionada.trim();

  @override
  void initState() {
    super.initState();
    _perfil = _consultarPerfil();
  }

  Future<_PerfilConfiguracoes?> _consultarPerfil() async {
    final usuario = _auth.currentUser;
    if (usuario == null) return null;
    final documento = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(usuario.uid)
        .get();
    final dados = documento.data();
    return _PerfilConfiguracoes(
      usuario.uid,
      _campo(dados?['nome'], _campo(usuario.displayName, 'Usuário')),
      _campo(dados?['tipo'], 'funcionario'),
    );
  }

  void _recarregarPerfil() {
    if (_saindo) return;
    setState(() => _perfil = _consultarPerfil());
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _alterarSenha() async {
    final usuario = _auth.currentUser;
    final email = usuario?.email;
    if (usuario == null || email == null || email.isEmpty) {
      _avisar('Entre com sua conta de e-mail para alterar a senha.');
      return;
    }
    final alterou = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoSenha(usuario: usuario, email: email),
    );
    if (mounted && alterou == true) _avisar('Senha alterada com sucesso.');
  }

  Future<void> _gerenciarUsuarios(_PerfilConfiguracoes perfil) async {
    if (!perfil.ehAdmin || _auth.currentUser?.uid != perfil.uid || _saindo) {
      return;
    }
    final loja = _loja;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GerenciarUsuariosView(lojaSelecionada: loja),
      ),
    );
    if (mounted) _recarregarPerfil();
  }

  Future<void> _sair() async {
    if (_saindo) return;
    setState(() => _saindo = true);
    try {
      await _auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    } catch (erro) {
      debugPrint('Configurações • saída: $erro');
      if (!mounted) return;
      setState(() => _saindo = false);
      _avisar('Não foi possível sair.');
    }
  }

  void _sobre() {
    showAboutDialog(
      context: context,
      applicationName: 'SystemVende',
      applicationVersion: '1.0.0',
      children: const [Text('Aplicativo de vendas desenvolvido com Flutter.')],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PerfilConfiguracoes?>(
      future: _perfil,
      builder: (context, snapshot) {
        final usuario = _auth.currentUser;
        final carregando = snapshot.connectionState == ConnectionState.waiting;
        final dados = snapshot.data;
        final perfil = !carregando && dados?.uid == usuario?.uid ? dados : null;
        return Scaffold(
          backgroundColor: _fundo,
          appBar: _cabecalho(),
          drawer: _menu(perfil),
          body: SafeArea(
            child: AbsorbPointer(
              absorbing: _saindo,
              child: LayoutBuilder(
                builder: (context, limites) {
                  final margem = limites.maxWidth >= 720 ? 32.0 : 14.0;
                  return ListView(
                    padding: EdgeInsets.fromLTRB(margem, 24, margem, 32),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: SizedBox(
                            width: double.infinity,
                            child: _conteudo(
                              perfil,
                              usuario,
                              carregando: carregando,
                              falha: snapshot.hasError,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  AppBar _cabecalho() {
    final loja = _loja;
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _marca,
      elevation: 0,
      toolbarHeight: 76,
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configurações',
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
          onPressed: _saindo ? null : _sair,
          icon: const Icon(Icons.logout),
        ),
        const SizedBox(width: 4),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: _borda),
      ),
    );
  }

  Widget _conteudo(
    _PerfilConfiguracoes? perfil,
    User? usuario, {
    required bool carregando,
    required bool falha,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('Minha conta'),
        const SizedBox(height: 12),
        _cartao(
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _icone(Icons.person_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        perfil?.nome ?? _campo(usuario?.displayName, 'Usuário'),
                        style: const TextStyle(
                          color: _texto,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_campo(usuario?.email).isNotEmpty)
                        Text(
                          usuario!.email!,
                          style: const TextStyle(color: _suave),
                        ),
                      if (perfil != null)
                        Text(
                          perfil.rotuloTipo,
                          style: const TextStyle(
                            color: _marca,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (carregando) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(color: _marca),
                      ] else if (falha) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Não foi possível carregar o perfil.',
                          style: TextStyle(color: _suave),
                        ),
                        TextButton(
                          onPressed: _recarregarPerfil,
                          child: const Text('Tentar novamente'),
                        ),
                      ] else if (usuario == null)
                        const Text(
                          'Sessão encerrada.',
                          style: TextStyle(color: _suave),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _opcao(
          Icons.lock_outline,
          'Alterar senha',
          usuario?.email == null ? null : _alterarSenha,
        ),
        if (perfil?.ehAdmin == true) ...[
          const SizedBox(height: 24),
          _titulo('Administração'),
          const SizedBox(height: 12),
          _opcao(
            Icons.manage_accounts_outlined,
            'Gerenciar usuários',
            () => _gerenciarUsuarios(perfil!),
          ),
        ],
        const SizedBox(height: 24),
        _titulo('Aplicativo'),
        const SizedBox(height: 12),
        _acoesAplicativo(),
      ],
    );
  }

  Widget _acoesAplicativo() {
    final sobre = _opcao(Icons.info_outline, 'Sobre o app', _sobre);
    final sair = _opcao(
      Icons.logout,
      _saindo ? 'Encerrando sessão…' : 'Sair',
      _saindo ? null : _sair,
      destaque: _erro,
    );
    return LayoutBuilder(
      builder: (context, limites) {
        if (limites.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [sobre, const SizedBox(height: 10), sair],
          );
        }
        return Row(
          children: [
            Expanded(child: sobre),
            const SizedBox(width: 12),
            Expanded(child: sair),
          ],
        );
      },
    );
  }

  Widget _opcao(
    IconData icone,
    String texto,
    VoidCallback? onTap, {
    Color destaque = _marca,
  }) {
    return _cartao(
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              _icone(icone, cor: destaque),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(
                    color: destaque == _erro ? _erro : _texto,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: destaque),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(_PerfilConfiguracoes? perfil) {
    final loja = _loja;
    final admin = perfil?.ehAdmin == true;
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined, color: _marca),
              title: Text(perfil?.nome ?? 'Senhorita'),
              subtitle: loja.isEmpty ? null : Text(loja),
            ),
            const Divider(color: _borda),
            if (admin)
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
            if (perfil?.tipo == 'funcionario')
              _link(
                Icons.receipt_long_outlined,
                'Vendas realizadas',
                () => VendasRealizadasView(lojaSelecionada: loja),
              ),
            if (admin)
              _link(
                Icons.bar_chart,
                'Relatórios',
                () => RelatoriosView(lojaSelecionada: loja),
              ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Configurações'),
              selected: true,
              selectedColor: _marca,
              selectedTileColor: _rosaClaro,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _link(IconData icone, String nome, Widget Function() abrir) {
    return ListTile(
      leading: Icon(icone, color: _suave),
      title: Text(nome),
      onTap: () {
        if (_saindo) return;
        final navegador = Navigator.of(context);
        navegador.pop();
        navegador.pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => abrir()),
        );
      },
    );
  }
}

class _PerfilConfiguracoes {
  const _PerfilConfiguracoes(this.uid, this.nome, this.tipo);

  final String uid;
  final String nome;
  final String tipo;

  bool get ehAdmin => tipo == 'admin';
  String get rotuloTipo => switch (tipo) {
    'admin' => 'Administrador',
    'funcionario' => 'Funcionário',
    _ => tipo,
  };
}

class _DialogoSenha extends StatefulWidget {
  const _DialogoSenha({required this.usuario, required this.email});

  final User usuario;
  final String email;

  @override
  State<_DialogoSenha> createState() => _DialogoSenhaState();
}

class _DialogoSenhaState extends State<_DialogoSenha> {
  final _formulario = GlobalKey<FormState>();
  final _atual = TextEditingController();
  final _nova = TextEditingController();
  final _confirmacao = TextEditingController();
  final _visiveis = <TextEditingController>{};
  bool _salvando = false;
  String? _erroSenha;

  @override
  void dispose() {
    _atual.dispose();
    _nova.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || _formulario.currentState?.validate() != true) return;
    final novaSenha = _nova.text;
    final credencial = EmailAuthProvider.credential(
      email: widget.email,
      password: _atual.text,
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _salvando = true;
      _erroSenha = null;
    });

    final auth = FirebaseAuth.instance;
    try {
      if (auth.currentUser?.uid != widget.usuario.uid) {
        _falhar('Sua sessão mudou. Entre novamente para alterar a senha.');
        return;
      }
      await widget.usuario.reauthenticateWithCredential(credencial);
      if (!mounted) return;
      if (auth.currentUser?.uid != widget.usuario.uid) {
        _falhar('Sua sessão mudou. Entre novamente para alterar a senha.');
        return;
      }

      await widget.usuario.updatePassword(novaSenha);
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (erro) {
      debugPrint('Configurações • alteração de senha: ${erro.code}');
      _falhar(switch (erro.code) {
        'wrong-password' ||
        'invalid-credential' => 'Confira a senha atual e tente novamente.',
        'weak-password' || 'password-does-not-meet-requirements' =>
          'A nova senha não atende aos requisitos de segurança da conta.',
        'requires-recent-login' ||
        'user-token-expired' ||
        'invalid-user-token' ||
        'user-not-found' ||
        'user-mismatch' ||
        'user-disabled' =>
          'Sua sessão precisa ser renovada. Entre novamente para alterar a senha.',
        'network-request-failed' => 'Confira sua conexão e tente novamente.',
        'too-many-requests' =>
          'Houve muitas tentativas. Aguarde um pouco e tente novamente.',
        _ => 'Não foi possível alterar a senha. Tente novamente.',
      });
    } catch (erro) {
      debugPrint('Configurações • alteração de senha: ${erro.runtimeType}');
      _falhar('Não foi possível alterar a senha. Tente novamente.');
    }
  }

  void _falhar(String mensagem) {
    if (!mounted) return;
    setState(() {
      _salvando = false;
      _erroSenha = mensagem;
    });
  }

  Widget _senha(
    TextEditingController controller,
    String rotulo,
    String? Function(String?) validar, {
    bool ultimo = false,
  }) {
    final visivel = _visiveis.contains(controller);
    return TextFormField(
      controller: controller,
      enabled: !_salvando,
      obscureText: !visivel,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: ultimo ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: ultimo ? (_) => _salvar() : null,
      decoration: _campoSenha(rotulo).copyWith(
        suffixIcon: IconButton(
          tooltip: visivel ? 'Ocultar $rotulo' : 'Mostrar $rotulo',
          onPressed: _salvando
              ? null
              : () => setState(() {
                  if (visivel) {
                    _visiveis.remove(controller);
                  } else {
                    _visiveis.add(controller);
                  }
                }),
          icon: Icon(
            visivel ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: _marca,
          ),
        ),
      ),
      validator: validar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.lock_outline, color: _marca),
        title: const Text('Alterar senha'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formulario,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _senha(
                  _atual,
                  'Senha atual',
                  (valor) => valor == null || valor.isEmpty
                      ? 'Informe a senha atual.'
                      : null,
                ),
                const SizedBox(height: 12),
                _senha(
                  _nova,
                  'Nova senha',
                  (valor) => valor == null || valor.isEmpty
                      ? 'Informe a nova senha.'
                      : null,
                ),
                const SizedBox(height: 12),
                _senha(
                  _confirmacao,
                  'Confirmar nova senha',
                  (valor) => valor == null || valor.isEmpty
                      ? 'Confirme a nova senha.'
                      : valor != _nova.text
                      ? 'A confirmação deve ser igual à nova senha.'
                      : null,
                  ultimo: true,
                ),
                if (_erroSenha != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _erroSenha!,
                      style: const TextStyle(color: _erro),
                    ),
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
            child: Text(_salvando ? 'Salvando…' : 'Salvar senha'),
          ),
        ],
      ),
    );
  }
}

InputDecoration _campoSenha(String rotulo) {
  return InputDecoration(
    labelText: rotulo,
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

Widget _titulo(String titulo) => Text(
  titulo,
  style: const TextStyle(
    color: _texto,
    fontSize: 20,
    fontWeight: FontWeight.w800,
  ),
);

Widget _icone(IconData icone, {Color cor = _marca}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: _rosaClaro,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Icon(icone, size: 21, color: cor),
    ),
  );
}

String _campo(Object? valor, [String padrao = '']) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}
