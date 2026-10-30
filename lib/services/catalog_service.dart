import 'dart:convert';
import 'dart:io';
import '../models.dart';

class CatalogService {
  Map<int, UnitCatalogEntry>? _cache;

  Future<Map<int, UnitCatalogEntry>> load({bool forceReload = false}) async {
    if (!forceReload && _cache != null) return _cache!;
    final http = HttpClient();
    try {
      final vReq = await http.getUrl(Uri.parse(
          'https://empire-html5.goodgamestudios.com/default/items/ItemsVersion.properties'));
      final vResp = await vReq.close();
      final vBody = await vResp.transform(utf8.decoder).join();
      final version = vBody.split('=').last.trim();

      final iReq = await http.getUrl(Uri.parse(
          'https://empire-html5.goodgamestudios.com/default/items/items_v$version.json'));
      final iResp = await iReq.close();
      final iBody = await iResp.transform(utf8.decoder).join();
      final data = jsonDecode(iBody) as Map<String, dynamic>;

      final catalog = <int, UnitCatalogEntry>{};
      for (final u in data['units'] as List) {
        if (u is! Map) continue;
        final id = _asInt(u['wodID'], -1);
        if (id < 0) continue;
        catalog[id] = UnitCatalogEntry(
          wodId: id,
          type: u['type'] as String?,
          role: u['role'] as String?,
          name: u['name'] as String?,
          fightType: _asIntOrNull(u['fightType']),
        );
      }
      _cache = catalog;
      return catalog;
    } finally {
      http.close();
    }
  }

  static int _asInt(dynamic v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }

  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}