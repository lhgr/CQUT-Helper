import 'dart:async';

import 'package:cqut_helper/manager/daily_quote_manager.dart';
import 'package:flutter/material.dart';

class DailyQuoteCard extends StatefulWidget {
  final bool active;
  final int refreshToken;
  final DailyQuoteManager? manager;

  const DailyQuoteCard({
    super.key,
    this.active = true,
    this.refreshToken = 0,
    this.manager,
  });

  @override
  State<DailyQuoteCard> createState() => _DailyQuoteCardState();
}

class _DailyQuoteCardState extends State<DailyQuoteCard>
    with WidgetsBindingObserver {
  DailyQuotePresentation? _presentation;
  bool _switching = false;
  int _loadGeneration = 0;
  Timer? _boundaryTimer;

  DailyQuoteManager get _manager =>
      widget.manager ?? DailyQuoteManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant DailyQuoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken && widget.active) {
      _load(forceRefresh: true);
    } else if (!oldWidget.active && widget.active) {
      _load();
    } else if (oldWidget.active && !widget.active) {
      _loadGeneration++;
      _boundaryTimer?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      _load();
    } else if (state != AppLifecycleState.resumed) {
      _loadGeneration++;
      _boundaryTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _boundaryTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    if (!forceRefresh) {
      final cached = await _manager.loadCached();
      if (mounted && generation == _loadGeneration && cached != null) {
        setState(() => _presentation = cached);
        _scheduleBoundary(cached.config.nextRefreshAt);
      }
    }

    try {
      final refreshed = await _manager.refresh(force: forceRefresh);
      if (!mounted || generation != _loadGeneration || !widget.active) return;
      setState(() => _presentation = refreshed);
      _scheduleBoundary(
        refreshed?.config.nextRefreshAt ?? await _manager.cachedNextRefreshAt(),
      );
    } catch (_) {
      // 一言是装饰性内容，网络失败时保留缓存或保持隐藏。
    }
  }

  void _scheduleBoundary(DateTime? configuredBoundary) {
    _boundaryTimer?.cancel();
    if (!mounted || !widget.active) return;
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    var boundary = nextMidnight;
    if (configuredBoundary != null &&
        configuredBoundary.toUtc().isAfter(now.toUtc()) &&
        configuredBoundary.toUtc().isBefore(nextMidnight.toUtc())) {
      boundary = configuredBoundary;
    }
    final delay = boundary.toUtc().difference(now.toUtc());
    if (delay <= Duration.zero) return;
    _boundaryTimer = Timer(delay, () {
      if (mounted && widget.active) _load(forceRefresh: true);
    });
  }

  Future<void> _showNext() async {
    final presentation = _presentation;
    if (presentation == null || presentation.queue.length < 2 || _switching) {
      return;
    }
    setState(() => _switching = true);
    try {
      final next = await _manager.selectNext(presentation);
      if (mounted) setState(() => _presentation = next);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;
    if (presentation == null) return const SizedBox.shrink();

    final quote = presentation.current;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 72),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.outlineVariant.withAlpha(150)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.format_quote_rounded,
                    color: colors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '一言',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (presentation.queue.length > 1)
                    TextButton.icon(
                      onPressed: _switching ? null : _showNext,
                      icon: const Icon(Icons.autorenew_rounded, size: 18),
                      label: const Text('换一句'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Semantics(
                    key: ValueKey('${quote.id}:${quote.updatedAt ?? ''}'),
                    label: quote.source == null
                        ? quote.text
                        : '${quote.text}，${quote.source}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          quote.text,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            height: 1.55,
                            color: colors.onSurface,
                          ),
                        ),
                        if (quote.source != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '—— ${quote.source}',
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
