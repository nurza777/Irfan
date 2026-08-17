import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../services/certificate_service.dart';
import '../services/date_fmt.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/certificate_sheet.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Выданные ученику дипломы и сертификаты.
class CertificatesScreen extends StatelessWidget {
  const CertificatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final female = AppScope.of(context).auth?.current?.gender.name == 'female';
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(t('Мои сертификаты')),
      ),
      body: DomeBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: CertificateService.instance,
            builder: (context, _) {
              final items = CertificateService.instance.items;
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: GlassCard(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspace_premium_outlined,
                              size: 42, color: AppColors.gold),
                          const SizedBox(height: 12),
                          Text(
                            t('Сертификаты появятся здесь после завершения '
                                'модуля или курса.'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 74, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, i) => _CertCard(
                  cert: items[i],
                  female: female,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CertCard extends StatelessWidget {
  final Certificate cert;
  final bool female;
  const _CertCard({required this.cert, required this.female});

  String get _kind => switch (cert.template) {
        'certificate' => t('Сертификат'),
        'gift' => t('Подарочный сертификат'),
        _ => t('Диплом'),
      };

  @override
  Widget build(BuildContext context) {
    final isNew = CertificateService.instance.isNew(cert);
    return PressableScale(
      onTap: () {
        CertificateService.instance.markSeen(cert);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CertificateViewer(cert: cert, female: female),
          ),
        );
      },
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Уменьшенный бланк вместо иконки: человек узнаёт свой документ
            // в лицо, а не по подписи под ним.
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: CertificateSheet.width / CertificateSheet.height,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: CertificateSheet(cert: cert, female: female),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _kind,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.gold, width: 1),
                    ),
                    child: Text(t('новый'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.goldLight)),
                  ),
              ],
            ),
            if (cert.title.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(cert.title,
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.75))),
            ],
            const SizedBox(height: 6),
            Text(
              '№ ${cert.number} · ${fmtDateLong(cert.issuedAt)}',
              style: TextStyle(
                  fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Бланк во весь экран: с увеличением пальцами и кнопкой «Поделиться».
///
/// Лист альбомный, а всё приложение закреплено в портрете — здесь поворот
/// разрешаем, как в полноэкранном плеере урока, и возвращаем портрет на
/// выходе.
class CertificateViewer extends StatefulWidget {
  final Certificate cert;
  final bool female;

  /// Только для отладочной проверки: нажать кнопку «Поделиться» в симуляторе
  /// нечем, а снимок бланка в файл — самое хрупкое место в разделе.
  final bool autoShare;

  const CertificateViewer({
    super.key,
    required this.cert,
    required this.female,
    this.autoShare = false,
  });

  @override
  State<CertificateViewer> createState() => _CertificateViewerState();
}

class _CertificateViewerState extends State<CertificateViewer> {
  final _shot = GlobalKey();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (widget.autoShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), _share);
      });
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  /// Снимает бланк в файл и отдаёт системному «Поделиться».
  ///
  /// Пишем в кэш, а не в документы: файл нужен ровно на время отправки, и
  /// копить в памяти телефона одни и те же дипломы незачем.
  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _shot.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      // Пиксельная плотность подобрана так, чтобы ширина вышла около 2000
      // точек — это годится и для печати, и для отправки в мессенджере.
      final image = await boundary.toImage(
          pixelRatio: 2000 / CertificateSheet.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.cert.number}.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: '${widget.cert.name} · № ${widget.cert.number}',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('Не удалось сохранить')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.cert.number,
            style: const TextStyle(fontSize: 16, letterSpacing: 0.5)),
        actions: [
          IconButton(
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.gold))
                : const Icon(Icons.ios_share),
            tooltip: t('Поделиться'),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: FittedBox(
            fit: BoxFit.contain,
            // Снимаем ровно то, что видно: RepaintBoundary внутри FittedBox
            // отдаёт бланк в исходном размере, а не в размере экрана.
            child: RepaintBoundary(
              key: _shot,
              child: CertificateSheet(
                  cert: widget.cert, female: widget.female),
            ),
          ),
        ),
      ),
    );
  }
}
