import 'package:flutter/material.dart';

import '../services/lang.dart';
import '../services/wallpaper_service.dart';
import '../theme.dart';

/// Выбор обоев: своё фото из галереи, снимок с камеры или возврат к
/// встроенному. Вызывается из настроек и долгим нажатием на главном экране.
Future<void> showWallpaperSheet(BuildContext context) {
  final w = WallpaperService.instance;
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.skyBottom,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
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
          const SizedBox(height: 14),
          Text(t('Обои'),
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              t('Поставьте своё фото — оно останется фоном всех экранов.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: AppColors.gold),
            title: Text(t('Выбрать из галереи')),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await w.pick();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(t('Фото не выбрано'))));
              }
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.photo_camera_outlined, color: AppColors.gold),
            title: Text(t('Снять на камеру')),
            onTap: () async {
              Navigator.pop(ctx);
              await w.pick(fromCamera: true);
            },
          ),
          if (w.isCustom)
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.redAccent),
              title: Text(t('Вернуть стандартные'),
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                await w.reset();
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
