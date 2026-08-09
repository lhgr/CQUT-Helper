import 'package:cqut_helper/api/auth/auth_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/pages/Login/ForgetPassword.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _savedEncryptedPassword;
  String? _savedAccount;

  final AuthApi _authApi = AuthApi();
  final CredentialStore _credentialStore = CredentialStore();

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _accountController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final account = prefs.getString('account');
    final encryptedPwd = await _credentialStore.readEncryptedPassword();

    if (account != null && account.isNotEmpty) {
      if (mounted) {
        setState(() {
          _accountController.text = account;
          _savedAccount = account;
          _savedEncryptedPassword = encryptedPwd;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;

    if (account.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请输入账号')));
      return;
    }

    bool useSavedPassword = false;
    if (password.isEmpty) {
      if (_savedEncryptedPassword != null &&
          _savedEncryptedPassword!.isNotEmpty &&
          account == _savedAccount) {
        useSavedPassword = true;
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('请输入密码')));
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
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
      await prefs.setInt(
        'schedule_notice_login_marker_$account',
        DateTime.now().millisecondsSinceEpoch,
      );
      if (useSavedPassword) {
        await _credentialStore.writeEncryptedPassword(_savedEncryptedPassword!);
      } else {
        final encrypted = _authApi.encryptPassword(password);
        await _credentialStore.writeEncryptedPassword(encrypted);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('登录成功')));
        Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        // 如果存在 "Exception: " 前缀，则移除
        if (errorMessage.startsWith("Exception: ")) {
          errorMessage = errorMessage.substring(11);
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('登录失败: $errorMessage')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSavedPasswordHint =
        _savedEncryptedPassword != null &&
        _savedEncryptedPassword!.isNotEmpty &&
        _accountController.text == _savedAccount;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer.withAlpha(isDark ? 70 : 105),
              colorScheme.surface,
              colorScheme.surface,
            ],
            stops: const [0, 0.42, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withAlpha(
                                      isDark ? 55 : 45,
                                    ),
                                    blurRadius: 28,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Image.asset(
                                  'lib/assets/Icon.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'CQUT 助手',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 32),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '统一身份认证',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '使用学校统一身份认证账号登录',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  TextFormField(
                                    controller: _accountController,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: '账号',
                                      prefixIcon: Icon(Icons.person_outline),
                                    ),
                                    textInputAction: TextInputAction.next,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _passwordController,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    obscureText: _obscurePassword,
                                    decoration: InputDecoration(
                                      labelText: '密码',
                                      hintText: showSavedPasswordHint
                                          ? '已保存密码，可直接登录'
                                          : '请输入密码',
                                      hintStyle: showSavedPasswordHint
                                          ? TextStyle(
                                              color: colorScheme.primary,
                                            )
                                          : null,
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                      ),
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
                                      onPressed: () {
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
                                  const SizedBox(height: 12),
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
                                    label: Text(_isLoading ? '正在登录' : '登录'),
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
      ),
    );
  }
}
