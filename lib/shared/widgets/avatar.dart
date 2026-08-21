import 'package:flutter/material.dart';

import '../theme/lehu_theme.dart';
import 'forum_network_image.dart';

class ForumAvatar extends StatelessWidget {
  const ForumAvatar({
    super.key,
    required this.url,
    this.size = 36,
    this.privateImage = false,
  });

  final String url;
  final double size;
  final bool privateImage;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _AvatarFallback(size: size);
    }
    return ClipOval(
      child: ForumNetworkImage(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        privateImage: privateImage,
        pinned: privateImage,
        errorBuilder: (context, error, stackTrace) {
          return _AvatarFallback(size: size);
        },
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: colors.surfaceMuted,
        alignment: Alignment.center,
        child: Icon(
          Icons.person,
          size: size * 0.56,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
