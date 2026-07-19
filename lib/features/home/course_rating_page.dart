import 'package:flutter/material.dart';

import '../../data/models/course_rating.dart';
import '../../data/repositories/course_rating_repository.dart';
import '../../data/services/course_rating_api_client.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/info_confirm_dialog.dart';

class CourseRatingPage extends StatefulWidget {
  const CourseRatingPage({
    super.key,
    required this.repository,
  });

  final CourseRatingRepository repository;

  @override
  State<CourseRatingPage> createState() => _CourseRatingPageState();
}

class _CourseRatingPageState extends State<CourseRatingPage> {
  final _controller = TextEditingController();
  Future<CourseRatingSearchResult>? _searchFuture;
  String _activeQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程评价'),
        actions: [
          IconButton(
            tooltip: '说明',
            onPressed: _showInfo,
            icon: const Icon(Icons.info),
          ),
        ],
      ),
      body: Column(
        children: [
          _CourseRatingSearchBar(
            controller: _controller,
            onSearch: () => _submitSearch(),
          ),
          Expanded(child: _resultBody()),
        ],
      ),
    );
  }

  Widget _resultBody() {
    final future = _searchFuture;
    if (future == null) {
      return const EmptyState(
        icon: Icons.rate_review_outlined,
        title: '搜索课程或教师',
        message: '输入课程名、课程号或教师名后查看评价。',
      );
    }
    return FutureBuilder<CourseRatingSearchResult>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: '搜索失败',
            message: _friendlyError(snapshot.error!),
            action: TextButton.icon(
              onPressed: () => _submitSearch(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          );
        }
        final result = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () => _submitSearch(forceRefresh: true),
          child: _CourseRatingSearchResultList(
            result: result,
            query: _activeQuery,
            onOpenCourse: _openCourse,
            onOpenTeacher: _openTeacher,
          ),
        );
      },
    );
  }

  Future<void> _submitSearch({bool forceRefresh = false}) async {
    final query = widget.repository.normalizeKeyword(_controller.text);
    if (query.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入至少 2 个字或课程号')),
      );
      return;
    }
    final future = widget.repository.search(query, forceRefresh: forceRefresh);
    setState(() {
      _activeQuery = query;
      _searchFuture = future;
    });
    await future.then<void>((_) {}, onError: (_) {});
  }

  void _openCourse(CourseRatingCourse course) {
    Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => CourseRatingCourseTeachersPage(
          repository: widget.repository,
          course: course,
        ),
      ),
    );
  }

  void _openTeacher(CourseRatingTeacher teacher) {
    Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => CourseRatingTeacherCoursesPage(
          repository: widget.repository,
          teacher: teacher,
        ),
      ),
    );
  }

  Future<void> _showInfo() async {
    await showInfoConfirmDialog(
      context,
      title: '课程评价说明',
      message:
          '该功能由 https://course-rate.icu/ 提供。感谢学盟的付出！\n\n当前客户端仅支持浏览课程与教师评价，暂不能发表评价。\n\n如需评价课程，请访问网站注册登录后进行。\n\n再次感谢学盟的付出！',
    );
  }
}

class CourseRatingCourseTeachersPage extends StatefulWidget {
  const CourseRatingCourseTeachersPage({
    super.key,
    required this.repository,
    required this.course,
  });

  final CourseRatingRepository repository;
  final CourseRatingCourse course;

  @override
  State<CourseRatingCourseTeachersPage> createState() =>
      _CourseRatingCourseTeachersPageState();
}

class _CourseRatingCourseTeachersPageState
    extends State<CourseRatingCourseTeachersPage> {
  late Future<CourseRatingCourseTeachers> _future;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchCourseTeachers(widget.course);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<CourseRatingCourseTeachers>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CourseRatingErrorState(
              title: '教师列表加载失败',
              message: _friendlyError(snapshot.error!),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _CourseHeader(course: data.course),
                const SizedBox(height: 16),
                if (data.teachers.isEmpty)
                  const EmptyState(
                    icon: Icons.person_search_outlined,
                    title: '暂无教师记录',
                    message: '这个课程暂时没有可查看的授课教师。',
                  )
                else ...[
                  const _SectionHeader('授课教师'),
                  for (final teacher in data.teachers)
                    _TeacherTile(
                      teacher: teacher,
                      onTap: () => _openDetail(data.course, teacher),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
      _future = widget.repository.fetchCourseTeachers(
        widget.course,
        forceRefresh: true,
      );
    });
    await _future.then<void>((_) {}, onError: (_) {});
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  void _openDetail(CourseRatingCourse course, CourseRatingTeacher teacher) {
    Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => CourseRatingDetailPage(
          repository: widget.repository,
          course: course,
          teacher: teacher,
        ),
      ),
    );
  }
}

