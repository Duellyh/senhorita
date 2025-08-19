// lib/env_nuvem_fiscal.dart
class NuvemFiscalEnv {
  // Deixa como var p/ sobrescrever em build flavors (dev/homolog/prod).
  static String baseUrl = 'https://api.nuvemfiscal.com.br';
  static String oauthPath = '/oauth/token';

  // ⚠️ Armazena temporariamente no SecureStorage e BUSCA do servidor/Firestore
  // num doc protegido por regras. Evita embarcar em claro no código.
  static String clientId = const String.fromEnvironment(
    'NF_CLIENT_ID',
    defaultValue: '',
  );
  static String clientSecret = const String.fromEnvironment(
    'NF_CLIENT_SECRET',
    defaultValue: '',
  );

  // Identificação do emitente (podes manter/sincronizar com teu cadastro)
  static String cnpjEmitente = '12345678000195';
  static String ufEmitente = 'PA';
}
