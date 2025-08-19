// lib/services/nuvem_fiscal_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import '../env_nuvem_fiscal.dart';

class NuvemFiscalApi {
  NuvemFiscalApi._();
  static final NuvemFiscalApi instance = NuvemFiscalApi._();

  final _storage = const FlutterSecureStorage();
  static const _kTokenKey = 'nf_access_token';
  static const _kTokenExpKey = 'nf_access_token_exp';

  String get _base => NuvemFiscalEnv.baseUrl;

  Future<String> _getToken() async {
    final cached = await _storage.read(key: _kTokenKey);
    final expStr = await _storage.read(key: _kTokenExpKey);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (cached != null && expStr != null) {
      final exp = int.tryParse(expStr) ?? 0;
      if (exp - 30 > now) return cached; // margem de 30s
    }

    final url = Uri.parse('$_base${NuvemFiscalEnv.oauthPath}');
    final body = {
      'grant_type': 'client_credentials',
      'client_id': NuvemFiscalEnv.clientId,
      'client_secret': NuvemFiscalEnv.clientSecret,
    };

    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final token = (data['access_token'] ?? '').toString();
      final expiresIn = (data['expires_in'] ?? 3600) as int;
      final exp = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + expiresIn;

      await _storage.write(key: _kTokenKey, value: token);
      await _storage.write(key: _kTokenExpKey, value: exp.toString());
      return token;
    }

    throw Exception('Falha ao obter token: ${res.statusCode} ${res.body}');
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_base$path'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('GET $path -> ${res.statusCode} ${res.body}');
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$_base$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('POST $path -> ${res.statusCode} ${res.body}');
  }

  // 3.1 Cadastrar/atualizar empresa emitente (se necessário)
  Future<Map<String, dynamic>> cadastrarEmpresa({
    required String cnpj,
    required String razaoSocial,
    required String nomeFantasia,
    required String inscricaoEstadual,
    required int crt, // 1=Simples, 2=Simples Exc, 3=Regime normal...
    required String uf,
    // Certificado A1 em base64 e senha
    String? certificadoBase64,
    String? certificadoSenha,
  }) {
    return _postJson('/nfe/empresas', {
      'cpf_cnpj': cnpj,
      'razao_social': razaoSocial,
      'nome_fantasia': nomeFantasia,
      'inscricao_estadual': inscricaoEstadual,
      'crt': crt,
      'uf': uf,
      if (certificadoBase64 != null && certificadoSenha != null)
        'certificado': {
          'alias': 'cert_a1',
          'senha': certificadoSenha,
          'arquivo': certificadoBase64,
        },
    });
  }

  // 3.2 Emitir NF-e
  Future<Map<String, dynamic>> emitirNFe(Map<String, dynamic> nfe) {
    return _postJson('/nfe', nfe);
  }

  // 3.3 Consultar NF-e por id
  Future<Map<String, dynamic>> consultarNFe(String id) async {
    return _getJson('/nfe/$id');
  }

  // 3.4 Baixar DANFE (PDF) como bytes
  Future<List<int>> baixarDanfePdf(String id) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_base/nfe/$id/pdf'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw Exception('PDF $id -> ${res.statusCode} ${res.body}');
  }

  // 3.5 Baixar XML como bytes
  Future<List<int>> baixarXml(String id) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_base/nfe/$id/xml'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw Exception('XML $id -> ${res.statusCode} ${res.body}');
  }

  // Emitir NFC-e
  Future<Map<String, dynamic>> emitirNFCe(Map<String, dynamic> nfce) {
    return _postJson('/nfce', nfce);
  }

  // Consultar NFC-e
  Future<Map<String, dynamic>> consultarNFCe(String id) {
    return _getJson('/nfce/$id');
  }

  // Baixar DANFE NFC-e (PDF Cupom)
  Future<List<int>> baixarDanfeNFCePdf(String id) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_base/nfce/$id/pdf'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw Exception('PDF NFC-e $id -> ${res.statusCode} ${res.body}');
  }

  // Baixar XML NFC-e
  Future<List<int>> baixarNFCeXml(String id) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_base/nfce/$id/xml'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw Exception('XML NFC-e $id -> ${res.statusCode} ${res.body}');
  }
}
