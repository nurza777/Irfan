import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/rating_service.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Соревнование: общая таблица, круг друзей и приглашения.
///
/// Смысл не в числах, а в том, чтобы держать привычку. Поэтому:
/// — очки растут от намазов и зикров, то есть от того самого, ради чего
///   приложение и нужно;
/// — рядом с общей сотней есть круг друзей, где место видно и новичку:
///   в таблице из тысячи человек сто первый не увидит себя никогда, а среди
///   пятерых знакомых соревнование настоящее;
/// — приглашение даёт очки не сразу, а когда позванный сам начнёт читать.
class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  /// Поле ввода кода. Поле класса, а не переменная в build: созданный
  /// в build контроллер не освобождается и теряет введённое при каждой
  /// перерисовке.
  final _codeInput = TextEditingController();
  Rating _data = const Rating(status: RatingStatus.offline);
  bool _loading = true;
  String _phone = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _phone = AppScope.of(context).auth?.current?.phone ?? '';
      _load();
    });
  }

  @override
  void dispose() {
    _codeInput.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_phone.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    // Сначала отправляем свою свежую статистику, потом просим таблицу:
    // иначе человек увидит свои же прошлые очки и решит, что счёт не идёт.
    await AppScope.of(context).refreshAccess();
    final d = await RatingService.load(_phone);
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(t('Соревнование')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, color: AppColors.gold),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.cream,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: t('Топ-100')),
            Tab(text: t('Друзья')),
            Tab(text: t('Пригласить')),
          ],
        ),
      ),
      body: DomeBackground(
        child: SafeArea(
          child: _phone.isEmpty
              ? Center(child: _needAccount())
              : _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.gold))
                  : _data.status != RatingStatus.ok
                      ? Center(child: _problem())
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            _board(_data.top, global: true),
                            _board(_data.friends, global: false),
                            _invite(_data),
                          ],
                        ),
        ),
      ),
    );
  }

  /// Что показать, когда таблицы нет. Причина у каждого случая своя, и
  /// совет «проверьте интернет» уместен ровно в одном из них.
  Widget _problem() {
    final text = switch (_data.status) {
      RatingStatus.offline => t('Нет связи с сервером'),
      RatingStatus.denied => t('Соревнование недоступно на этом устройстве. '
          'Если вы переносили аккаунт, войдите заново.'),
      RatingStatus.noProfile => t('Ваша анкета ещё не дошла до сервера. '
          'Откройте приложение при интернете — и место появится.'),
      RatingStatus.ok => '',
    };
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.7))),
    );
  }

  Widget _needAccount() => Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 52, color: AppColors.textFaint),
            const SizedBox(height: 14),
            Text(
              t('Соревнование идёт между аккаунтами — войдите или '
                  'зарегистрируйтесь, и ваши намазы начнут приносить очки.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      );

  /// Полоска «моё место» — она нужнее самой таблицы: в общей сотне человек
  /// ищет прежде всего себя.
  Widget _mine() {
    final d = _data;
    final rank = d.myRank;
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle_outlined,
              color: AppColors.goldLight),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rank == null
                      ? t('Ваше место появится после первых намазов')
                      : '${t('Ваше место')}: $rank ${t('из')} ${d.total}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('${d.myPoints} ${t('очков')}',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7))),
                if (d.hidden) ...[
                  const SizedBox(height: 4),
                  Text(
                      t('Вы скрыты из общей таблицы — место видно только вам'),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textFaint)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _board(List<RatingRow> rows, {required bool global}) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.gold,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _mine(),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                global
                    ? t('Таблица пока пуста.')
                    : t('Здесь появятся те, кого вы позвали, и те, кто '
                        'позвал вас. Пригласите друга — соревноваться '
                        'со знакомыми интереснее.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.6)),
              ),
            )
          else
            for (final r in rows) RatingRowTile(row: r),
        ],
      ),
    );
  }

  Widget _invite(Rating d) {
    final ref = d.referral;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        GlassCard(
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(t('Ваш код приглашения'),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.65))),
              const SizedBox(height: 10),
              SelectableText(
                ref.code.isEmpty ? '—' : ref.code,
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: AppColors.goldLight),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ref.code.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(
                                  ClipboardData(text: ref.code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t('Код скопирован'))));
                            },
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(t('Скопировать')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: ref.code.isEmpty
                          ? null
                          : () => SharePlus.instance.share(ShareParams(
                                text: t('Присоединяйся к «Ирфану» — '
                                        'время намаза, Коран и зикры. '
                                        'Мой код приглашения: ') +
                                    ref.code,
                              )),
                      icon: const Icon(Icons.share, size: 18),
                      label: Text(t('Поделиться')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          radius: 18,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t('Пришло по коду')}: ${ref.invited}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('${t('Зачтено')}: ${ref.counted} · '
                  '${t('начислено')} ${ref.bonus} ${t('очков')}',
                  style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.white.withValues(alpha: 0.75))),
              const SizedBox(height: 10),
              Text(
                // Условие пишем прямо, а не мелким шрифтом внизу: человек
                // должен понимать, почему друг пришёл, а очков нет.
                '${t('Очки приходят не за регистрацию, а когда друг прочитает')} '
                '${ref.minPrayers} ${t('намазов')} — '
                '${ref.perFriend} ${t('очков за каждого')}.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _enterCode(),
      ],
    );
  }

  Widget _enterCode() {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Вас кто-то пригласил?'),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(t('Введите его код — попадёте в круг друзей. Один раз.'),
              style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeInput,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'ABC123',
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () async {
                  final err =
                      await RatingService.applyCode(_phone, _codeInput.text);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(err == null ? t('Код принят') : t(err)),
                    backgroundColor:
                        err == null ? AppColors.accentGreen : null,
                  ));
                  if (err == null) _load();
                },
                child: Text(t('Применить')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Строка таблицы соревнования.
///
/// Вынесена из экрана отдельным виджетом, чтобы её можно было проверить
/// виджет-тестом: экран целиком тянет за собой сеть и состояние приложения,
/// а строка — самая заметная часть и там же всего легче ошибиться.
class RatingRowTile extends StatelessWidget {
  final RatingRow row;
  const RatingRowTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final r = row;
    // Первые три места — медалями: так таблица читается взглядом, а не
    // чтением чисел.
    final medal = switch (r.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: r.me
            ? AppColors.gold.withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(14),
        border: r.me
            ? Border.all(color: AppColors.gold.withValues(alpha: 0.6))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: medal != null
                ? Text(medal, style: const TextStyle(fontSize: 20))
                : Text('${r.rank}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.6))),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.me ? '${r.name} · ${t('вы')}' : r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: r.me ? FontWeight.w700 : FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    '${r.prayers} ${t('намазов')}'
                    '${r.streak > 0 ? ' · ${t('серия')} ${r.streak}' : ''}',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Text('${r.points}',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.goldLight)),
        ],
      ),
    );
  }
}
