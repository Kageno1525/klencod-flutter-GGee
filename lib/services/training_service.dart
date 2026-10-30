import 'dart:convert';
import '../gge_client.dart';
import '../models.dart';

class TrainingService {
  final GgeClient conn;
  TrainingService(this.conn);

  Future<TransferResult> train({
    required int areaId,
    required int wodId,
    required int amount,
    int lordId = 0,
  }) async {
    try {
      final resp = await conn.sendXtAndWait(
        'bup',
        jsonEncode({
          'LID': lordId, 'WID': wodId, 'AMT': amount,
          'PO': -1, 'PWR': 0, 'SK': 0, 'SID': 0, 'AID': areaId,
        }),
        responseCmd: 'bup',
        timeoutMs: 15000,
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