import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as dev;

class VendasService {
  VendasService._();
  static final instance = VendasService._();

  final _db = FirebaseFirestore.instance;

  Future<void> cancelarVendaSoft({
    required String vendaId,
    String motivo = 'Cancelada manualmente',
  }) async {
    final vendaRef = _db.collection('vendas').doc(vendaId);
    final user = FirebaseAuth.instance.currentUser;

    try {
      // 1) TRANSAÇÃO: devolve estoque + marca venda como cancelada
      await _db.runTransaction((tx) async {
        final vendaSnap = await tx.get(vendaRef);
        if (!vendaSnap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'Venda $vendaId não encontrada.',
          );
        }
        final venda = vendaSnap.data() as Map<String, dynamic>;
        final itens = List<Map<String, dynamic>>.from(venda['itens'] ?? []);

        await _devolverEstoqueEmProdutos(tx, itens);

        tx.update(vendaRef, {
          'status': 'cancelada',
          'canceladaEm': FieldValue.serverTimestamp(),
          'canceladaPor': user?.uid,
          'motivoCancelamento': motivo,
        });

        final logRef = _db.collection('vendas_cancelamentos').doc();
        tx.set(logRef, {
          'vendaId': vendaRef.id,
          'quando': FieldValue.serverTimestamp(),
          'por': user?.uid,
          'motivo': motivo,
          'snapshotVenda': venda,
          'tipo': 'soft',
        });
      });

      // 2) BATCH: marca todos os "vendidos" dessa venda
      final vendidosQuery = await _db
          .collection('vendidos')
          .where('vendaId', isEqualTo: vendaId)
          .get();

      if (vendidosQuery.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in vendidosQuery.docs) {
          batch.update(doc.reference, {
            'status': 'cancelado',
            'estornado': true,
            'canceladoEm': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } on FirebaseException catch (e) {
      dev.log(
        'cancelarVendaSoft FirebaseException: ${e.code} ${e.message}',
        name: 'VendasService',
      );
      rethrow;
    } catch (e) {
      dev.log('cancelarVendaSoft erro: $e', name: 'VendasService');
      rethrow;
    }
  }

  Future<void> cancelarVendaHardDelete({
    required String vendaId,
    String motivo = 'Exclusão de venda',
  }) async {
    final vendaRef = _db.collection('vendas').doc(vendaId);
    final user = FirebaseAuth.instance.currentUser;

    try {
      Map<String, dynamic>? vendaSnapshotForLog;

      await _db.runTransaction((tx) async {
        final vendaSnap = await tx.get(vendaRef);
        if (!vendaSnap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'Venda $vendaId não encontrada.',
          );
        }
        final venda = vendaSnap.data() as Map<String, dynamic>;
        vendaSnapshotForLog = venda;
        final itens = List<Map<String, dynamic>>.from(venda['itens'] ?? []);

        await _devolverEstoqueEmProdutos(tx, itens);
        tx.delete(vendaRef);

        final logRef = _db.collection('vendas_cancelamentos').doc();
        tx.set(logRef, {
          'vendaId': vendaRef.id,
          'quando': FieldValue.serverTimestamp(),
          'por': user?.uid,
          'motivo': motivo,
          'snapshotVenda': vendaSnapshotForLog,
          'tipo': 'hard',
        });
      });

      final vendidosQuery = await _db
          .collection('vendidos')
          .where('vendaId', isEqualTo: vendaId)
          .get();

      if (vendidosQuery.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in vendidosQuery.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } on FirebaseException catch (e) {
      dev.log(
        'cancelarVendaHardDelete FirebaseException: ${e.code} ${e.message}',
        name: 'VendasService',
      );
      rethrow;
    } catch (e) {
      dev.log('cancelarVendaHardDelete erro: $e', name: 'VendasService');
      rethrow;
    }
  }

  Future<void> _devolverEstoqueEmProdutos(
    Transaction tx,
    List<Map<String, dynamic>> itens,
  ) async {
    for (final item in itens) {
      final produtoId = _resolverProdutoId(item);
      if (produtoId == null || produtoId.isEmpty) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'invalid-argument',
          message: 'Item sem produtoId. Ajuste o campo do item da venda: $item',
        );
      }

      final prodRef = _db.collection('produtos').doc(produtoId);
      final prodSnap = await tx.get(prodRef);
      if (!prodSnap.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'Produto $produtoId não encontrado.',
        );
      }

      final prodData = prodSnap.data() as Map<String, dynamic>;

      final qtdVendida = _parseInt(item['quantidade'], defaultValue: 1);
      final String? tam = _text(item['tamanho']);

      final Map<String, dynamic>? tamanhos =
          (prodData['tamanhos'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(prodData['tamanhos'])
          : null;

      if (tamanhos != null && tam != null && tam.isNotEmpty) {
        final atual = _parseInt(tamanhos[tam], defaultValue: 0);
        final totalAtual = _parseInt(prodData['quantidade'], defaultValue: 0);

        tx.update(prodRef, {
          'tamanhos.$tam': atual + qtdVendida,
          'quantidade':
              totalAtual + qtdVendida, // se você mantém total agregado
        });
      } else {
        final totalAtual = _parseInt(prodData['quantidade'], defaultValue: 0);
        tx.update(prodRef, {'quantidade': totalAtual + qtdVendida});
      }
    }
  }

  // ===== helpers =====

  String? _resolverProdutoId(Map<String, dynamic> item) {
    // tenta várias chaves comuns
    final direct =
        (item['produtoId'] ??
                item['idProduto'] ??
                item['produtoDocId'] ??
                item['id'])
            ?.toString();

    if (direct != null && direct.isNotEmpty) return direct;

    // às vezes o item vem como um submapa 'produto'
    if (item['produto'] is Map) {
      final p = Map<String, dynamic>.from(item['produto']);
      final nested = (p['id'] ?? p['documentId'] ?? p['produtoId'])?.toString();
      if (nested != null && nested.isNotEmpty) return nested;
    }
    return null;
  }

  int _parseInt(dynamic v, {int defaultValue = 0}) {
    if (v == null) return defaultValue;
    if (v is int) return v;
    if (v is double) return v.round();
    final s = v.toString().replaceAll(RegExp(r'[^0-9\-\+]'), '');
    return int.tryParse(s) ?? defaultValue;
  }

  String? _text(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
