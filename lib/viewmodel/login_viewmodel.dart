

import 'package:firebase_auth/firebase_auth.dart';
import 'package:senhorita/service/auth_service.dart';

class LoginViewModel {
  final AuthService _authService = AuthService();

  get usuarioLogado => null;

  Future<String?> login(String email, String senha) async {
    if (email.isEmpty || senha.isEmpty) return 'Preencha todos os campos';

    try {
      await _authService.login(email, senha);
      return null;
    } catch (e) {
      return _mapearErroLogin(e);
    }
  }

  Future<String?> redefinirSenha(String email) async {
    if (email.isEmpty) return 'Informe o e-mail';
    if (!email.contains('@') || !email.contains('.')) return 'E-mail inválido';

    try {
      await _authService.enviarEmailRedefinicao(email);
      return null;
    } catch (e) {
      return _mapearErroRedefinicao(e);
    }
  }

String _mapearErroLogin(dynamic e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'user-not-found':
        return 'Usuário não encontrado';
      case 'wrong-password':
        return 'Senha incorreta';
      case 'invalid-email':
        return 'E-mail inválido';
      case 'user-disabled':
        return 'Usuário desativado';
      case 'too-many-requests':
        return 'Muitas tentativas. Tente novamente mais tarde.';
      case 'operation-not-allowed':
        return 'Operação não permitida. Contate o suporte.';
      default:
        return 'Erro: ${e.message}';
    }
  }

  // Erros de rede genéricos
  if (e.toString().toLowerCase().contains('network') ||
      e.toString().toLowerCase().contains('timeout')) {
    return 'Erro de conexão com a internet. Verifique sua rede.';
  }

  return 'Erro desconhecido ao fazer login';
}


  String _mapearErroRedefinicao(dynamic e) {
    if (e is FirebaseAuthException && e.code == 'user-not-found') {
      return 'Usuário não encontrado com esse e-mail';
    }
    return 'Erro ao enviar e-mail';
  }
}
