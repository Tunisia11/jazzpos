import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/app_theme.dart';

class ProductThumbnail extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final double borderRadius;
  final IconData placeholderIcon;
  final BoxFit fit;

  const ProductThumbnail({
    super.key,
    this.imageUrl,
    this.size = 48,
    this.borderRadius = AppDesignTokens.radiusSm,
    this.placeholderIcon = Icons.checkroom,
    this.fit = BoxFit.cover,
  });

  File? _resolveEffectiveFile() {
    if (imageUrl == null || imageUrl!.trim().isEmpty) return null;

    final resolved = AppPaths.instance.resolveImagePath(imageUrl!);
    if (resolved == null) return null;

    // Check if thumbnail sibling exists in same directory
    final dir = p.dirname(resolved);
    for (final ext in ['jpg', 'png', 'webp', 'jpeg']) {
      final thumbPath = p.join(dir, 'thumb.$ext');
      final thumbFile = File(thumbPath);
      if (thumbFile.existsSync()) {
        return thumbFile;
      }
    }

    final mainFile = File(resolved);
    if (mainFile.existsSync()) {
      return mainFile;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    Widget? imageWidget;

    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      if (imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://')) {
        imageWidget = Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: fit,
          errorBuilder: (_, error, ___) {
            PosLogger.instance.warning('Thumbnail', 'Network image error: $error');
            return _buildPlaceholder();
          },
        );
      } else {
        final file = _resolveEffectiveFile();
        if (file != null) {
          imageWidget = Image.file(
            file,
            width: size,
            height: size,
            fit: fit,
            cacheWidth: (size * 2).toInt(),
            cacheHeight: (size * 2).toInt(),
            errorBuilder: (_, error, ___) {
              PosLogger.instance.warning(
                'Thumbnail',
                'Failed to decode image file ${file.path}: $error',
              );
              return _buildPlaceholder();
            },
          );
        }
      }
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 1),
        child: imageWidget ?? _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        placeholderIcon,
        color: AppDesignTokens.textMuted,
        size: size * 0.48,
      ),
    );
  }
}
