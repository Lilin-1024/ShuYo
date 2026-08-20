import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Route<T> lehuRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoPageRoute<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      builder: (context) => _LehuRouteSurface(child: builder(context)),
    );
  }
  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 210),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _LehuRouteSurface(child: builder(context));
    },
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final begin = fullscreenDialog ? const Offset(0, 1) : const Offset(1, 0);
      final position = animation.drive(
        Tween<Offset>(begin: begin, end: Offset.zero).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
      );
      return SlideTransition(position: position, child: child);
    },
  );
}

class _LehuRouteSurface extends StatelessWidget {
  const _LehuRouteSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }
}
