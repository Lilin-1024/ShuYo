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
    this.onImageSize,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ValueChanged<Size>? onImageSize;

  @override
  State<ForumNetworkImage> createState() => _ForumNetworkImageState();
}

class _ForumNetworkImageState extends State<ForumNetworkImage> {
  late Future<Map<String, String>?> _headersFuture;
  late final ImageStreamListener _imageStreamListener;
  ImageProvider<Object>? _imageProvider;
  ImageStream? _imageStream;
  Size? _decodedSize;

  @override
  void initState() {
    super.initState();
    _headersFuture = ForumImageHeaders.forUrl(widget.url);
    _imageStreamListener = ImageStreamListener(
      _handleImageFrame,
      onError: (Object error, StackTrace? stackTrace) => _detachImageStream(),
    );
  }

  @override
  void didUpdateWidget(covariant ForumNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _detachImageStream();
      _imageProvider = null;
      _decodedSize = null;
      _headersFuture = ForumImageHeaders.forUrl(widget.url);
    } else if (oldWidget.onImageSize == null && widget.onImageSize != null) {
      final provider = _imageProvider;
      if (provider != null) {
        _listenForImageSize(provider);
      }
      _reportDecodedSize();
    } else if (oldWidget.onImageSize != null && widget.onImageSize == null) {
      _detachImageStream();
    }
  }

  @override
  void dispose() {
    _detachImageStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>?>(
      future: _headersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _ImagePlaceholder(
            width: widget.width,
            height: widget.height,
          );
        }
        final provider = _ensureImageProvider(snapshot.data);
        return Image(
          image: provider,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }

  ImageProvider<Object> _ensureImageProvider(Map<String, String>? headers) {
    final existing = _imageProvider;
    if (existing != null) {
      return existing;
    }
    final provider = NetworkImage(widget.url, headers: headers);
    _imageProvider = provider;
    if (widget.onImageSize != null) {
      _listenForImageSize(provider);
    }
    return provider;
  }

  void _listenForImageSize(ImageProvider<Object> provider) {
    if (_imageStream != null) {
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _imageStream = stream;
    stream.addListener(_imageStreamListener);
  }

  void _detachImageStream() {
    _imageStream?.removeListener(_imageStreamListener);
    _imageStream = null;
  }

  void _handleImageFrame(ImageInfo info, bool synchronousCall) {
    final scale = info.scale > 0 ? info.scale : 1.0;
    final size = Size(
      info.image.width / scale,
      info.image.height / scale,
    );
    if (_decodedSize == size) {
      return;
    }
    _decodedSize = size;
    _detachImageStream();
    _reportDecodedSize();
  }

  void _reportDecodedSize() {
    final size = _decodedSize;
    final url = widget.url;
    if (size == null || widget.onImageSize == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.url == url) {
        widget.onImageSize?.call(size);
      }
    });
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}
