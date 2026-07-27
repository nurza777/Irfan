import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/shop_service.dart';
import '../services/lang.dart';
import '../services/date_fmt.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Магазин обмена коинов на награды (1 коин = 1 сом).
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final balance = state.coins;
    final redemptions = state.shop?.redemptions ?? [];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(t('Магазин наград')),
      ),
      body: DomeBackground(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 56, 20, 24),
            children: [
              // --- Баланс ---
              FadeSlideIn(
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.monetization_on,
                              color: AppColors.goldLight, size: 34),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(t('Доступно коинов'),
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white
                                            .withValues(alpha: 0.75))),
                                Text('$balance',
                                    style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.goldLight)),
                              ],
                            ),
                          ),
                          Text(t('1 коин = 1 сом'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white
                                      .withValues(alpha: 0.6))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: state.earnedCoins / AppState.maxCoins,
                          minHeight: 8,
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.gold),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                            appLang == Lang.ky
                    ? 'Топтолду: ${state.earnedCoins} / ${AppState.maxCoins}'
                    : 'Заработано ${state.earnedCoins} / ${AppState.maxCoins}'
                            '${state.spentCoins > 0 ? ' · потрачено ${state.spentCoins}' : ''}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white
                                    .withValues(alpha: 0.6))),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(t('Награды'),
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (var i = 0; i < shopItems.length; i++)
                _ShopCard(
                  item: shopItems[i],
                  balance: balance,
                  delayMs: 80 + i * 70,
                ),
              if (redemptions.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(t('Мои выкупы'),
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final r in redemptions) _RedemptionCard(r: r),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  final ShopItem item;
  final int balance;
  final int delayMs;
  const _ShopCard(
      {required this.item, required this.balance, required this.delayMs});

  @override
  Widget build(BuildContext context) {
    final affordable = balance >= item.cost;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FadeSlideIn(
        delay: Duration(milliseconds: delayMs),
        child: GlassCard(
          radius: 18,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.domeGreen.withValues(alpha: 0.5),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.5)),
                ),
                child: Icon(item.icon,
                    color: AppColors.goldLight, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(item.title),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(t(item.subtitle),
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                Colors.white.withValues(alpha: 0.7))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.monetization_on,
                            size: 16, color: AppColors.goldLight),
                        const SizedBox(width: 4),
                        Text('${item.cost} ${t('коин')}',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.goldLight)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: affordable
                      ? AppColors.accentGreen
                      : Colors.white.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed:
                    affordable ? () => _redeem(context, item) : null,
                child: Text(t('Обменять'),
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _redeem(BuildContext context, ShopItem item) async {
    final state = AppScope.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(t('Подтвердите обмен')),
        content: Text(
            appLang == Lang.ky
                ? '${item.cost} коинди «${t(item.title)}» үчүн алмашасызбы?\n'
                    'Калат: ${state.coins - item.cost} коин.'
                : 'Обменять ${item.cost} коинов на «${item.title}»?\n'
                    'Останется: ${state.coins - item.cost} коинов.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Отмена'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Обменять')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final r = await state.redeem(item);
    if (r == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('Недостаточно коинов'))));
      }
      return;
    }
    if (context.mounted) _showCode(context, r);
  }

  void _showCode(BuildContext context, Redemption r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(t('Награда получена! 🎉')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('«${t(r.title)}»', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold),
              ),
              child: Text(r.code,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: AppColors.goldLight)),
            ),
            const SizedBox(height: 12),
            Text(t('Покажите этот код устазу, чтобы получить награду.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7))),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentGreen),
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Готово')),
          ),
        ],
      ),
    );
  }
}

class _RedemptionCard extends StatelessWidget {
  final Redemption r;
  const _RedemptionCard({required this.r});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.card_giftcard,
                color: AppColors.goldLight, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t(r.title),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(
                      '${fmtDateShort(r.date)} · '
                      '${r.cost} ${t('коин')}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Text(r.code,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppColors.goldLight)),
          ],
        ),
      ),
    );
  }
}
