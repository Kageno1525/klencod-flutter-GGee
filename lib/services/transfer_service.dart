import 'dart:convert';
import '../gge_client.dart';
import '../models.dart';
import 'commanders_service.dart';

class TransferService {
  final GgeClient conn;
  final CommandersService commanders;
  TransferService(this.conn, this.commanders);

  Future<TransferResult> transfer({
    required OwnedCastle source,
    required OwnedCastle target,
    required List<List<int>> units,
    int? lordId,
  }) async {
    final filtered = <List<int>>[];
    for (final u in units) {
      if (u.length >= 2 && u[1] > 0) filtered.add([u[0], u[1]]);
    }
    if (filtered.isEmpty) return TransferResult.fail('No units selected');

    int lid = lordId ?? -1;
    if (lid == -1) {
      final cmds = await commanders.getCommanders();
      final free = cmds.where((c) => !c.isBusy).toList();
      if (free.isEmpty) return TransferResult.fail('ALL_LORDS_BUSY');
      lid = free.first.lord.id;
    }

    if (source.kingdomId == target.kingdomId) {
      try {
        conn.sendXt('sti', jsonEncode({
          'SX': source.x, 'SY': source.y,
          'TX': target.x, 'TY': target.y,
          'KID': target.kingdomId,
        }));
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (_) {}

      try {
        final catResp = await conn.sendXtAndWait(
          'cat',
          jsonEncode({
            'SX': source.x, 'SY': source.y,
            'TX': target.x, 'TY': target.y,
            'KID': target.kingdomId,
            'LID': lid, 'WT': 0, 'HBW': -1, 'BPC': 0,
            'PTT': 0, 'SD': 0, 'A': filtered,
          }),
          responseCmd: 'cat',
          timeoutMs: 25000,
          isAction: true,
        );
        if (catResp.resultCode == 0) return TransferResult.ok();
        return _tryKut(source, target, filtered, sameKingdom: true);
      } catch (_) {
        return _tryKut(source, target, filtered, sameKingdom: true);
      }
    }
    return _tryKut(source, target, filtered, sameKingdom: false);
  }

  Future<TransferResult> _tryKut(
    OwnedCastle source,
    OwnedCastle target,
    List<List<int>> units, {
    required bool sameKingdom,
  }) async {
    try {
      final resp = await conn.sendXtAndWait(
        'kut',
        jsonEncode({
          'SCID': source.areaId,
          'SKID': source.kingdomId,
          'TKID': target.kingdomId,
          'CID': sameKingdom ? target.areaId : -1,
          'A': units,
        }),
        responseCmd: 'kut',
        timeoutMs: 25000,
        isAction: true,
      );
      if (resp.resultCode != 0) {
        return TransferResult.fail(errorName(resp.resultCode));
      }
      return TransferResult.ok();
    } catch (e) {
      return TransferResult.fail('$e');
    }
  }
}