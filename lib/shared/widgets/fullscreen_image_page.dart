import 'package:flutter/material.dart';

class FullscreenImagePage extends StatelessWidget {
  const FullscreenImagePage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(96),
                child: SizedBox.expand(
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Text(
                          '图片加载失败',
                          style: TextStyle(color: Color(0xFFBDBDBD)),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
