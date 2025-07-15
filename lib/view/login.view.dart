import 'package:flutter/material.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/viewmodel/login_viewmodel.dart';


class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final TextEditingController _usuarioController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();
  final LoginViewModel _viewModel = LoginViewModel();
  bool _senhaVisivel = false;

  @override
  void dispose() {
    _usuarioController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _mostrarAlerta(String titulo, String mensagem, Color cor, IconData icone) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: cor, size: 60),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              mensagem,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fazerLogin() async {
    final usuario = _usuarioController.text.trim();
    final senha = _senhaController.text;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final erro = await _viewModel.login(usuario, senha);
    Navigator.of(context).pop();

    if (erro == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeView()),
      );
    } else {
      _mostrarAlerta('Erro', erro, Colors.red, Icons.error_outline);
    }
  }

  void _redefinirSenha() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Redefinir senha'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Digite seu e-mail',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Enviar'),
            onPressed: () async {
              final email = emailController.text.trim();
              Navigator.of(context).pop();

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              final erro = await _viewModel.redefinirSenha(email);
              Navigator.of(context).pop();

              if (erro == null) {
                _mostrarAlerta(
                  'Sucesso',
                  'E-mail enviado! Verifique sua caixa de entrada ou spam.',
                  Colors.green,
                  Icons.check_circle_outline,
                );
              } else {
                _mostrarAlerta('Erro', erro, Colors.red, Icons.error_outline);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color.fromARGB(255, 194, 131, 178),
        child: Center(
          child: SingleChildScrollView(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ConstrainedBox(
                    constraints: const BoxConstraints(
                          maxWidth: 500,
                    ),
                    child: Card(
                      color: Colors.pink[50],
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                            
                            const Text(
                              'SENHORITA CINTAS MODELADORES',
                              style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.pink,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _usuarioController,
                              decoration: InputDecoration(
                              labelText: 'Usuário',
                              labelStyle: const TextStyle(color: Colors.pink),
                              enabledBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.pink),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.pink, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.person, color: Colors.pink),
                              ),
                              style: const TextStyle(color: Colors.black),
                              textInputAction: TextInputAction.next,
                              textAlign: TextAlign.left,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _senhaController,
                              obscureText: !_senhaVisivel,
                              decoration: InputDecoration(
                              labelText: 'Senha',
                              labelStyle: const TextStyle(color: Colors.pink),
                              enabledBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.pink),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.pink, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.lock, color: Colors.pink),
                              suffixIcon: IconButton(
                                icon: Icon(
                                _senhaVisivel ? Icons.visibility_off : Icons.visibility,
                                color: Colors.pink,
                                ),
                                onPressed: () {
                                setState(() {
                                  _senhaVisivel = !_senhaVisivel;
                                });
                                },
                              ),
                              ),
                              style: const TextStyle(color: Colors.black),
                              textInputAction: TextInputAction.done,
                              textAlign: TextAlign.left,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.pink,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _fazerLogin,
                              child: const Text('Entrar', style: TextStyle(fontSize: 18)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                              onPressed: _redefinirSenha,
                              child: const Text(
                                'Esqueceu a senha?',
                                style: TextStyle(color: Colors.pink),
                              ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
