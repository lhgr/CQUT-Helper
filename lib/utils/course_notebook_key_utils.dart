String normalizeCourseName(String? rawName) {
  final name = (rawName ?? '').trim();
  if (name.isEmpty) {
    return '未命名课程';
  }
  return name;
}

String buildCourseNotebookKey({
  required String courseName,
  String? yearTerm,
}) {
  final safeName = normalizeCourseName(courseName);
  final safeTerm = (yearTerm ?? '').trim();
  if (safeTerm.isEmpty) {
    return safeName;
  }
  return '$safeTerm|$safeName';
}
