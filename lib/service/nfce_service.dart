// lib/service/nfce_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class NfceService {
  static const String _baseUrl = 'http://localhost:3333';

  Future<Map<String, dynamic>> emitirNfce(
    Map<String, dynamic> dadosNfce,
  ) async {
    final url = Uri.parse('$_baseUrl/emitir-nfce');

    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(dadosNfce),
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } else {
      throw Exception('Erro HTTP ${resp.statusCode}: ${resp.body}');
    }
  }
}
