import 'dart:async';

import 'package:cqut_helper/manager/exam_repository.dart';
import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showExamDetails(BuildContext context, ExamRecord exam) {
  final media = MediaQuery.of(context);
  final availableHeight =
      media.size.height -
      media.padding.top -
      media.padding.bottom -
      media.viewInsets.bottom;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: 640,
      maxHeight: availableHeight.clamp(0.0, double.infinity) * 0.8,
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: media.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '考试详情',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    exam.courseName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  Text('考试时间', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Text(exam.timeText.trim().isEmpty ? '待公布' : exam.timeText),
                  const SizedBox(height: 20),
                  Text('考试地点', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Text(exam.location.isEmpty ? '待公布' : exam.location),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key, this.repository, this.initialExamKey});
  final ExamRepository? repository;
  final String? initialExamKey;
  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends State<ExamsPage> with WidgetsBindingObserver {
  late final ExamRepository _repository =
      widget.repository ?? ExamRepository.instance;
  bool _loading = true;
  bool _openedInitial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.isCurrentOf(context) ?? false)) {
      unawaited(_repository.refresh());
    }
  }

  Future<void> _load() async {
    await _repository.load();
    if (!mounted) return;
    if (_repository.snapshot != null) {
      setState(() => _loading = false);
      _openInitial();
    }
    await _repository.refresh();
    if (!mounted) return;
    setState(() => _loading = false);
    _openInitial();
  }

  void _openInitial() {
    if (_openedInitial || widget.initialExamKey == null) return;
    final matches = _repository.exams.where(
      (exam) => exam.key == widget.initialExamKey,
    );
    if (matches.isEmpty) return;
    _openedInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showExamDetails(context, matches.first);
    });
  }

  Future<void> _refresh() async {
    if (_repository.requiresReauthentication) {
      if (!await requestReauthentication(context) || !mounted) return;
    }
    await _repository.refresh(force: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('考试安排')),
    body: ListenableBuilder(
      listenable: _repository,
      builder: (context, _) {
        if (_loading) return const Center(child: CircularProgressIndicator());
        final exams = [..._repository.exams]
          ..sort((a, b) {
            if (a.startAt == null) {
              return b.startAt == null
                  ? a.courseName.compareTo(b.courseName)
                  : 1;
            }
            if (b.startAt == null) return -1;
            return a.startAt!.compareTo(b.startAt!);
          });
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (_repository.refreshing) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              if (_repository.error != null) ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _repository.requiresReauthentication
                              ? '请重新登录后更新考试安排'
                              : '考试更新失败，请检查网络后重试',
                        ),
                        if (_repository.snapshot != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '正在显示已保存的考试安排',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _repository.refreshing ? null : _refresh,
                            child: Text(
                              _repository.requiresReauthentication
                                  ? '重新登录'
                                  : '重试',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_repository.snapshot != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '更新于 ${_time(_repository.snapshot!.fetchedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (exams.isEmpty &&
                  !_repository.refreshing &&
                  _repository.error == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('暂无考试安排')),
                ),
              for (final exam in exams) ...[
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => showExamDetails(context, exam),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            exam.courseName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            exam.timeText.trim().isEmpty
                                ? '考试时间待公布'
                                : exam.timeText,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            exam.location.isEmpty ? '考试地点待公布' : exam.location,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    ),
  );

  String _time(DateTime value) {
    final date = value.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
