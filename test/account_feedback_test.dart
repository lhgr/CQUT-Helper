import 'dart:async';

import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/api/auth/auth_api.dart';
import 'package:cqut_helper/api/auth/forget_password_api.dart';
import 'package:cqut_helper/manager/cache_cleanup_manager.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/pages/Login/ForgetPassword.dart';
import 'package:cqut_helper/pages/Mine/Mine.dart';
import 'package:cqut_helper/pages/Mine/mine_user_info_card.dart';
import 'package:cqut_helper/pages/Mine/mine_user_info_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthApi {
  final pending = Completer<void>();
  int requests = 0;
  @override
  Future<void> resetLoginContext({String? account}) async {}
  @override
  Future<void> login({required String account, required String password}) {
    requests++;
    return pending.future;
  }
}

class _Recovery extends ForgetPasswordApi {
  final phones = <String>[];
  final tickets = <String>[];
  String? failure;
  int resets = 0;
  @override
  Future<String> sendAuthCode({required String mobilePhone}) async {
    phones.add(mobilePhone);
    if (failure != null) throw Exception(failure);
    return 'ticket-${phones.length}';
  }

  @override
  Future<void> checkAuthCode({
    required String ticket,
    required String authCode,
  }) async {
    tickets.add(ticket);
  }

  @override
  Future<void> setNewPassword({
    required String ticket,
    required String password,
  }) async {
    resets++;
  }
}

MineUserInfoLoadResult _user(String name) => MineUserInfoLoadResult(
  userId: 'student',
  userInfo: {'username': 'student', 'userRealName': name},
);

