import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/models/course_review.dart';
import '../../data/repositories/course_review_repository.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/theme/shuyo_theme.dart';
import 'rate_navigation.dart';
import 'rate_widgets.dart';

class RateHomePage extends StatefulWidget {
  const RateHomePage({
    super.key,
    required this.repository,
    required this.active,
  });

  final CourseReviewRepository repository;

  /// Whether the course review tab is the visible tab.
  final bool active;

  @override
  State<RateHomePage> createState() => _RateHomePageState();
}

class _RateHomePageState extends State<RateHomePage> {
  static const _staleAfter = Duration(minutes: 2);

  RateHome? _home;
  List<RateScheduleMatch> _matches = const [];
  Object? _error;
  bool _loading = false;
  DateTime? _loadedAt;

  CourseReviewRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant RateHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loadedAt = _loadedAt;
    if (widget.active &&
        !oldWidget.active &&
        (loadedAt == null ||
            DateTime.now().difference(loadedAt) > _staleAfter)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final matches = _repo.matchSchedule().then<List<RateScheduleMatch>?>(
        (value) => value,
        onError: (Object _) => null);
    try {
      final home = await _repo.home();
      final matched = await matches;
      if (!mounted) return;
      setState(() {
        _home = home;
        if (matched != null) _matches = matched;
        _error = null;
        _loadedAt = DateTime.now();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text('课评',
                    style:
                        ShuYoTextStyles.headerTitle(color: colors.textPrimary)),
              ),
              IconButton(
                tooltip: '个人中心',
                onPressed: () => openRateProfile(context, _repo),
                icon: const Icon(Icons.person_outline),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    final home = _home;
    if (home == null) {
      if (_error != null) {
        return RateLoadError(error: _error, onRetry: _load);
      }
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RateSearchField(
              readOnly: true,
              onTap: () => openRateSearch(context, _repo),
            ),
          ),
          if (_matches.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section('本学期课程'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ScheduleGrid(
                matches: _matches,
                onTap: _openMatch,
              ),
            ),
          ],
          if (home.recent.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section('最近评价'),
            _RecentReviewsRow(
              units: home.recent,
              active: widget.active,
              onTap: (unit) => openRateUnit(context, _repo, unit.id),
            ),
          ],
          for (final ranking in home.rankings) ...[
            const SizedBox(height: 16),
            _section(
              ranking.title,
              action: RateMoreButton(
                onPressed: () =>
                    openRateRanking(context, _repo, ranking.key, ranking.title),
              ),
            ),
            _RankingRow(
              ranking: ranking,
              onTap: (unit) => openRateUnit(context, _repo, unit.id),
            ),
          ],
          if (home.colleges.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section('按学院浏览'),
            _CollegeRow(
              colleges: home.colleges,
              onTap: (college) => openRateCollege(context, _repo, college.name),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, {Widget? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
        child: RateSectionTitle(title: title, action: action),
      );

  Future<void> _openMatch(RateScheduleMatch match) async {
    final result = match.result;
    switch (result.status) {
      case RateLookupStatus.unit:
        await openRateUnit(context, _repo, result.unit!.id);
      case RateLookupStatus.course:
        await openRateCourse(context, _repo, result.courseId,
            highlightedUnitIds: [for (final unit in result.units) unit.id]);
      case RateLookupStatus.search:
        await openRateSearch(context, _repo, query: result.query);
      case RateLookupStatus.none:
        await openRateSearch(context, _repo,
            query: result.query.isEmpty
                ? match.course.courseName
                : result.query);
    }
  }
}

class _ScheduleGrid extends StatelessWidget {
  const _ScheduleGrid({required this.matches, required this.onTap});

  final List<RateScheduleMatch> matches;
  final ValueChanged<RateScheduleMatch> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 10.0;
      final width = (constraints.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final match in matches)
            SizedBox(
              width: width,
              height: 104,
              child: _ScheduleCourseCard(match: match, onTap: () => onTap(match)),
            ),
        ],
      );
    });
  }
}

class _ScheduleCourseCard extends StatelessWidget {
  const _ScheduleCourseCard({required this.match, required this.onTap});

