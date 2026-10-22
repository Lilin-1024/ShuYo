import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/campus_card.dart';
import '../../data/services/campus_card_service.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/theme/shuyo_theme.dart';
import 'campus_card_date_range_sheet.dart';

class CampusCardPage extends StatefulWidget {
  const CampusCardPage({super.key, required this.onLogin});

  final Future<bool> Function() onLogin;

  @override
  State<CampusCardPage> createState() => _CampusCardPageState();
}

class _CampusCardPageState extends State<CampusCardPage> {
  final _service = CampusCardService();
  late DateTimeRange _range;
  int? _presetDays = 7;
  CampusCardInfo? _card;
  List<CampusCardBill>? _bills;
  Object? _cardError;
  Object? _billsError;
  DateTime? _cardQueriedAt;
  bool _loadingCard = true;
  bool _loadingBills = true;
  bool _loggingIn = false;
  int _billsRevision = 0;

  @override
  void initState() {
    super.initState();
    _range = _recentDays(7);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  DateTimeRange _recentDays(int days) {
    final today = DateUtils.dateOnly(DateTime.now());
    return DateTimeRange(
      start: DateTime(today.year, today.month, today.day - days + 1),
      end: today,
    );
  }

  Future<void> _refresh() async {
    await Future.wait([_loadCard(), _loadBills()]);
  }

  Future<void> _loadCard() async {
    setState(() {
      _loadingCard = true;
      _card = null;
      _cardError = null;
      _cardQueriedAt = null;
    });
    try {
      final card = await _service.fetchCardInfo();
      if (!mounted) return;
      setState(() {
        _card = card;
        _cardQueriedAt = DateTime.now();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _cardError = error);
    } finally {
      if (mounted) setState(() => _loadingCard = false);
    }
  }

  Future<void> _loadBills() async {
    final revision = ++_billsRevision;
    final range = _range;
    setState(() {
      _loadingBills = true;
      _bills = null;
      _billsError = null;
    });
    try {
      final bills = await _service.fetchBills(
        startDate: range.start,
        endDate: range.end,
      );
      if (!mounted || revision != _billsRevision) return;
      setState(() => _bills = bills);
    } on Object catch (error) {
      if (mounted && revision == _billsRevision) {
        setState(() => _billsError = error);
      }
    } finally {
      if (mounted && revision == _billsRevision) {
        setState(() => _loadingBills = false);
      }
    }
  }

  Future<void> _login() async {
    if (_loggingIn) return;
    setState(() => _loggingIn = true);
    try {
      if (await widget.onLogin() && mounted) await _refresh();
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _selectRecentDays(int days) {
    setState(() {
      _presetDays = days;
      _range = _recentDays(days);
    });
    unawaited(_loadBills());
  }

  Future<void> _selectRange() async {
    final range =
        await showCampusCardDateRangeSheet(context, initialRange: _range);
    if (range == null || !mounted) return;
    setState(() {
      _presetDays = null;
      _range = range;
    });
    await _loadBills();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园卡'),
        actions: [
          IconButton(
            tooltip: '刷新余额和消费记录',
            onPressed:
                _loadingCard || _loadingBills || _loggingIn ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            if (!_loadingCard && !_loadingBills && !_loggingIn) {
              await _refresh();
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverList.list(children: [
                  _cardSection(),
                  const SizedBox(height: 12),
                  Text(
                    '数据由学校信息门户提供，可能存在同步延迟。',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Semantics(
                    header: true,
                    child: Text(
                      '消费记录',
                      style: ShuYoTextStyles.sectionTitle(
                          color: colors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('近 7 天'),
                        selected: _presetDays == 7,
                        onSelected: _loadingBills || _loggingIn
                            ? null
                            : (_) => _selectRecentDays(7),
                      ),
                      ChoiceChip(
                        label: const Text('近 30 天'),
                        selected: _presetDays == 30,
                        onSelected: _loadingBills || _loggingIn
                            ? null
                            : (_) => _selectRecentDays(30),
                      ),
                      ChoiceChip(
                        label: const Text('自选日期'),
                        selected: _presetDays == null,
                        onSelected: _loadingBills || _loggingIn
                            ? null
                            : (_) => _selectRange(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_date(_range.start)} 至 ${_date(_range.end)}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_loadingBills)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          semanticsLabel: '正在查询消费记录',
                        ),
                      ),
                    )
                  else if (_billsError != null)
                    _errorSection(_billsError!, onRetry: _loadBills)
                  else if (_bills?.isEmpty == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        '所选日期内暂无消费记录，可切换日期查询。',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    )
                  else
                    Text(
                      '共 ${_bills?.length ?? 0} 条',
                      style:
                          TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                ]),
              ),
              if (!_loadingBills && _billsError == null && _bills != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  sliver: SliverList.builder(
                    itemCount: _bills!.length,
                    itemBuilder: (context, index) => _billRow(_bills![index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardSection() {
    final colors = context.shuyoColors;
    final card = _card;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    '校园卡余额',
                    style: ShuYoTextStyles.label(color: colors.textSecondary),
                  ),
                ),
                if (!_loadingCard &&
                    _cardError == null &&
                    card != null &&
                    card.status.isNotEmpty)
                  Semantics(
                    label: '卡片状态：${card.status}',
                    excludeSemantics: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        child: Text(
                          card.status,
                          style:
                              ShuYoTextStyles.meta(color: colors.textSecondary),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingCard)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  semanticsLabel: '正在查询校园卡余额',
                ),
              ),
            )
          else if (_cardError != null)
            _errorSection(_cardError!, onRetry: _loadCard)
          else if (card != null) ...[
            Semantics(
              label: '${card.balance.toStringAsFixed(2)} 元',
              excludeSemantics: true,
              child: Text(
                '¥ ${card.balance.toStringAsFixed(2)}',
                style: ShuYoTextStyles.title(
                  color: colors.textPrimary,
                  size: 36,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (card.name.isNotEmpty) ...[
              Text(
                card.name,
                style: ShuYoTextStyles.title(
                    color: colors.textPrimary,
                    size: 15,
                    weight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              '学号 ${card.studentId}',
              style:
                  ShuYoTextStyles.meta(color: colors.textSecondary, size: 13),
            ),
            if (card.validUntil.isNotEmpty || _cardQueriedAt != null) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  if (card.validUntil.isNotEmpty)
                    _cardMetadata('有效期', card.validUntil),
                  if (_cardQueriedAt != null)
                    _cardMetadata('查询时间', _time(_cardQueriedAt!)),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _cardMetadata(String label, String value) {
    final colors = context.shuyoColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ShuYoTextStyles.meta(color: colors.textTertiary)),
        const SizedBox(height: 4),
        Text(value, style: ShuYoTextStyles.meta(color: colors.textSecondary)),
      ],
    );
  }

  Widget _billRow(CampusCardBill bill) {
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 20,
              runSpacing: 8,
              children: [
                Text(bill.name,
                    style: ShuYoTextStyles.title(
                        color: colors.textPrimary,
                        size: 15,
                        weight: FontWeight.w600)),
                Text('¥ ${bill.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(bill.payTime,
              style: TextStyle(color: colors.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _errorSection(Object error,
      {required Future<void> Function() onRetry}) {
    final authRequired = error is CampusCardAuthRequiredException ||
        error is CampusCardException && error.code == 'accountMismatch';
    final message =
        error is CampusCardException ? error.message : '查询失败，请检查网络后重试。';
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message,
              style: TextStyle(color: context.shuyoColors.textSecondary)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loggingIn
                ? null
                : authRequired
                    ? _login
                    : onRetry,
            icon: Icon(authRequired ? Icons.login : Icons.refresh),
            label: Text(_loggingIn
                ? '正在登录…'
                : authRequired
                    ? '登录校园卡服务'
                    : '重试'),
          ),
        ],
      ),
    );
  }

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
