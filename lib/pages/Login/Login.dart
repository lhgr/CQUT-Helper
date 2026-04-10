import 'package:cqut/api/auth/auth_api.dart';
import 'package:cqut/pages/Login/ForgetPassword.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
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
    final encryptedPwd = prefs.getString('encrypted_password');

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

      // 登录成功，保存凭证
      await FirebaseAnalytics.instance.logLogin(loginMethod: 'password');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account', account);
      await prefs.setInt(
        'schedule_notice_login_marker_$account',
        DateTime.now().millisecondsSinceEpoch,
      );
      if (useSavedPassword) {
        await prefs.setString('encrypted_password', _savedEncryptedPassword!);
      } else {
        final encrypted = _authApi.encryptPassword(password);
        await prefs.setString('encrypted_password', encrypted);
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
    // 判断是否显示“已保存密码”提示
    bool showSavedPasswordHint =
        _savedEncryptedPassword != null &&
        _savedEncryptedPassword!.isNotEmpty &&
        _accountController.text == _savedAccount;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.school_rounded,
                      size: 60,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    "CQUT 助手",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "让校园生活更简单",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  SizedBox(height: 48),
                  TextFormField(
                    controller: _accountController,
                    decoration: InputDecoration(
                      labelText: "账号",
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: "密码",
                      hintText: showSavedPasswordHint ? "已保存密码，可直接登录" : "请输入密码",
                      hintStyle: showSavedPasswordHint
                          ? TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withAlpha(179),
                            )
                          : null,
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                    onFieldSubmitted: (_) => _handleLogin(),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await FirebaseAnalytics.instance.logEvent(
                            name: 'forgot_password_click',
                          );
                          if (!context.mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgetPasswordPage(),
                            ),
                          );
                        },
                        child: Text("忘记密码?"),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : Text(
                            "登录",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
