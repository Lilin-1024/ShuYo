import 'package:flutter/material.dart';

import '../../data/models/user_profile.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/forum_network_image.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.title,
    required this.subtitle,
    this.avatarUrl,
    this.backgroundUrl,
    this.onTap,
    this.trailing,
  });

  final UserProfile profile;
  final String title;
  final String subtitle;
  final String? avatarUrl;
  final String? backgroundUrl;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final header = SizedBox(
      height: 176,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 122,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _ProfileBackground(
                url: backgroundUrl ?? profile.profileBackgroundUrl(),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 88,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: ForumAvatar(
                url: avatarUrl ?? profile.avatarUrl(size: 144),
                size: 68,
              ),
            ),
          ),
          Positioned(
            left: 102,
            right: 0,
            top: 128,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LehuTextStyles.title(
                          size: 19,
                          height: 1.22,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFBDBDBD)),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return header;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: header,
    );
  }
}

class _ProfileBackground extends StatelessWidget {
  const _ProfileBackground({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF26332F),
              Color(0xFF171717),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }
    return ForumNetworkImage(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const DecoratedBox(
          decoration: BoxDecoration(color: Color(0xFF202020)),
        );
      },
    );
  }
}