  final RateScheduleMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final result = match.result;
    final unit = result.unit;
    final teacher = switch (result.status) {
      RateLookupStatus.unit => unit!.teacher.displayName,
      RateLookupStatus.course when result.units.isNotEmpty =>
        result.units.map((item) => item.teacher.displayName).join('、'),
      _ => match.course.teacherName,
    };
    final score = switch (result.status) {
      RateLookupStatus.unit => rateScoreText(unit!.average),
      RateLookupStatus.course => '选择教师',
      RateLookupStatus.search => '选择课程',
      RateLookupStatus.none => '未找到',
    };
    final hasScore =
        result.status == RateLookupStatus.unit && unit!.average != null;
    return RateCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unit?.course.name ?? match.course.courseName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ShuYoTextStyles.title(
                color: colors.textPrimary, size: 14.5, height: 1.35),
          ),
          const SizedBox(height: 4),
          Text(
            teacher,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ShuYoTextStyles.meta(color: colors.textSecondary),
          ),
          const Spacer(),
          Text(
            score,
            style: hasScore
                ? ShuYoTextStyles.title(
                    color: colors.textPrimary, size: 16, weight: FontWeight.w500)
                : ShuYoTextStyles.meta(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.ranking, required this.onTap});

  final RateRankingPreview ranking;
  final ValueChanged<RateUnit> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    if (ranking.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('还没有评价，去评价你上过的课吧',
            style: ShuYoTextStyles.meta(color: colors.textTertiary)),
      );
    }
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ranking.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => RateUnitCard(
          unit: ranking.items[index],
          rank: index + 1,
          onTap: () => onTap(ranking.items[index]),
        ),
      ),
    );
  }
}

class _CollegeRow extends StatelessWidget {
  const _CollegeRow({required this.colleges, required this.onTap});

  final List<RateCollege> colleges;
  final ValueChanged<RateCollege> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: colleges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Material(
          color: colors.surface,
          shape: StadiumBorder(side: BorderSide(color: colors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onTap(colleges[index]),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: Text(colleges[index].name,
                    style: ShuYoTextStyles.label(
                        color: colors.textSecondary,
                        size: 13,
                        weight: FontWeight.w400)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slowly scrolls the recently reviewed units in a loop. Touch pauses it;
/// it resumes three seconds after release, from wherever the user left it.
class _RecentReviewsRow extends StatefulWidget {
  const _RecentReviewsRow({
    required this.units,
    required this.active,
    required this.onTap,
  });

  final List<RateUnit> units;
  final bool active;
  final ValueChanged<RateUnit> onTap;

  @override
  State<_RecentReviewsRow> createState() => _RecentReviewsRowState();
}

class _RecentReviewsRowState extends State<_RecentReviewsRow>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _cardWidth = 156.0;
  static const _gap = 10.0;
  static const _speed = 24.0;
  static const _resumeDelay = Duration(seconds: 3);

  final _controller = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  Timer? _resumeTimer;
  bool _touching = false;
  bool _foreground = true;
  bool _loops = false;

  double get _loopWidth => widget.units.length * (_cardWidth + _gap);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _RecentReviewsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = _loops &&
        widget.active &&
        _foreground &&
        !_touching &&
        !reduceMotion &&
        _resumeTimer == null;
    if (run && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!_controller.hasClients || dt <= 0 || dt > 0.5) return;
    var offset = _controller.offset + _speed * dt;
    if (offset >= _loopWidth) offset -= _loopWidth;
    _controller.jumpTo(offset);
  }

  void _pause() {
    _touching = true;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _syncTicker();
  }

  void _scheduleResume() {
    _touching = false;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeDelay, () {
      _resumeTimer = null;
      if (!mounted) return;
      // A manual fling may have left the view inside the second copy.
      if (_controller.hasClients && _controller.offset >= _loopWidth) {
        _controller.jumpTo(_controller.offset - _loopWidth);
      }
      _syncTicker();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: LayoutBuilder(builder: (context, constraints) {
        final loops = _loopWidth - _gap + 32 > constraints.maxWidth;
        if (loops != _loops) {
          _loops = loops;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncTicker();
          });
        }
        final count = loops ? widget.units.length * 2 : widget.units.length;
        return Listener(
          onPointerDown: (_) => _pause(),
          onPointerUp: (_) => _scheduleResume(),
          onPointerCancel: (_) => _scheduleResume(),
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox(width: _gap),
            itemBuilder: (context, index) {
              final unit = widget.units[index % widget.units.length];
              return _RecentCard(unit: unit, onTap: () => widget.onTap(unit));
            },
          ),
        );
      }),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.unit, required this.onTap});

  final RateUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return RateCard(
      width: _RecentReviewsRowState._cardWidth,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unit.course.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ShuYoTextStyles.title(color: colors.textPrimary, size: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            unit.teacher.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ShuYoTextStyles.meta(color: colors.textSecondary),
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                rateScoreText(unit.average),
                style: ShuYoTextStyles.title(
                    color: colors.textPrimary, size: 18, weight: FontWeight.w500),
              ),
              const SizedBox(width: 6),
              RateStars(average: unit.average, size: 12),
            ],
          ),
        ],
      ),
    );
  }
}
