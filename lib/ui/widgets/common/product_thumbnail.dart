import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/app_theme.dart';

class ProductThumbnail extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final double borderRadius;
  final IconData placeholderIcon;

  const ProductThumbnail({
    super.key,
    this.imageUrl,
    this.size = 48,
    this.borderRadius = AppDesignTokens.radiusSm,
    this.placeholderIcon = Icons.checkroom,
  });

  @override
  Widget build(BuildContext context) {
    Widget? imageWidget;

    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      final file = File(imageUrl!);
      if (file.existsSync()) {
        imageWidget = Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      } else if (imageUrl!.startsWith('http://') ||
          imageUrl!.startsWith('https://')) {
        imageWidget = Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
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
