import 'package:flutter/material.dart';

import '../services/lang.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'glass.dart';

/// Выбор города: поиск по встроенному списку, а чего в нём нет — по названию
/// через системный геокодер.
///
/// Возвращает выбранный город или null, если лист просто закрыли.
Future<City?> showCityPicker(BuildContext context) => showModalBottomSheet<City>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _CityPickerSheet(),
    );

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet();

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _query = TextEditingController();

  /// Найденное геокодером — показываем отдельной строкой под списком.
  City? _remote;
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _fold(String v) => v
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r"[^а-яa-z0-9]"), '');

  List<City> get _found {
    final q = _fold(_query.text);
    if (q.isEmpty) return SettingsService.cities;
    return [
      for (final c in SettingsService.cities)
        if (_fold(c.name).contains(q)) c,
    ];
  }

  Future<void> _searchRemote() async {
    final q = _query.text.trim();
    if (q.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _remote = null;
    });
    final found = await SettingsService.findCity(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searched = true;
      _remote = found;
    });
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final typed = _query.text.trim();
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: GlassSheet(
        opacity: 0.86,
        material: true,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {
                      _remote = null;
                      _searched = false;
                    }),
                    onSubmitted: (_) => _searchRemote(),
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: AppColors.gold),
                      hintText: t('Город или село'),
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45)),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.28),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.gold),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
                    children: [
                      for (final c in found)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_city,
                              size: 20, color: AppColors.gold),
                          title: Text(c.name,
                              style: const TextStyle(fontSize: 15.5)),
                          onTap: () => Navigator.pop(context, c),
                        ),
                      if (typed.isNotEmpty) _remoteRow(typed, found.isEmpty),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Строка поиска за пределами встроенного списка.
  ///
  /// Показывается всегда, когда что-то набрано, а не только при пустом
  /// списке: «Кара-Суу» есть и в Кыргызстане, и в других местах, и человек
  /// должен иметь возможность уточнить, даже если совпадение нашлось.
  Widget _remoteRow(String typed, bool listEmpty) {
    if (_searching) {
      return const ListTile(
        dense: true,
        leading: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.gold),
        ),
        title: Text(''),
      );
    }
    final remote = _remote;
    if (remote != null) {
      return ListTile(
        dense: true,
        leading:
            const Icon(Icons.place_outlined, size: 20, color: AppColors.gold),
        title: Text(remote.name, style: const TextStyle(fontSize: 15.5)),
        subtitle: Text(
          '${remote.lat.toStringAsFixed(3)}, ${remote.lon.toStringAsFixed(3)}',
          style: TextStyle(
              fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
        ),
        onTap: () => Navigator.pop(context, remote),
      );
    }
    if (_searched) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
        child: Text(
          t('Не нашли такого места. Проверьте написание или выберите\nближайший город из списка.'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.7)),
        ),
      );
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.travel_explore, size: 20, color: AppColors.gold),
      title: Text(
        listEmpty ? '${t('Найти')} «$typed»' : '${t('Искать иначе')}: «$typed»',
        style: const TextStyle(fontSize: 15, color: AppColors.goldLight),
      ),
      subtitle: Text(t('Поиск по названию — нужен интернет'),
          style: TextStyle(
              fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
      onTap: _searchRemote,
    );
  }
}
