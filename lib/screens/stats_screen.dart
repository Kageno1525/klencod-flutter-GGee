import 'package:flutter/material.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/models.dart';
import 'package:gge/services/stats_service.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';

class StatsScreen extends StatefulWidget {
  final GgeClient client;
  const StatsScreen({super.key, required this.client});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<CastleStats> _castles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.client.loadCatalog();
      final stats =
          await StatsService(widget.client).getAllCastleStats(catalog: catalog);
      if (!mounted) return;
      setState(() {
        _castles = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _fmt(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AppTheme.background(context),
          SafeArea(
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: _loading
                      ? const Center(
                          child:
                              CircularProgressIndicator(color: AppTheme.purple))
                      : _error != null
                          ? _errorView(context)
                          : _castles.isEmpty
                              ? _emptyView(context)
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  color: AppTheme.purple,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 8, 16, 24),
                                    itemCount: _castles.length,
                                    itemBuilder: (_, i) => FadeSlideIn(
                                      delay:
                                          Duration(milliseconds: 80 + i * 60),
                                      child: _castleCard(_castles[i]),
                                    ),
                                  ),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          AppIconBtn(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.statsTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textColor(context),
                    letterSpacing: -0.3,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  '${_castles.length} ${S.isAr ? "قلعة" : "castles"}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.subTextColor(context),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          AppIconBtn(
            icon: Icons.refresh_rounded,
            onTap: _loading ? null : _load,
            size: 42,
          ),
        ],
      ),
    );
  }

  Widget _errorView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppTheme.glassCard(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppTheme.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontSize: 13,
                    decoration: TextDecoration.none),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded,
                    color: AppTheme.purple),
                label: Text(S.retry,
                    style: const TextStyle(
                        color: AppTheme.purple,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyView(BuildContext context) {
    return Center(
      child: Text(
        S.noCastles,
        style: TextStyle(
            color: AppTheme.subTextColor(context),
            decoration: TextDecoration.none),
      ),
    );
  }

  Widget _castleCard(CastleStats c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: AppTheme.glassCard(
        context: context,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.castle_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name ?? 'Castle ${c.areaId}',
                        style: TextStyle(
                            color: AppTheme.textColor(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            decoration: TextDecoration.none),
                      ),
                      Text(
                        '${_kingdomName(c.kingdomId)} · ${S.defenseStat}: ${c.defense}',
                        style: TextStyle(
                            color: AppTheme.subTextColor(context),
                            fontSize: 11,
                            decoration: TextDecoration.none),
                      ),
                    ],
                  ),
                ),
                InfoChip(
                  icon: Icons.groups_rounded,
                  label: _fmt(c.totalUnits),
                  color: AppTheme.teal,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _resChip('Wood', c.wood, c.maxWood, c.deltaWood,
                    Icons.park_rounded, const Color(0xFF4CAF50)),
                _resChip('Stone', c.stone, c.maxStone, c.deltaStone,
                    Icons.landscape_rounded, const Color(0xFF9E9E9E)),
                _resChip('Food', c.food, c.maxFood, c.deltaFood,
                    Icons.restaurant_rounded, const Color(0xFFFF9800)),
                _resChip('Coal', c.coal, c.maxCoal, c.deltaCoal,
                    Icons.local_fire_department_rounded,
                    const Color(0xFF424242)),
                _resChip('Iron', c.iron, c.maxIron, c.deltaIron,
                    Icons.hardware_rounded, const Color(0xFF607D8B)),
                _resChip('Glass', c.glass, c.maxGlass, c.deltaGlass,
                    Icons.water_drop_rounded, const Color(0xFF03A9F4)),
                _resChip('Honey', c.honey, c.maxHoney, c.deltaHoney,
                    Icons.emoji_nature_rounded, const Color(0xFFFFC107)),
                _resChip('Mead', c.mead, c.maxMead, c.deltaMead,
                    Icons.local_drink_rounded, const Color(0xFF795548)),
              ],
            ),
            if (c.units.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(
                  color: AppTheme.subTextColor(context).withOpacity(0.1)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: c.units.take(8).map((u) {
                  return InfoChip(
                    icon: u.info?.role == 'ranged'
                        ? Icons.gps_fixed_rounded
                        : Icons.gavel_rounded,
                    label: '${S.unitName(u.displayName)} ${u.amount}',
                    color: u.roleColor,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resChip(String name, int current, int max, double delta,
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none),
              ),
              Text(
                '${_fmt(current)} / ${_fmt(max)}',
                style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none),
              ),
              if (delta > 0)
                Text(
                  '+${_fmt(delta)}/${S.perHour}',
                  style: TextStyle(
                      color: color,
                      fontSize: 9,
                      decoration: TextDecoration.none),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _kingdomName(int kid) => switch (kid) {
        0 => 'Great Empire',
        1 => 'Burning Sands',
        2 => 'Everwinter',
        3 => 'Fire Peaks',
        4 => 'Storm Islands',
        _ => 'K$kid',
      };
}