class _Profiles extends MineUserInfoLoader {
  _Profiles() : super(ApiService());
  final responses = <Future<MineUserInfoLoadResult> Function()>[];
  int requests = 0;
  @override
  Future<MineUserInfoLoadResult> load({bool forceRefresh = false}) {
    requests++;
    return responses.removeAt(0)();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null);
  });
  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  Finder input(String label) =>
      find.descendant(of: field(label), matching: find.byType(TextField));

  testWidgets('登录校验持续显示在字段旁并聚焦首个错误', (tester) async {
    await pump(tester, const LoginPage());
    await tap(tester, '登录');
    expect(find.text('请输入账号'), findsOneWidget);
    expect(tester.widget<TextField>(input('账号')).focusNode!.hasFocus, isTrue);
    await tester.enterText(field('账号'), 'student');
    await tap(tester, '登录');
    expect(tester.widget<TextField>(input('密码')).focusNode!.hasFocus, isTrue);
    expect(find.text('请输入密码'), findsWidgets);
  });

  testWidgets('键盘与按钮共用登录防重入且失败保留输入与可见错误', (tester) async {
    final auth = _Auth();
    await pump(tester, LoginPage(authApi: auth));
    await tester.enterText(field('账号'), 'student');
    await tester.enterText(field('密码'), 'secret');
    final submit = tester.widget<TextField>(input('密码')).onSubmitted!;
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '登录'))
        .onPressed!;
    submit('secret');
    button();
    await tester.pump();
    expect(auth.requests, 1);
    auth.pending.completeError(Exception('学校认证暂时繁忙'));
    await tester.pumpAndSettle();
    expect(find.text('学校认证暂时繁忙'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(field('账号')).controller!.text,
      'student',
    );
    expect(
      tester.widget<TextFormField>(field('密码')).controller!.text,
      'secret',
    );
  });

  testWidgets('重发失败保留验证码阶段和旧ticket，成功重发换ticket并清空旧验证码', (tester) async {
    final api = _Recovery();
    await pump(tester, ForgetPasswordPage(api: api));
    await tester.enterText(field('手机号'), '13800138000');
    await tap(tester, '发送验证码');
    await tester.enterText(field('验证码'), '123456');
    expect(
      tester.widget<TextField>(input('验证码')).autofillHints,
      contains(AutofillHints.oneTimeCode),
    );
    api.failure = '发送过于频繁，请稍后重试';
    await tap(tester, '重新发送验证码');
    expect(find.text('发送过于频繁，请稍后重试'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(field('验证码')).controller!.text,
      '123456',
    );
    await tap(tester, '验证验证码');
    expect(api.tickets, ['ticket-1']);
    await tap(tester, '返回');
    api.failure = null;
    await tap(tester, '重新发送验证码');
    expect(
      tester.widget<TextFormField>(field('验证码')).controller!.text,
      isEmpty,
    );
    await tester.enterText(field('验证码'), '654321');
    await tap(tester, '验证验证码');
    expect(api.tickets.last, 'ticket-3');
  });

  testWidgets('修改手机号重启验证，新密码不一致显示字段错误和显隐语义', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Recovery();
    await pump(tester, ForgetPasswordPage(api: api), scale: 2);
    await tester.enterText(field('手机号'), '13800138000');
    await tap(tester, '发送验证码');
    final modify = find.widgetWithText(OutlinedButton, '修改手机号');
    final verify = find.widgetWithText(FilledButton, '验证验证码');
    expect(
      tester.getTopLeft(modify).dy,
      greaterThan(tester.getBottomLeft(verify).dy),
    );
    expect(tester.getSize(verify).width, greaterThan(250));
    for (final number in ['1', '2', '3']) {
      final text = find.text(number);
      final circle = find
          .ancestor(of: text, matching: find.byType(Container))
          .first;
      expect(
        tester.getSize(circle).height,
        greaterThan(tester.getSize(text).height),
      );
    }
    await tester.enterText(field('验证码'), '123456');
    await tap(tester, '修改手机号');
    await tester.enterText(field('手机号'), '13900139000');
    await tap(tester, '发送验证码');
    expect(api.phones, ['13800138000', '13900139000']);
    expect(
      tester.widget<TextFormField>(field('验证码')).controller!.text,
      isEmpty,
    );
    await tester.enterText(field('验证码'), '123456');
    await tap(tester, '验证验证码');
    expect(api.tickets, ['ticket-2']);
    await tester.enterText(field('新密码'), 'Abc12345');
    await tester.enterText(field('确认新密码'), 'Abc12346');
    await tap(tester, '重置密码');
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(
      tester.widget<TextField>(input('确认新密码')).focusNode!.hasFocus,
      isTrue,
    );
    expect(find.byTooltip('显示新密码'), findsOneWidget);
    expect(find.byTooltip('显示确认密码'), findsOneWidget);
    expect(api.resets, 0);
  });

  testWidgets('缓存资料刷新失败可重试，刷新期间保留资料并防重入', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<MineUserInfoLoadResult>();
    final profiles = _Profiles()
      ..responses.addAll([
        () async => _user('缓存同学'),
        () async => throw Exception('network unavailable'),
        () => pending.future,
      ]);
    await pump(tester, MineView(userInfoLoader: profiles), scale: 2);
    final initial = find.text('缓');
    final avatar = find
        .ancestor(of: initial, matching: find.byType(Container))
        .first;
    expect(
      tester.getRect(avatar).contains(tester.getRect(initial).topLeft),
      isTrue,
    );
    expect(
      tester.getRect(avatar).contains(tester.getRect(initial).bottomRight),
      isTrue,
    );
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('缓存同学'), findsOneWidget);
    expect(find.text('正在显示已保存的个人信息'), findsOneWidget);
    final feedback = find
        .ancestor(of: find.text('个人信息更新失败，请重试'), matching: find.byType(Card))
        .first;
    expect(
      tester.getTopLeft(feedback).dy -
          tester.getBottomLeft(find.byType(MineUserInfoCard)).dy,
      greaterThanOrEqualTo(12),
    );
    final retry = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '重试'))
        .onPressed!;
    retry();
    retry();
    await tester.pump();
    expect(profiles.requests, 3);
    expect(find.text('缓存同学'), findsOneWidget);
    pending.complete(_user('更新同学'));
    await tester.pumpAndSettle();
    expect(find.text('更新同学'), findsOneWidget);
    expect(find.text('正在显示已保存的个人信息'), findsNothing);
  });

  testWidgets('缓存资料凭证失效进入重新登录并在取消后保留资料', (tester) async {
    final profiles = _Profiles()
      ..responses.addAll([
        () async => _user('缓存同学'),
        () async => throw Exception('401 credential expired'),
      ]);
    await pump(tester, MineView(userInfoLoader: profiles));
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    await tap(tester, '重新登录');
    expect(
      tester.widget<LoginPage>(find.byType(LoginPage)).reauthenticate,
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // The retry button sits below the profile card; scroll back before checking
    // that the cached profile is still shown.
    await tester.scrollUntilVisible(find.text('缓存同学'), -200);
    expect(find.text('缓存同学'), findsOneWidget);
    expect(profiles.requests, 2);
  });

  testWidgets('清理资料缓存启动新读取，旧刷新迟到不能覆盖新资料', (tester) async {
    final old = Completer<MineUserInfoLoadResult>();
    final fresh = Completer<MineUserInfoLoadResult>();
    final profiles = _Profiles()
      ..responses.addAll([
        () async => _user('原同学'),
        () => old.future,
        () => fresh.future,
      ]);
    await pump(tester, MineView(userInfoLoader: profiles));
    unawaited(
      tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh(),
    );
    await tester.pump();
    CacheCleanupManager.userInfoCacheEpoch.value++;
    await tester.pump();
    expect(profiles.requests, 3);
    fresh.complete(_user('新同学'));
    await tester.pumpAndSettle();
    old.complete(_user('过期资料'));
    await tester.pumpAndSettle();
    expect(find.text('新同学'), findsOneWidget);
    expect(find.text('过期资料'), findsNothing);
  });
}
