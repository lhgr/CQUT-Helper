import 'package:cqut/utils/course_notebook_key_utils.dart';
import 'package:flutter/material.dart';

class CourseOverviewItem {
  final String courseName;
  final String? teacher;
  final String? address;
  final String timeText;

  const CourseOverviewItem({
    required this.courseName,
    required this.timeText,
    this.teacher,
    this.address,
  });
}

class CourseOverviewPage extends StatelessWidget {
  final String? yearTerm;
  final List<CourseOverviewItem> courses;
  final ValueChanged<CourseOverviewItem> onTapCourse;

  const CourseOverviewPage({
    super.key,
    this.yearTerm,
    required this.courses,
    required this.onTapCourse,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          yearTerm?.trim().isNotEmpty == true ? '$yearTerm学期课程' : '本学期课程',
        ),
      ),
      body: courses.isEmpty
          ? Center(
              child: Text(
                '暂无课程数据',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final item = courses[index];
                return Card(
                  child: ListTile(
                    title: Text(
                      normalizeCourseName(item.courseName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        item.timeText,
                        if ((item.address ?? '').trim().isNotEmpty)
                          '教室：${item.address!.trim()}',
                        if ((item.teacher ?? '').trim().isNotEmpty)
                          '教师：${item.teacher!.trim()}',
                      ].join('\n'),
                      softWrap: true,
                    ),
                    trailing: const Icon(Icons.menu_book_outlined),
                    onTap: () => onTapCourse(item),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: courses.length,
            ),
    );
  }
}
