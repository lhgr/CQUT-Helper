import 'auth/auth_api.dart';
import 'course/course_api.dart';
import 'user/user_api.dart';
import 'update/update_api.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  late final AuthApi auth;
  late final CourseApi course;
  late final UserApi user;
  late final UpdateApi update;

  factory ApiService() => _instance;

  ApiService._internal() {
    auth = AuthApi();
    course = CourseApi();
    user = UserApi();
    update = UpdateApi();
  }
}
