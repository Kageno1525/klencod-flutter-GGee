import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gge/gge_client.dart';
import 'package:gge/l10n/strings.dart';
import 'package:gge/models.dart';
import 'package:gge/theme.dart';
import 'package:gge/widgets/animated_widgets.dart';

class TransferScreen extends StatefulWidget {
  final GgeClient client;
  const TransferScreen({super.key, required this.client});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  List<OwnedCastle> _castles = [];
  Map<int, UnitCatalogEntry> _catalog = {};
  List<CommanderInfo> _commanders = [];

  OwnedCastle? _source;
  OwnedCastle? _target;
  Lord? _selectedLord;

  List<CastleUnit> _units = [];
  final Map<int, TextEditingController> _amtCtrl = {};

  bool _loadingUnits = false;
  bool _loadingCommanders = false;
  bool _sending = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final castles = await widget.client.getCastles();
      final catalog = await widget.client.loadCatalog();
      if (!mounted) return;
      setState(() {
        _castles = castles;
        _catalog = catalog;
        if (_castles.isNotEmpty) {
          _source = _castles.firstWhere(
            (c) => c.areaType == 1,
            orElse: () => _castles.first,
          );
          _target = _castles.firstWhere(
            (c) => c.areaId != _source!.areaId,
            orElse: () => _castles.first,
          );
        }
      });
      await _loadCommanders();
    } catch (e) {
      _snack('$e', color: AppTheme.red);
    }
  }

  Future<void> _loadCommanders() async {
    setState(() => _loadingCommanders = true);
    try {
      final cmds = await widget.client.getCommanders();
      if (!mounted) return;
      setState(() {
        _commanders = cmds;
        _loadingCommanders = false;
        final free = _commanders.where((c) => !c.isBusy).toList();
        if (_selectedLord == null && free.isNotEmpty) {
          _selectedLord = free.first.lord;
        } else if (_selectedLord != null) {
          final current = _commanders.firstWhere(
            (c) => c.lord.id == _selectedLord!.id,
            orElse: () => CommanderInfo(lord: _selectedLord!),
          );
          if (current.isBusy) _selectedLord = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCommanders = false);
    }
  }

  Future<void> _loadUnits() async {
    if (_source == null) return;
    setState(() {
      _loadingUnits = true;
      _units = [];
      for (final c in _amtCtrl.values) c.dispose();
      _amtCtrl.clear();
    });

    try {
      final units = await widget.client
          .getCastleUnits(_source!.kingdomId, _source!.areaId, _catalog);
      if (!mounted) return;
      setState(() {
        _units = units;
        for (final u in units) {
          _amtCtrl[u.wodId] = TextEditingController(text: '0');
        }
        _loadingUnits = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUnits = false);
      _snack('$e', color: AppTheme.red);
    }
  }

  List<CastleUnit> get _filtered {
    switch (_filter) {
      case 'offense':
        return _units.where((u) => u.isCombat && !u.isDefensive).toList();
      case 'defense':
        return _units.where((u) => u.isCombat && u.isDefensive).toList();
      case 'all':
      default:
        return _units.where((u) => u.isCombat).toList();
    }
  }

  int get _totalSelected {
    int total = 0;
    for (final u in _units) {
      final amt = int.tryParse(_amtCtrl[u.wodId]?.text ?? '0') ?? 0;
      if (amt > 0) total += amt;
    }
    return total;
  }

  void _selectAllInFilter() {
    for (final u in _filtered) {
      _amtCtrl[u.wodId]?.text = u.amount.toString();
    }
    setState(() {});
  }

  void _deselectAll() {
    for (final c in _amtCtrl.values) c.text = '0';
    setState(() {});
  }

  Future<void> _send() async {
    if (_source == null || _target == null) return;
    if (_source!.areaId == _target!.areaId &&
        _source!.kingdomId == _target!.kingdomId) {
      _snack(S.sameCastleError, color: AppTheme.orange);
      return;
    }
    if (_selectedLord == null) {
      _snack(S.allLordsBusy, color: AppTheme.red);
      return;
    }

    final toSend = <List<int>>[];
    for (final u in _units) {
      final amt = int.tryParse(_amtCtrl[u.wodId]?.text ?? '0') ?? 0;
      if (amt > 0) {
        final real = amt.clamp(0, u.amount);
        if (real > 0) toSend.add([u.wodId, real]);
      }
    }

    if (toSend.isEmpty) {
      _snack(S.noUnitsSelected, color: AppTheme.orange);
      return;
    }

    setState(() => _sending = true);
    final result = await widget.client.transfer(
      source: _source!,
      target: _target!,
      units: toSend,
      lordId: _selectedLord!.id,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result.success) {
      _snack('✓ ${S.transferOk}', color: AppTheme.green);
      HapticFeedback.mediumImpact();

      setState(() {
        final sentMap = <int, int>{};
        for (var item in toSend) sentMap[item[0]] = item[1];

        for (int i = 0; i < _units.length; i++) {
          if (sentMap.containsKey(_units[i].wodId)) {
            _units[i] = CastleUnit(
              wodId: _units[i].wodId,
              amount: _units[i].amount - sentMap[_units[i].wodId]!,
              info: _units[i].info,
            );
          }
        }
        _units.removeWhere((u) => u.amount <= 0);
        _deselectAll();
      });

      _loadCommanders();
    } else {
      _snack('${S.transferFail}: ${result.error}', color: AppTheme.red);
    }
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(decoration: TextDecoration.none)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  void dispose() {
    for (final c in _amtCtrl.values) c.dispose();
    super.dispose();
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
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 100),
                        child: _castlePickers(context),
                      ),
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 200),
                        child: _lordPicker(context),
                      ),
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 300),
                        child: _loadBar(context),
                      ),
                      if (_loadingUnits) ...[
                        const SizedBox(height: 24),
                        Center(
                          child: Column(
                            children: [
                              const CircularProgressIndicator(
                                  color: AppTheme.purple),
                              const SizedBox(height: 14),
                              Text(
                                S.loadingUnits,
                                style: TextStyle(
                                    color: AppTheme.subTextColor(context),
                                    fontSize: 12,
                                    decoration: TextDecoration.none),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!_loadingUnits && _units.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 400),
                          child: _filterRow(context),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(_filtered.length, (i) {
                          return FadeSlideIn(
                            delay: Duration(milliseconds: 450 + i * 40),
                            child: _unitRow(context, _filtered[i]),
                          );
                        }),
                        const SizedBox(height: 16),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 600),
                          child: _summaryCard(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_units.isNotEmpty && !_loadingUnits)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 700),
                offset: const Offset(0, 0.2),
                child: GradientButton(
                  label: '${S.send} ($_totalSelected)',
                  icon: Icons.send_rounded,
                  gradient: AppTheme.primaryGradient,
                  loading: _sending,
                  onPressed: _send,
                ),
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
                  S.transferTroops,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textColor(context),
                    letterSpacing: -0.3,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  S.transferDesc,
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
            onTap: _source == null || _loadingUnits ? null : _loadUnits,
            size: 42,
          ),
        ],
      ),
    );
  }

  Widget _castlePickers(BuildContext context) {
    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _castleField(
            context,
            label: S.from,
            value: _source,
            color: AppTheme.teal,
            onChanged: (v) {
              setState(() => _source = v);
              _loadUnits();
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppTheme.subTextColor(context).withOpacity(0.1),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    final tmp = _source;
                    _source = _target;
                    _target = tmp;
                    setState(() {});
                    _loadUnits();
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.purple.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppTheme.purple.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.swap_vert_rounded,
                        color: AppTheme.purple, size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppTheme.subTextColor(context).withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
          _castleField(
            context,
            label: S.to,
            value: _target,
            color: AppTheme.blue,
            onChanged: (v) => setState(() => _target = v),
          ),
        ],
      ),
    );
  }

  Widget _castleField(
    BuildContext context, {
    required String label,
    required OwnedCastle? value,
    required Color color,
    required ValueChanged<OwnedCastle?> onChanged,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(Icons.castle_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.subTextColor(context),
                  letterSpacing: 0.8,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 2),
              DropdownButtonHideUnderline(
                child: DropdownButton<OwnedCastle>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textColor(context),
                  ),
                  items: _castles
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.fullLabel,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AppTheme.textColor(context),
                                    fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lordPicker(BuildContext context) {
    final freeLords =
        _commanders.where((c) => !c.isBusy).map((c) => c.lord).toList();
    if (_selectedLord != null &&
        !freeLords.any((l) => l.id == _selectedLord!.id)) {
      _selectedLord = null;
    }

    return AppTheme.glassCard(
      context: context,
      padding: const EdgeInsets.all(14),
      child: _loadingCommanders
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.purple),
              ),
            )
          : Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppTheme.orange.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: AppTheme.orange, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.selectLord,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.subTextColor(context),
                          letterSpacing: 0.8,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<Lord>(
                          value: _selectedLord,
                          isExpanded: true,
                          isDense: true,
                          dropdownColor:
                              Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textColor(context),
                          ),
                          items: [
                            DropdownMenuItem<Lord>(
                              value: null,
                              child: Text(S.autoLord,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textColor(context))),
                            ),
                            ...freeLords.map((l) => DropdownMenuItem(
                                  value: l,
                                  child: Text(l.displayName,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color:
                                              AppTheme.textColor(context))),
                                )),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedLord = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _loadBar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _filterChip(context, 'all', S.allUnits),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _filterChip(context, 'offense', S.offenseOnly),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _filterChip(context, 'defense', S.defenseOnly),
        ),
      ],
    );
  }

  Widget _filterChip(BuildContext context, String key, String label) {
    final selected = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? AppTheme.primaryGradient : null,
          color: selected
              ? null
              : Theme.of(context).colorScheme.surface.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : AppTheme.subTextColor(context).withOpacity(0.1),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.purple.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.subTextColor(context),
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _filterRow(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: _selectAllInFilter,
          icon: const Icon(Icons.done_all_rounded,
              size: 16, color: AppTheme.teal),
          label: Text(S.selectAll,
              style: const TextStyle(
                  color: AppTheme.teal,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _deselectAll,
          icon: Icon(Icons.clear_all_rounded,
              size: 16, color: AppTheme.subTextColor(context)),
          label: Text(S.deselectAll,
              style: TextStyle(
                  color: AppTheme.subTextColor(context),
                  fontSize: 12,
                  decoration: TextDecoration.none)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _unitRow(BuildContext context, CastleUnit u) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surface
            .withOpacity(AppTheme.isDark(context) ? 0.55 : 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: u.roleColor.withOpacity(0.2),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  u.roleColor.withOpacity(0.3),
                  u.roleColor.withOpacity(0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: u.roleColor.withOpacity(0.4)),
            ),
            child: Icon(u.icon, color: u.roleColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.unitName(u.displayName), // ✅ Arabic
                  style: TextStyle(
                    color: AppTheme.textColor(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    decoration: TextDecoration.none,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.inventory_2_rounded,
                        size: 11, color: AppTheme.teal),
                    const SizedBox(width: 3),
                    Text(
                      '${S.available}: ${u.amount}',
                      style: TextStyle(
                          color: AppTheme.subTextColor(context),
                          fontSize: 10.5,
                          decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 85,
            height: 40,
            child: TextField(
              controller: _amtCtrl[u.wodId],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textColor(context),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: '0',
                hintStyle: TextStyle(
                    color: AppTheme.subTextColor(context).withOpacity(0.5)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: AppTheme.subTextColor(context).withOpacity(0.1)),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              _amtCtrl[u.wodId]?.text = u.amount.toString();
              setState(() {});
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppTheme.successGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.keyboard_double_arrow_up_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.purple.withOpacity(0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.calculate_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              S.total,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Text(
            '$_totalSelected',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 26,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}