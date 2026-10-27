import 'dart:async';
import 'package:flutter/material.dart';

import '../../../shared/theme/shuyo_theme.dart';

/// Time remaining before the current enterprise WeChat scan session expires.
class WeComScanCountdown extends StatefulWidget {
  const WeComScanCountdown({
    super.key,
    required this.duration,
    this.startedAt,
    this.clock,
  });

  final Duration duration;
  final DateTime? startedAt;

  /// Optional clock for tests. The default is the device wall clock.
  final DateTime Function()? clock;

  @override
  State<WeComScanCountdown> createState() => _WeComScanCountdownState();
}

class _WeComScanCountdownState extends State<WeComScanCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _startedAt;
  late int _remainingMicroseconds;
  bool _backgrounded = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reset();
  }

  @override
  void didUpdateWidget(covariant WeComScanCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration ||
        oldWidget.startedAt != widget.startedAt ||
        oldWidget.clock != widget.clock) {
      _reset();
    }
  }

  void _reset() {
    _timer?.cancel();
    _startedAt = widget.startedAt ?? _now;
    _remainingMicroseconds = _calculateRemaining();
    _startTimer();
  }

  int _calculateRemaining() {
    final total = widget.duration.inMicroseconds;
    if (total <= 0) return 0;
    final elapsed = _now.difference(_startedAt).inMicroseconds;
    return (total - elapsed).clamp(0, total);
  }

  void _startTimer() {
    if (_backgrounded ||
        _remainingMicroseconds <= 0 ||
        _timer?.isActive == true) {
      return;
    }
    // Recalculate from the wall clock at roughly display-frame intervals so
    // progress moves smoothly while remaining accurate after delayed callbacks.
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _update());
  }

  void _update() {
    final remaining = _calculateRemaining();
    if (remaining <= 0) _timer?.cancel();
    if (remaining != _remainingMicroseconds && mounted) {
      setState(() => _remainingMicroseconds = remaining);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      _update();
      _startTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgrounded = true;
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final total = widget.duration.inMicroseconds;
    final remainingSeconds =
        (_remainingMicroseconds + Duration.microsecondsPerSecond - 1) ~/
            Duration.microsecondsPerSecond;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final textScaler = MediaQuery.textScalerOf(context);
    return Row(
      children: [
        SizedBox(
          width: textScaler.scale(56),
          child: Text('剩余', textAlign: TextAlign.end, style: textStyle),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: LinearProgressIndicator(
            value: total <= 0 ? 0 : _remainingMicroseconds / total,
            minHeight: 3,
            color: colors.accent,
            backgroundColor: colors.accentSoft,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: textScaler.scale(56),
          height: textScaler.scale(20),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${remainingSeconds}s', style: textStyle),
          ),
        ),
      ],
    );
  }
}
