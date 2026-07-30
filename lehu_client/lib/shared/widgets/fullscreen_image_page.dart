import 'package:flutter/material.dart';

import '../../data/services/forum_image_headers.dart';
import '../../data/services/image_saver.dart';

class FullscreenImagePage extends StatefulWidget {
  FullscreenImagePage({
    super.key,
    String? url,
    List<String>? urls,
    this.initialIndex = 0,
  }) : urls = urls ?? (url == null ? const <String>[] : <String>[url]);

  final List<String> urls;
  final int initialIndex;

  @override
  State<FullscreenImagePage> createState() => _FullscreenImagePageState();
}

class _FullscreenImagePageState extends State<FullscreenImagePage> {
  late final PageController _pageController;
  late int _index;
  bool _currentPageZoomed = false;

  @override
  void initState() {
    super.initState();
    _index = _clampIndex(widget.initialIndex);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: urls.isEmpty
                ? const Center(
                    child: Text(
                      '图片加载失败',
                      style: TextStyle(color: Color(0xFFBDBDBD)),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    onLongPress: () => _showImageActions(urls[_index]),
                    child: PageView.builder(
                      controller: _pageController,
                      physics: _currentPageZoomed
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(),
                      itemCount: urls.length,
                      onPageChanged: (value) {
                        setState(() {
                          _index = value;
                          _currentPageZoomed = false;
                        });
                      },
                      itemBuilder: (context, index) {
                        return _ZoomableNetworkImage(
                          key: ValueKey(urls[index]),
                          url: urls[index],
                          onSwipePrevious: _previousPage,
                          onSwipeNext: _nextPage,
                          onZoomChanged: (zoomed) {
                            if (_index != index ||
                                _currentPageZoomed == zoomed) {
                              return;
                            }
                            setState(() => _currentPageZoomed = zoomed);
                          },
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 6),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  tooltip: '关闭',
                ),
              ),
            ),
          ),
          if (urls.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Text(
                        '${_index + 1} / ${urls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showImageActions(String url) async {
    const sheetBackground = Color(0xFF111111);
    const actionForeground = Color(0xFFF2F2F2);
    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: sheetBackground,
      showDragHandle: false,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 6, bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7A7A7A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                ListTile(
                  iconColor: actionForeground,
                  textColor: actionForeground,
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('保存图片'),
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (shouldSave == true) {
      await _saveImage(url);
    }
  }

  Future<void> _saveImage(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('正在保存图片...')));
    try {
      await ImageSaver.saveNetworkImage(url);
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('图片已保存到相册')));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  void _previousPage() => _animateToPage(_index - 1);

  void _nextPage() => _animateToPage(_index + 1);

  void _animateToPage(int index) {
    if (index < 0 || index >= widget.urls.length) {
      return;
    }
    setState(() => _currentPageZoomed = false);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  int _clampIndex(int value) {
    if (widget.urls.isEmpty || value < 0) {
      return 0;
    }
    final maxIndex = widget.urls.length - 1;
    return value > maxIndex ? maxIndex : value;
  }
}

class _ZoomableNetworkImage extends StatefulWidget {
  const _ZoomableNetworkImage({
    super.key,
    required this.url,
    required this.onZoomChanged,
    required this.onSwipePrevious,
    required this.onSwipeNext,
  });

  final String url;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onSwipePrevious;
  final VoidCallback onSwipeNext;

  @override
  State<_ZoomableNetworkImage> createState() => _ZoomableNetworkImageState();
}

class _ZoomableNetworkImageState extends State<_ZoomableNetworkImage> {
  static const _pageSwipeThreshold = 72.0;
  static const _edgeTolerance = 2.0;

  final _controller = TransformationController();
  late final ImageStreamListener _imageListener;
  ImageStream? _imageStream;
  Map<String, String>? _headers;
  Size? _imageSize;
  Size? _viewportSize;
  bool _headersLoaded = false;
  bool _zoomed = false;
  bool _clamping = false;
  bool _pageSwipeTriggered = false;
  double _horizontalDrag = 0;

  @override
  void initState() {
    super.initState();
    _imageListener = ImageStreamListener((info, _) {
      _imageSize = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      _clampTransform();
    });
    _controller.addListener(_handleTransformChanged);
    _loadHeaders();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_headersLoaded) {
      _resolveImage();
    }
  }

  @override
  void didUpdateWidget(covariant _ZoomableNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _imageSize = null;
      _headers = null;
      _headersLoaded = false;
      _controller.value = Matrix4.identity();
      _setZoomed(false);
      _loadHeaders();
    }
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageListener);
    _controller
      ..removeListener(_handleTransformChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (!_headersLoaded) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: 5,
          panEnabled: _zoomed,
          scaleEnabled: true,
          boundaryMargin: EdgeInsets.zero,
          onInteractionStart: (_) {
            _horizontalDrag = 0;
            _pageSwipeTriggered = false;
          },
          onInteractionUpdate: _handleInteractionUpdate,
          onInteractionEnd: (_) {
            _horizontalDrag = 0;
            _pageSwipeTriggered = false;
            _resetIfNeeded();
          },
          child: SizedBox.expand(
            child: Center(
              child: Image.network(
                widget.url,
                fit: BoxFit.contain,
                headers: _headers,
                errorBuilder: (context, error, stackTrace) {
                  return const Text(
                    '图片加载失败',
                    style: TextStyle(color: Color(0xFFBDBDBD)),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _resolveImage() {
    if (!_headersLoaded) {
      return;
    }
    final oldStream = _imageStream;
    final newStream = NetworkImage(widget.url, headers: _headers).resolve(
      createLocalImageConfiguration(context),
    );
    if (oldStream?.key == newStream.key) {
      return;
    }
    oldStream?.removeListener(_imageListener);
    _imageStream = newStream..addListener(_imageListener);
  }

  Future<void> _loadHeaders() async {
    final headers = await ForumImageHeaders.forUrl(widget.url);
    if (!mounted) {
      return;
    }
    setState(() {
      _headers = headers;
      _headersLoaded = true;
    });
    _resolveImage();
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    if (!_zoomed || details.pointerCount > 1 || _pageSwipeTriggered) {
      return;
    }
    final delta = details.focalPointDelta;
    if (delta.dx.abs() <= delta.dy.abs()) {
      return;
    }
    _horizontalDrag += delta.dx;
    if (_horizontalDrag > _pageSwipeThreshold && _isAtLeftEdge) {
      _pageSwipeTriggered = true;
      widget.onSwipePrevious();
    } else if (_horizontalDrag < -_pageSwipeThreshold && _isAtRightEdge) {
      _pageSwipeTriggered = true;
      widget.onSwipeNext();
    }
  }

  void _handleTransformChanged() {
    if (_clamping) {
      return;
    }
    final scale = _controller.value.getMaxScaleOnAxis();
    if (scale <= 1.01) {
      _setZoomed(false);
      return;
    }
    _setZoomed(true);
    _clampTransform();
  }

  void _resetIfNeeded() {
    if (_controller.value.getMaxScaleOnAxis() <= 1.01) {
      _controller.value = Matrix4.identity();
      _setZoomed(false);
      return;
    }
    _clampTransform();
  }

  void _clampTransform() {
    final horizontal = _translationBounds(horizontal: true);
    final vertical = _translationBounds(horizontal: false);
    if (horizontal == null || vertical == null) {
      return;
    }
    final matrix = _controller.value.clone();
    final nextX = matrix.storage[12].clamp(horizontal.min, horizontal.max);
    final nextY = matrix.storage[13].clamp(vertical.min, vertical.max);
    if ((nextX - matrix.storage[12]).abs() < 0.1 &&
        (nextY - matrix.storage[13]).abs() < 0.1) {
      return;
    }
    matrix.storage[12] = nextX.toDouble();
    matrix.storage[13] = nextY.toDouble();
    _clamping = true;
    _controller.value = matrix;
    _clamping = false;
  }

  bool get _isAtLeftEdge {
    final bounds = _translationBounds(horizontal: true);
    if (bounds == null) {
      return true;
    }
    return _controller.value.storage[12] >= bounds.max - _edgeTolerance;
  }

  bool get _isAtRightEdge {
    final bounds = _translationBounds(horizontal: true);
    if (bounds == null) {
      return true;
    }
    return _controller.value.storage[12] <= bounds.min + _edgeTolerance;
  }

  _TranslationBounds? _translationBounds({required bool horizontal}) {
    final viewport = _viewportSize;
    final image = _imageSize;
    if (viewport == null || image == null) {
      return null;
    }
    final fitted = _fittedImageSize(viewport, image);
    final viewportExtent = horizontal ? viewport.width : viewport.height;
    final fittedExtent = horizontal ? fitted.width : fitted.height;
    final baseOffset = (viewportExtent - fittedExtent) / 2;
    final scale = _controller.value.getMaxScaleOnAxis();
    final scaledExtent = fittedExtent * scale;
    if (scaledExtent <= viewportExtent) {
      final centered = (viewportExtent - scaledExtent) / 2 - baseOffset * scale;
      return _TranslationBounds(centered, centered);
    }
    final min = viewportExtent - (baseOffset + fittedExtent) * scale;
    final max = -baseOffset * scale;
    return _TranslationBounds(min, max);
  }

  Size _fittedImageSize(Size viewport, Size image) {
    final imageRatio = image.width / image.height;
    final viewportRatio = viewport.width / viewport.height;
    if (imageRatio > viewportRatio) {
      return Size(viewport.width, viewport.width / imageRatio);
    }
    return Size(viewport.height * imageRatio, viewport.height);
  }

  void _setZoomed(bool value) {
    if (_zoomed == value) {
      return;
    }
    _zoomed = value;
    widget.onZoomChanged(value);
    if (mounted) {
      setState(() {});
    }
  }
}

class _TranslationBounds {
  const _TranslationBounds(this.min, this.max);

  final double min;
  final double max;
}
