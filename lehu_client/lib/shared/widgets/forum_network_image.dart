import 'package:flutter/material.dart';

import '../../data/services/forum_image_headers.dart';

class ForumNetworkImage extends StatefulWidget {
  const ForumNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<ForumNetworkImage> createState() => _ForumNetworkImageState();
}

class _ForumNetworkImageState extends State<ForumNetworkImage> {
  late Future<Map<String, String>?> _headersFuture;

  @override
  void initState() {
    super.initState();
    _headersFuture = ForumImageHeaders.forUrl(widget.url);
  }

  @override
  void didUpdateWidget(covariant ForumNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _headersFuture = ForumImageHeaders.forUrl(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>?>(
      future: _headersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(width: widget.width, height: widget.height);
        }
        return Image.network(
          widget.url,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          headers: snapshot.data,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }
}
