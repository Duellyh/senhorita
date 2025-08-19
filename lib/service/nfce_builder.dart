// lib/services/nfce_builder.dart
import 'package:intl/intl.dart';

class NFCeBuilder {
  static String _agoraISO() {
    final now = DateTime.now();
    final off = now.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    String two(int n) => n.toString().padLeft(2, '0');
    final tz =
        '$sign${two(off.inHours.abs())}:${two(off.inMinutes.abs() % 60)}';
    return DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(now) + tz;
  }

  /// items: [{codigo, descricao, ncm, cfop, unidade, qtd, unit, total, csosn/cst, origem, aliquota?...}]
  /// pagamentos: lista de maps ex: [{"forma":1,"valor":50.0},{"forma":3,"valor":70.0}]
  static Map<String, dynamic> build({
    required String idInterno,
    required int serie,
    required int numero,
    required String cnpjEmitente,
    required List<Map<String, dynamic>> items,
    Map<String, dynamic>? destinatario, // pode ser null p/ consumidor anônimo
    List<Map<String, dynamic>>? pagamentos,
    double? descontoTotal,
    double? frete,
  }) {
    final totalItens = items.fold<double>(
      0.0,
      (acc, e) => acc + (e['total'] as num).toDouble(),
    );
    final desc = descontoTotal ?? 0.0;
    final freteVal = frete ?? 0.0;
    final valorNota = totalItens - desc + freteVal;

    return {
      'id': idInterno,
      'natureza_operacao': 'Venda ao consumidor',
      'modelo': '65', // NFC-e
      'serie': serie,
      'numero': numero,
      'emissao': {'data': _agoraISO(), 'tipo': 1, 'finalidade': 1},
      'emitente': {'cpf_cnpj': cnpjEmitente},
      if (destinatario != null) 'destinatario': destinatario,
      'itens': List.generate(items.length, (i) {
        final it = items[i];
        return {
          'numero_item': i + 1,
          'produto': {
            'codigo': it['codigo'],
            'descricao': it['descricao'],
            'ncm': it['ncm'],
            'cfop': it['cfop'] ?? '5102',
            'unidade_comercial': it['unidade'] ?? 'UN',
            'quantidade_comercial': it['qtd'],
            'valor_unitario': it['unit'],
            'valor_total': it['total'],
            if (desc > 0) 'desconto': 0,
          },
          'impostos': {
            'icms': {
              'origem': it['origem'] ?? 0,
              if (it['csosn'] != null) 'csosn': it['csosn'],
              if (it['cst'] != null) 'cst': it['cst'],
              if (it['aliquota'] != null) 'aliquota': it['aliquota'],
            },
          },
        };
      }),
      'transporte': {
        'modalidade_frete': 9, // 9 = sem frete (padrão NFC-e)
      },
      'pagamentos':
          pagamentos ??
          [
            {
              'forma': 1, // 1=dinheiro
              'valor': double.parse(valorNota.toStringAsFixed(2)),
            },
          ],
    };
  }
}
