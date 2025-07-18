// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:senhorita/view/home.view.dart';
import 'package:senhorita/view/vendas.view.dart';
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
  final entrada = _usuarioController.text.trim().toLowerCase();
  final senha = _senhaController.text;

  if (entrada.isEmpty || senha.isEmpty) {
    _mostrarAlerta(
      'Atenção',
      'Preencha todos os campos.',
      Colors.orange,
      Icons.info_outline,
    );
    return;
  }

  // Mostra loading
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    String? email;
    DocumentSnapshot? usuarioDoc;

    if (entrada.contains('@')) {
      // Buscar pelo e-mail
      final snapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: entrada)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        Navigator.of(context).pop();
        _mostrarAlerta('Erro', 'E-mail não encontrado.', Colors.red, Icons.error_outline);
        return;
      }

      usuarioDoc = snapshot.docs.first;
      email = entrada;
    } else {
      // Buscar pelo nome de usuário
      final snapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('nomeUsuario', isEqualTo: entrada)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        Navigator.of(context).pop();
        _mostrarAlerta('Erro', 'Usuário não encontrado.', Colors.red, Icons.error_outline);
        return;
      }

      usuarioDoc = snapshot.docs.first;
      email = usuarioDoc['email'];
    }

    // Faz login
    final erro = await _viewModel.login(email!, senha);

    if (erro != null) {
      Navigator.of(context).pop();
      _mostrarAlerta('Erro', erro, Colors.red, Icons.error_outline);
      return;
    }

    // Verifica o tipo do usuário após login
    final tipoUsuario = usuarioDoc['tipo'];

    Navigator.of(context).pop(); // Fecha loading

    if (tipoUsuario == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeView()),
      );
    } else if (tipoUsuario == 'funcionario') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VendasView()),
      );
    } else {
      _mostrarAlerta(
        'Erro',
        'Tipo de usuário inválido.',
        Colors.red,
        Icons.error_outline,
      );
    }
  } catch (e, stack) {
  Navigator.of(context).pop();

  _mostrarAlerta(
    'Erro',
    'Falha ao tentar fazer login.\nErro: ${e.toString()}',
    Colors.red,
    Icons.error_outline,
  );

  debugPrint('Erro no login: $e');
  debugPrint('Stack trace: $stack');
}

}



void _redefinirSenha() {
  final TextEditingController usuarioController = TextEditingController();

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Redefinir senha'),
      content: TextField(
        controller: usuarioController,
        decoration: const InputDecoration(
          labelText: 'Digite seu nome de usuário',
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
            final nomeUsuario = usuarioController.text.trim().toLowerCase();
            Navigator.of(context).pop();

            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const Center(child: CircularProgressIndicator()),
            );

            try {
              // Buscar o e-mail a partir do nome de usuário
              final snapshot = await FirebaseFirestore.instance
                  .collection('usuarios')
                  .where('nomeUsuario', isEqualTo: nomeUsuario)
                  .limit(1)
                  .get();

              if (snapshot.docs.isEmpty) {
                Navigator.of(context).pop();
                _mostrarAlerta('Erro', 'Usuário não encontrado.', Colors.red, Icons.error_outline);
                return;
              }

              final email = snapshot.docs.first['email'];

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
            } catch (e) {
              Navigator.of(context).pop();
              _mostrarAlerta('Erro', 'Ocorreu um erro ao redefinir a senha.', Colors.red, Icons.error_outline);
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
                              onSubmitted: (_) => _fazerLogin(),
                              
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