class CourseRatingTeacherCoursesPage extends StatefulWidget {
  const CourseRatingTeacherCoursesPage({
    super.key,
    required this.repository,
    required this.teacher,
  });

  final CourseRatingRepository repository;
  final CourseRatingTeacher teacher;

  @override
  State<CourseRatingTeacherCoursesPage> createState() =>
      _CourseRatingTeacherCoursesPageState();
}

class _CourseRatingTeacherCoursesPageState
    extends State<CourseRatingTeacherCoursesPage> {
  late Future<CourseRatingTeacherCourses> _future;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchTeacherCourses(widget.teacher);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.teacher.name),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<CourseRatingTeacherCourses>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CourseRatingErrorState(
              title: '课程列表加载失败',
              message: _friendlyError(snapshot.error!),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data!;
          final colors = context.lehuColors;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  data.teacher.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '选择课程查看这位老师的评价',
                  style: TextStyle(color: colors.textTertiary, fontSize: 14.5),
                ),
                const SizedBox(height: 16),
                if (data.courses.isEmpty)
                  const EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: '暂无课程记录',
                    message: '这个教师暂时没有可查看的课程评价。',
                  )
                else ...[
                  const _SectionHeader('关联课程'),
                  for (final course in data.courses)
                    _CourseTile(
                      course: course,
                      onTap: () => _openDetail(course, data.teacher),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
      _future = widget.repository.fetchTeacherCourses(
        widget.teacher,
        forceRefresh: true,
      );
    });
    await _future.then<void>((_) {}, onError: (_) {});
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  void _openDetail(CourseRatingCourse course, CourseRatingTeacher teacher) {
    Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => CourseRatingDetailPage(
          repository: widget.repository,
          course: course,
          teacher: teacher,
        ),
      ),
    );
  }
}

class CourseRatingDetailPage extends StatefulWidget {
  const CourseRatingDetailPage({
    super.key,
    required this.repository,
    required this.course,
    required this.teacher,
  });

  final CourseRatingRepository repository;
  final CourseRatingCourse course;
  final CourseRatingTeacher teacher;

  @override
  State<CourseRatingDetailPage> createState() => _CourseRatingDetailPageState();
}

