import 'package:cqut_helper/api/auth/auth_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/onboarding_manager.dart';
import 'package:cqut_helper/pages/Login/ForgetPassword.dart';
import 'package:cqut_helper/utils/diagnostic_operation.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  final bool reauthenticate;
  final AuthApi? authApi;

  const LoginPage({super.key, this.reauthenticate = false, this.authApi});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _accountFocus = FocusNode();
  final _passwordFocus = FocusNode();
  String? _loginError;

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _savedEncryptedPassword;
  String? _savedAccount;

  late final AuthApi _authApi;
  final CredentialStore _credentialStore = CredentialStore();

  @override
  void initState() {
    super.initState();
    _authApi = widget.authApi ?? AuthApi();
    _loadSavedCredentials();
    _accountController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _accountFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final account = prefs.getString('account');
    final encryptedPwd = await _credentialStore.readEncryptedPassword();

    if (account != null && account.isNotEmpty) {
      if (mounted) {
        setState(() {
          if (_accountController.text.isEmpty) {
            _accountController.text = account;
          }
          _savedAccount = account;
          _savedEncryptedPassword = widget.reauthenticate ? null : encryptedPwd;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    final account = _accountController.text.trim();
    final password = _passwordController.text;

    if (_formKey.currentState?.validate() != true) {
      (account.isEmpty ? _accountFocus : _passwordFocus).requestFocus();
      return;
    }

    final useSavedPassword = password.isEmpty && _canUseSavedPassword;
    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    try {
      await runDiagnosticOperation('Login', 'sign_in', () async {
        await _authApi.resetLoginContext();
        if (useSavedPassword) {
          await _authApi.loginWithEncrypted(
            account: account,
            encryptedPassword: _savedEncryptedPassword!,
          );
        } else {
          await _authApi.login(account: account, password: password);
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('account', account);
        await WidgetUpdater.updateTodayWidget(trigger: 'login');
        await prefs.setInt(
          'schedule_notice_login_marker_$account',
          DateTime.now().millisecondsSinceEpoch,
        );
        if (useSavedPassword) {
          await _credentialStore.writeEncryptedPassword(
            _savedEncryptedPassword!,
          );
        } else {
          final encrypted = _authApi.encryptPassword(password);
          await _credentialStore.writeEncryptedPassword(encrypted);
        }

        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('登录成功')));
          if (widget.reauthenticate) {
            Navigator.of(context).pop(true);
          } else {
            Navigator.of(context).pushReplacementNamed('/');
          }
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loginError = _loginErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _canUseSavedPassword =>
      _savedEncryptedPassword?.isNotEmpty == true &&
      _accountController.text.trim() == _savedAccount;

  String _loginErrorMessage(Object error) {
    if (error is DioException) return '登录请求未能完成，请检查网络后重试';
    if (error is FormatException) return '登录服务响应异常，请稍后重试';
    if (error is PlatformException) return '登录暂时不可用，请稍后重试';

    if (error is Exception) {
      final rawMessage = error.toString();
      if (!rawMessage.startsWith('Exception: ')) {
        return '登录暂时无法完成，请稍后重试';
      }
      final message = rawMessage.substring('Exception: '.length).trim();
      const technicalMessages = {
        '登录失败：登录接口返回格式异常',
        'Login failed at step 1',
        'Login failed at step 2',
        '响应格式异常',
        'Password or encryptedPassword must be provided',
      };
      if (technicalMessages.contains(message) || message.isEmpty) {
        return '登录暂时无法完成，请稍后重试';
      }
      return message;
    }
    return '登录暂时无法完成，请稍后重试';
  }

  @override
  Widget build(BuildContext context) {
    final showSavedPasswordHint =
        _savedEncryptedPassword != null &&
        _savedEncryptedPassword!.isNotEmpty &&
        _accountController.text == _savedAccount;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 32).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'lib/assets/Icon.png',
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              color: colorScheme.primary,
                              colorBlendMode: BlendMode.srcIn,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'CQUT Helper',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 24),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  widget.reauthenticate ? '重新验证身份' : '统一身份认证',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.reauthenticate
                                      ? '登录状态已失效，请重新输入密码；本地课表与个性化设置会保留'
                                      : '使用学校统一身份认证账号登录',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (OnboardingManager.instance.isNewUser) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '登录后自动同步课表，已同步的课程可离线查看。',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _accountController,
                                  focusNode: _accountFocus,
                                  enabled: !_isLoading,
                                  validator: (value) =>
                                      value?.trim().isNotEmpty == true
                                      ? null
                                      : '请输入账号',
                                  onChanged: (_) =>
                                      setState(() => _loginError = null),
                                  autofillHints: const [AutofillHints.username],
                                  decoration: const InputDecoration(
                                    labelText: '账号',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocus,
                                  enabled: !_isLoading,
                                  validator: (value) =>
                                      value?.isNotEmpty == true ||
                                          _canUseSavedPassword
                                      ? null
                                      : '请输入密码',
                                  onChanged: (_) =>
                                      setState(() => _loginError = null),
                                  autofillHints: const [AutofillHints.password],
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: '密码',
                                    hintText: showSavedPasswordHint
                                        ? '已保存密码，可直接登录'
                                        : '请输入密码',
                                    hintStyle: showSavedPasswordHint
                                        ? TextStyle(color: colorScheme.primary)
                                        : null,
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? '显示密码'
                                          : '隐藏密码',
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                  ),
                                  onFieldSubmitted: (_) => _handleLogin(),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const ForgetPasswordPage(),
                                              ),
                                            );
                                          },
                                    child: const Text('忘记密码？'),
                                  ),
                                ),
                                if (_loginError != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _loginError!,
                                    style: TextStyle(color: colorScheme.error),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  icon: _isLoading
                                      ? SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: colorScheme.onPrimary,
                                          ),
                                        )
                                      : const Icon(Icons.login_rounded),
                                  label: Text(
                                    _isLoading
                                        ? '正在验证'
                                        : widget.reauthenticate
                                        ? '重新验证'
                                        : '登录',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> requestReauthentication(BuildContext context) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => const LoginPage(reauthenticate: true),
    ),
  );
  return result == true;
}
