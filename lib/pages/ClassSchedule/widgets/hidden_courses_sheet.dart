import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:flutter/material.dart';

class HiddenCoursesSheet extends StatefulWidget {
  final String userId;
  final String yearTerm;
  final Future<List<HiddenCourseInfo>> Function()? loadCourses;
  final Future<void> Function(HiddenCourseInfo course)? onRestore;

  const HiddenCoursesSheet({
    super.key,
    required this.userId,
    required this.yearTerm,
    this.loadCourses,
    this.onRestore,
  });

  @override
  State<HiddenCoursesSheet> createState() => _HiddenCoursesSheetState();
}

class _HiddenCoursesSheetState extends State<HiddenCoursesSheet> {
  late Future<List<HiddenCourseInfo>> _courses;
  final Set<String> _restoring = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _courses =
        widget.loadCourses?.call() ??
        ScheduleCustomizationManager.instance.hiddenCourses(
          userId: widget.userId,
          yearTerm: widget.yearTerm,
        );
  }

  Future<void> _restore(HiddenCourseInfo course) async {
    final key = course.preference.courseKey;
    if (_restoring.contains(key)) return;
    setState(() => _restoring.add(key));
    try {
      final callback = widget.onRestore;
      if (callback != null) {
        await callback(course);
      } else {
        await ScheduleCustomizationManager.instance.saveCoursePreference(
          course.preference.copyWith(hidden: false, updatedAt: DateTime.now()),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已恢复“${course.displayName}”'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('恢复失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _restoring.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已隐藏课程',
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
              child: FutureBuilder<List<HiddenCourseInfo>>(
                future: _courses,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('读取隐藏课程失败：${snapshot.error}'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => setState(_reload),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final courses = snapshot.data ?? const <HiddenCourseInfo>[];
                  if (courses.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('暂无隐藏课程'),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: courses.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final course = courses[index];
                      final restoring = _restoring.contains(
                        course.preference.courseKey,
                      );
                      final details = [
                        if (course.teacher.isNotEmpty) course.teacher,
                        if (course.location.isNotEmpty) course.location,
                      ].join(' · ');
                      return ListTile(
                        leading: const Icon(Icons.visibility_off_outlined),
                        title: Text(course.displayName),
                        subtitle: details.isEmpty ? null : Text(details),
                        trailing: TextButton(
                          onPressed: restoring ? null : () => _restore(course),
                          child: Text(restoring ? '恢复中' : '取消隐藏'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showHiddenCoursesSheet(
  BuildContext context, {
  required String userId,
  required String yearTerm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => HiddenCoursesSheet(userId: userId, yearTerm: yearTerm),
  );
}