class _CourseRatingDetailPageState extends State<CourseRatingDetailPage> {
  CourseRatingDetail? _detail;
  Object? _error;
  var _ratings = <CourseRatingItem>[];
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.teacher.name),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshing ? null : () => _loadFirstPage(force: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _CourseRatingErrorState(
        title: '评价加载失败',
        message: _friendlyError(error),
        onRetry: () => _loadFirstPage(force: true),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return const EmptyState(
        icon: Icons.rate_review_outlined,
        title: '暂无评价',
        message: '暂时没有可展示的课程评价。',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadFirstPage(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
          _RatingDetailHeader(detail: detail),
          const SizedBox(height: 18),
          if (_ratings.isEmpty)
            const EmptyState(
              icon: Icons.rate_review_outlined,
              title: '暂无评价',
              message: '这组课程与教师暂时还没有评价。',
            )
          else ...[
            const _SectionHeader('评价'),
            for (final rating in _ratings) _RatingTile(rating: rating),
          ],
          if (detail.hasMore || _loadingMore) ...[
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: const Text('加载更多'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadFirstPage({bool force = false}) async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
      _loading = _detail == null;
      _error = null;
    });
    try {
      final detail = await widget.repository.fetchRatingDetail(
        course: widget.course,
        teacher: widget.teacher,
        forceRefresh: force,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _ratings = detail.ratings;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final detail = _detail;
    if (detail == null || !detail.hasMore || _loadingMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final next = await widget.repository.fetchRatingDetail(
        course: detail.course,
        teacher: detail.teacher,
        page: detail.page + 1,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = next;
        _ratings = [..._ratings, ...next.ratings];
      });
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }
}

class _CourseRatingSearchBar extends StatelessWidget {
  const _CourseRatingSearchBar({
    required this.controller,
    required this.onSearch,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '课程名、课程号或教师名',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: onSearch,
              child: const Text('搜索'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseRatingSearchResultList extends StatelessWidget {
  const _CourseRatingSearchResultList({
    required this.result,
    required this.query,
    required this.onOpenCourse,
    required this.onOpenTeacher,
  });

  final CourseRatingSearchResult result;
  final String query;
  final ValueChanged<CourseRatingCourse> onOpenCourse;
  final ValueChanged<CourseRatingTeacher> onOpenTeacher;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    if (result.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 88),
          EmptyState(
            icon: Icons.search_off,
            title: '没有找到结果',
            message: '没有找到与“$query”相关的课程或教师。',
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          '搜索：$query',
          style: LehuTextStyles.title(
            color: colors.textPrimary,
            size: 16.5,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        if (result.courses.isNotEmpty) ...[
          const _SectionHeader('课程'),
          for (final course in result.courses)
            _CourseTile(
              course: course,
              onTap: () => onOpenCourse(course),
            ),
          const SizedBox(height: 18),
        ],
        if (result.teachers.isNotEmpty) ...[
          const _SectionHeader('教师'),
          for (final teacher in result.teachers)
            _TeacherTile(
              teacher: teacher,
              onTap: () => onOpenTeacher(teacher),
            ),
        ],
      ],
    );
  }
}

class _CourseHeader extends StatelessWidget {
  const _CourseHeader({required this.course});

  final CourseRatingCourse course;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          course.name,
          style: LehuTextStyles.title(
            color: colors.textPrimary,
            size: 19,
            weight: FontWeight.w600,
          ),
        ),
        if (course.displayCode.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            course.displayCode,
            style: TextStyle(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _RatingDetailHeader extends StatelessWidget {
  const _RatingDetailHeader({required this.detail});

  final CourseRatingDetail detail;

  @override
  Widget build(BuildContext context) {
    final radar = detail.radar;
    final colors = context.lehuColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CourseHeader(course: detail.course),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                detail.total == 0 ? '暂无评分' : '${_scoreText(detail.average)}/10',
                style: TextStyle(
                  color: colors.onAccentSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${detail.teacher.name} · ${detail.total} 条评价',
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
        if (radar.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0;
                  i < radar.categories.length && i < radar.values.length;
                  i++)
                _SoftLabel(
                  '${radar.categories[i]} ${_percentText(radar.values[i])}',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.course,
    required this.onTap,
  });

  final CourseRatingCourse course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pieces = <String>[
      if (course.displayCode.isNotEmpty) course.displayCode,
      if (course.count > 0) '${course.count} 条评价',
    ];
    return _PlainTile(
      icon: Icons.menu_book_outlined,
      title: course.name,
      subtitle: pieces.join(' · '),
      onTap: onTap,
    );
  }
}

class _TeacherTile extends StatelessWidget {
  const _TeacherTile({
    required this.teacher,
    required this.onTap,
  });

  final CourseRatingTeacher teacher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PlainTile(
      icon: Icons.person_outline,
      title: teacher.name,
      subtitle: '查看关联课程与评价',
      onTap: onTap,
    );
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile({required this.rating});

  final CourseRatingItem rating;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ScorePill(rating: rating),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rating.user.username.isEmpty ? '匿名' : rating.user.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.detailAuthor,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                _dateText(rating.createdAt),
                style: TextStyle(color: colors.textMuted, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            rating.content.isEmpty ? '未填写文字评价' : rating.content,
            style: TextStyle(
              color: rating.content.isEmpty
                  ? colors.textMuted
                  : colors.textPrimary,
              fontSize: 15.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (rating.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in rating.tags) _SoftLabel(tag.displayText),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PlainTile extends StatelessWidget {
  const _PlainTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.rating});

  final CourseRatingItem rating;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: rating.hasScore ? colors.accentSoft : colors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        rating.hasScore ? '${rating.score}/10' : '旧版',
        style: TextStyle(
          color: rating.hasScore ? colors.onAccentSoft : colors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _SoftLabel extends StatelessWidget {
  const _SoftLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: context.lehuColors.textPrimary,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CourseRatingErrorState extends StatelessWidget {
  const _CourseRatingErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: title,
      message: message,
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    );
  }
}

String _friendlyError(Object error) {
  if (error is CourseRatingRateLimitedException) {
    final retryAfter = error.retryAfter;
    if (retryAfter == null) {
      return error.message;
    }
    return '${error.message} 建议 ${retryAfter.inSeconds} 秒后再试。';
  }
  if (error is CourseRatingApiException) {
    return error.message;
  }
  return '课程评价站点暂时无法访问，请稍后重试。';
}

String _scoreText(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

String _percentText(double value) {
  final percent = (value * 100).round();
  return '$percent%';
}

String _dateText(DateTime? date) {
  if (date == null) {
    return '';
  }
  final now = DateTime.now();
  if (date.year == now.year) {
    return '${date.month}/${date.day}';
  }
  return '${date.year}/${date.month}/${date.day}';
}
