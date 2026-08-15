import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/visual_effects.dart';
import '../theme.dart';

/// Стеклянный блок: блюр того, что за ним, полупрозрачная заливка
/// с лёгким градиентом и тонкая светлая рамка.
///
/// В экономном режиме ([VisualEffects]) размытие не рисуется: остаётся та же
/// заливка, чуть плотнее, чтобы текст читался поверх фотографии без матовой
/// подложки. Это главная правка ради Android — карточек на экране до шести, а
/// в чтении Корана по одной на каждый аят, и каждая просила движок отдельно
/// размыть то, что под ней, заново на каждом кадре прокрутки.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  /// Насколько тёмная заливка (0 — почти прозрачная).
  final double darkness;

  /// Выделенное состояние: золотая рамка вместо светлой. Один способ
  /// показать «выбрано» на всё приложение.
  final bool selected;

  /// Тень под карточкой. Обои — ночное фото с яркими огнями, и без тени
  /// край стекла на них теряется.
  final bool elevated;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding,
    this.blur = 16,
    this.darkness = 0.28,
    this.selected = false,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VisualEffects.instance,
      builder: (context, _) => _build(VisualEffects.instance.blur),
    );
  }

  Widget _build(bool blurred) {
    // Без размытия фотография просвечивает резко, и текст на ней теряется —
    // добираем плотностью подложки. Величина подобрана по снимку экрана: на
    // обоях по умолчанию под карточкой времён намаза оказывается подсвеченный
    // циферблат башни, и цифры читались поверх ярко-зелёного.
    //
    // Красить приходится именно градиентом: в `BoxDecoration` он перекрывает
    // `color` целиком (шейдер вытесняет цвет в `Paint`), поэтому заливка тут
    // всегда была декоративной и ни на что не влияла. В полном режиме
    // градиент идёт от белого блика — на размытом фоне это и читается как
    // стекло; без размытия тот же блик высветляет карточку, и его убираем.
    final fill = blurred ? darkness : (darkness + 0.38).clamp(0.0, 1.0);
    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
            color: selected
                ? AppColors.selection
                : Colors.white.withValues(alpha: 0.16),
            width: selected ? 1.4 : 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: blurred
              ? [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: darkness + 0.14),
                ]
              : [
                  Colors.black.withValues(alpha: fill),
                  Colors.black.withValues(alpha: (fill + 0.12).clamp(0.0, 1.0)),
                ],
        ),
      ),
      child: child,
    );
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blurred
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: inner,
            )
          : inner,
    );
    if (!elevated) return card;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: card,
    );
  }
}

/// Размытие фона там, где оно включено, и ничего — где выключено.
///
/// Ставится ровно на место `BackdropFilter`: обёртка одноуровневая, поэтому
/// листы, собиравшие стекло вручную, переводятся заменой одной строки.
class MaybeBlur extends StatelessWidget {
  final Widget child;
  final double sigma;
  const MaybeBlur({super.key, required this.child, this.sigma = 24});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VisualEffects.instance,
      builder: (context, _) => VisualEffects.instance.blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: child,
            )
          : child,
    );
  }
}

/// Плотность подложки листа. Без размытия за ней остаётся резкая фотография:
/// на снимке экрана сквозь меню «···» читались и карточка времён намаза, и
/// нижняя панель. Лист в экономном режиме — почти сплошная панель.
double sheetAlpha(double full) =>
    VisualEffects.instance.blur ? full : (full + 0.20).clamp(0.0, 1.0);

/// Подложка модального листа — то же стекло, что у карточек, но во всю
/// ширину и со скруглением только сверху. Раньше каждый лист собирал эту
/// конструкцию сам, и переключить их разом было негде.
class GlassSheet extends StatelessWidget {
  final Widget child;

  /// Насколько плотна подложка в полном режиме. В экономном к ней добавляется
  /// непрозрачности: за листом остаётся резкая фотография.
  final double opacity;
  final double radius;
  final double blur;

  /// Обернуть подложку в [Material] — нужно листам, внутри которых есть
  /// нажимаемые строки: без него у них негде рисовать отклик.
  final bool material;

  const GlassSheet({
    super.key,
    required this.child,
    this.opacity = 0.9,
    this.radius = 24,
    this.blur = 24,
    this.material = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VisualEffects.instance,
      builder: (context, _) {
        final blurred = VisualEffects.instance.blur;
        final color = AppColors.skyBottom.withValues(alpha: sheetAlpha(opacity));
        final Widget inner = material
            ? Material(color: color, child: child)
            : ColoredBox(color: color, child: child);
        return ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
          child: blurred
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: inner,
                )
              : inner,
        );
      },
    );
  }
}

/// Заголовок раздела поверх обоев. Собственная подложка нужна потому, что
/// текст ложится прямо на фото: над тёмным небом он читается, над подсвеченной
/// башней — уже нет.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    // Без Spacer: он забирал всё свободное место, и заголовок ужимался до
    // «Последн…», хотя строка была наполовину пустой.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

/// Пилюля выбора: один вид на все экраны — настройки, язык, фильтры.
/// Выбранная золотая, остальные — стекло.
class SelectPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool dense;

  const SelectPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          // Высота 38–42 pt: палец попадает уверенно, но кнопка не
          // занимает пол-экрана.
          padding: EdgeInsets.symmetric(
              horizontal: dense ? 13 : 16, vertical: dense ? 8 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: selected
                ? AppColors.selection.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: selected
                  ? AppColors.selection
                  : Colors.white.withValues(alpha: 0.18),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16,
                    color: selected ? AppColors.goldLight : AppColors.textSoft),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                    fontSize: dense ? 13.5 : 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.cream : AppColors.textSoft,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плавное появление: прозрачность + сдвиг, со стартовой задержкой —
/// удобно для каскадной анимации блоков экрана.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 550),
    this.offset = const Offset(0, 26),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  /// Каскад появления блоков — самое заметное место открытия экрана: на
  /// главной их с полдюжины, и каждый добавляет слой прозрачности и сдвиг
  /// поверх остальной отрисовки. В экономном режиме блок просто появляется.
  late final bool _animate = VisualEffects.instance.animated;

  AnimationController? _c;
  Animation<double>? _a;

  @override
  void initState() {
    super.initState();
    if (!_animate) return;
    final c = AnimationController(vsync: this, duration: widget.duration);
    _c = c;
    _a = CurvedAnimation(parent: c, curve: Curves.easeOutCubic);
    if (widget.delay == Duration.zero) {
      c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return widget.child;
    return AnimatedBuilder(
      animation: a,
      builder: (context, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(
          offset: widget.offset * (1 - a.value),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Отклик на нажатие: лёгкое «пружинное» сжатие.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const PressableScale({super.key, required this.child, this.onTap});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Мягко пульсирующая золотая точка — «живой» индикатор.
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulsingDot({super.key, required this.color, this.size = 8});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  /// Точка пульсирует бесконечно, то есть держит экран перерисовывающимся всё
  /// время, пока видна. В экономном режиме она просто горит.
  late final AnimationController? _c = VisualEffects.instance.animated
      ? (AnimationController(
          vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true))
      : null;

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return _dot;
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
      child: _dot,
    );
  }

  Widget get _dot => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
                color: widget.color.withValues(alpha: 0.6), blurRadius: 8),
          ],
        ),
      );
}
