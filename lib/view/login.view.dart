import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:senhorita/viewmodel/login_viewmodel.dart';

import 'home.view.dart';
import 'vendas.view.dart';

const _fundo = Color(0xFFFAF7F9);
const _texto = Color(0xFF301F2C);
const _suave = Color(0xFF695763);
const _marca = Color(0xFF832958);
const _rosaClaro = Color(0xFFF8EAF2);
const _borda = Color(0xFFEADDE5);
const _lojas = ['Senhorita Modeladores (Matriz)', 'Senhorita Jalecos (Filial)'];

enum _Operacao { entrar, recuperar }

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formulario = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _senha = TextEditingController();
  final _viewModel = LoginViewModel();
  final _usuarios = FirebaseFirestore.instance.collection('usuarios');
  final _auth = FirebaseAuth.instance;

  bool _senhaVisivel = false;
  _Operacao? _operacao;
  String? _mensagem;
  bool _mensagemDeErro = true;

  bool get _ocupado => _operacao != null;

  @override
  void dispose() {
    _usuario.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _buscarPerfil(
    String entrada,
  ) async {
    final campo = entrada.contains('@') ? 'email' : 'nomeUsuario';
    final resultado = await _usuarios
        .where(campo, isEqualTo: entrada)
        .limit(1)
        .get();
    return resultado.docs.isEmpty ? null : resultado.docs.first;
  }

  void _informar(String mensagem, {bool erro = true}) {
    if (!mounted) return;
    setState(() {
      _mensagem = mensagem;
      _mensagemDeErro = erro;
    });
  }

  Future<void> _fazerLogin() async {
    if (_ocupado || !(_formulario.currentState?.validate() ?? false)) return;
    final entrada = _usuario.text.trim().toLowerCase();
    final senha = _senha.text;
    FocusScope.of(context).unfocus();
    setState(() {
      _operacao = _Operacao.entrar;
      _mensagem = null;
    });

    String? uidDaSessao;
    var encaminhado = false;
    try {
      final perfil = await _buscarPerfil(entrada);
      if (!mounted) return;
      final dados = perfil?.data();
      final email = entrada.contains('@')
          ? entrada
          : _textoCampo(dados?['email']);
      if (perfil == null || email.isEmpty) {
        _informar('Confira seu usuário ou e-mail e sua senha.');
        return;
      }

      final erro = await _viewModel.login(email, senha);
      if (erro != null) {
        _informar(
          'Não foi possível entrar. Confira seus dados e tente novamente.',
        );
        return;
      }
      final autenticado = _auth.currentUser;
      if (autenticado == null) {
        _informar('Não foi possível iniciar a sessão. Tente novamente.');
        return;
      }
      uidDaSessao = autenticado.uid;
      if (!mounted) return;

      final tipo = _textoCampo(dados?['tipo']);
      if (tipo != 'admin' && tipo != 'funcionario') {
        _informar('Seu perfil não está habilitado para acessar o sistema.');
        return;
      }

      final loja = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _DialogoLoja(anterior: _textoCampo(dados?['lojaSelecionada'])),
      );
      if (!mounted || loja == null) return;
      await perfil.reference.update({'lojaSelecionada': loja});
      if (!mounted) return;

      TextInput.finishAutofillContext();
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => tipo == 'admin'
              ? HomeView(lojaSelecionada: loja)
              : VendasView(lojaSelecionada: loja),
        ),
      );
      encaminhado = true;
    } on FirebaseException catch (erro) {
      debugPrint('Login • Firebase: ${erro.code}');
      _informar(
        uidDaSessao == null
            ? 'Não foi possível fazer login. Tente novamente.'
            : 'Não foi possível salvar a loja selecionada. Tente novamente.',
      );
    } catch (_) {
      _informar('Não foi possível concluir o acesso. Tente novamente.');
    } finally {
      if (!encaminhado) {
        if (uidDaSessao != null && _auth.currentUser?.uid == uidDaSessao) {
          try {
            await _auth.signOut();
          } catch (_) {
            _informar(
              'Não foi possível encerrar a sessão. Reabra o aplicativo antes de tentar novamente.',
            );
          }
        }
        if (mounted) setState(() => _operacao = null);
      }
    }
  }

  Future<void> _redefinirSenha() async {
    if (_ocupado) return;
    FocusScope.of(context).unfocus();
    final entrada = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoRecuperacao(inicial: _usuario.text.trim()),
    );
    if (!mounted || entrada == null || _ocupado) return;
    setState(() {
      _operacao = _Operacao.recuperar;
      _mensagem = null;
    });

    const resposta =
        'Se houver uma conta cadastrada, você receberá um e-mail. Confira também a pasta de spam.';
    try {
      final perfil = entrada.contains('@')
          ? null
          : await _buscarPerfil(entrada);
      if (!mounted) return;
      final email = entrada.contains('@')
          ? entrada
          : _textoCampo(perfil?.data()['email']);
      if (email.isEmpty) {
        _informar(resposta, erro: false);
        return;
      }

      final erro = await _viewModel.redefinirSenha(email);
      if (erro == null ||
          erro.toString().toLowerCase().contains('user-not-found')) {
        _informar(resposta, erro: false);
      } else {
        _informar(
          'Não foi possível solicitar a recuperação. Confira o e-mail e tente novamente.',
        );
      }
    } on FirebaseException catch (erro) {
      debugPrint('Login • recuperação: ${erro.code}');
      _informar('Não foi possível solicitar a recuperação. Tente novamente.');
    } catch (_) {
      _informar('Não foi possível solicitar a recuperação. Tente novamente.');
    } finally {
      if (mounted) setState(() => _operacao = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, limites) {
            final horizontal = limites.maxWidth >= 760;
            final margem = horizontal ? 32.0 : 16.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.all(margem),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: limites.maxHeight > margem * 2
                      ? limites.maxHeight - margem * 2
                      : 0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: horizontal ? 880 : 480,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.white,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: _borda),
                        ),
                        child: horizontal
                            ? Stack(
                                children: [
                                  const Positioned.fill(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 4,
                                          child: ColoredBox(color: _rosaClaro),
                                        ),
                                        Expanded(flex: 5, child: SizedBox()),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      const Expanded(
                                        flex: 4,
                                        child: _MarcaLogin(horizontal: true),
                                      ),
                                      Expanded(
                                        flex: 5,
                                        child: _formularioLogin(
                                          horizontal: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const ColoredBox(
                                    color: _rosaClaro,
                                    child: _MarcaLogin(horizontal: false),
                                  ),
                                  _formularioLogin(horizontal: false),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _formularioLogin({required bool horizontal}) {
    return Padding(
      padding: EdgeInsets.all(horizontal ? 36 : 22),
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Form(
          key: _formulario,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Entrar',
                style: TextStyle(
                  color: _texto,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _usuario,
                enabled: !_ocupado,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                decoration: _decoracao(
                  'Usuário ou e-mail',
                  Icons.person_outline,
                ),
                validator: (valor) => (valor?.trim().isEmpty ?? true)
                    ? 'Informe seu usuário ou e-mail'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _senha,
                enabled: !_ocupado,
                autofillHints: const [AutofillHints.password],
                obscureText: !_senhaVisivel,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: _decoracao('Senha', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _senhaVisivel ? 'Ocultar senha' : 'Mostrar senha',
                    onPressed: _ocupado
                        ? null
                        : () => setState(() => _senhaVisivel = !_senhaVisivel),
                    icon: Icon(
                      _senhaVisivel
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (valor) =>
                    (valor?.isEmpty ?? true) ? 'Informe sua senha' : null,
                onFieldSubmitted: (_) => _fazerLogin(),
              ),
              if (_mensagem != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _mensagem!,
                    style: TextStyle(
                      color: _mensagemDeErro
                          ? Theme.of(context).colorScheme.error
                          : _suave,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _ocupado ? null : _fazerLogin,
                style: _botaoPrincipal(),
                child: _operacao == _Operacao.entrar
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _marca,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Entrando…'),
                        ],
                      )
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _ocupado ? null : _redefinirSenha,
                style: TextButton.styleFrom(foregroundColor: _marca),
                child: Text(
                  _operacao == _Operacao.recuperar
                      ? 'Enviando solicitação…'
                      : 'Esqueceu a senha?',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarcaLogin extends StatelessWidget {
  const _MarcaLogin({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: horizontal ? 36 : 24,
      vertical: horizontal ? 32 : 18,
    ),
    child: Center(
      child: Image.asset(
        'assets/logosenhorita.png',
        height: horizontal ? 190 : 104,
        width: horizontal ? 250 : 190,
        fit: BoxFit.contain,
        semanticLabel: 'Senhorita Cintas Modeladores',
        errorBuilder: (_, __, ___) => const Text(
          'Senhorita',
          style: TextStyle(
            color: _marca,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

class _DialogoLoja extends StatefulWidget {
  const _DialogoLoja({required this.anterior});

  final String anterior;

  @override
  State<_DialogoLoja> createState() => _DialogoLojaState();
}

class _DialogoLojaState extends State<_DialogoLoja> {
  String? _selecionada;

  @override
  void initState() {
    super.initState();
    if (_lojas.contains(widget.anterior)) _selecionada = widget.anterior;
  }

  void _fechar([String? loja]) {
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(loja);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: const Text('Selecione a loja'),
    content: SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final loja in _lojas)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: loja == _selecionada ? _rosaClaro : Colors.white,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: loja == _selecionada ? _marca : _borda,
                  ),
                ),
                child: ListTile(
                  selected: loja == _selecionada,
                  selectedColor: _marca,
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(loja),
                  trailing: loja == _selecionada
                      ? const Icon(Icons.check_circle_outline, color: _marca)
                      : const Icon(Icons.radio_button_unchecked),
                  onTap: () => setState(() => _selecionada = loja),
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _fechar, child: const Text('Voltar')),
      FilledButton(
        onPressed: _selecionada == null ? null : () => _fechar(_selecionada),
        style: _botaoPrincipal(),
        child: const Text('Confirmar loja'),
      ),
    ],
  );
}

class _DialogoRecuperacao extends StatefulWidget {
  const _DialogoRecuperacao({required this.inicial});

  final String inicial;

  @override
  State<_DialogoRecuperacao> createState() => _DialogoRecuperacaoState();
}

class _DialogoRecuperacaoState extends State<_DialogoRecuperacao> {
  final _formulario = GlobalKey<FormState>();
  late String _entrada = widget.inicial;

  void _enviar() {
    final form = _formulario.currentState;
    if (ModalRoute.of(context)?.isCurrent != true ||
        form == null ||
        !form.validate()) {
      return;
    }
    form.save();
    Navigator.of(context).pop(_entrada);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: const Text('Redefinir senha'),
    content: SizedBox(
      width: 390,
      child: Form(
        key: _formulario,
        child: TextFormField(
          initialValue: widget.inicial,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          decoration: _decoracao('Usuário ou e-mail', Icons.person_outline),
          validator: (valor) => (valor?.trim().isEmpty ?? true)
              ? 'Informe seu usuário ou e-mail'
              : null,
          onSaved: (valor) => _entrada = valor!.trim().toLowerCase(),
          onFieldSubmitted: (_) => _enviar(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _enviar,
        style: _botaoPrincipal(),
        child: const Text('Enviar'),
      ),
    ],
  );
}

InputDecoration _decoracao(String rotulo, IconData icone) => InputDecoration(
  labelText: rotulo,
  prefixIcon: Icon(icone, color: _marca),
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _borda),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _marca, width: 1.5),
  ),
);

ButtonStyle _botaoPrincipal() => FilledButton.styleFrom(
  backgroundColor: _marca,
  foregroundColor: Colors.white,
  minimumSize: const Size(0, 46),
  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

String _textoCampo(Object? valor) => valor?.toString().trim() ?? '';
