import 'package:cqut_helper/api/auth/forget_password_api.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class ForgetPasswordPage extends StatefulWidget {
  final ForgetPasswordApi? api;
  const ForgetPasswordPage({super.key, this.api});

  @override
  State<ForgetPasswordPage> createState() => _ForgetPasswordPageState();
}

class _ForgetPasswordPageState extends State<ForgetPasswordPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();

  late final ForgetPasswordApi _api = widget.api ?? ForgetPasswordApi();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  String? _phoneError;
  String? _codeError;
  String? _passwordError;
  String? _confirmError;
  String? _operationError;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscurePassword2 = true;

  int _step = 0;
  String? _ticket;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _password2Controller.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _operationError = message);
  }

  String _operationErrorMessage(Object error, {required String fallback}) {
    if (error is DioException) return '请求未能完成，请检查网络后重试';
    if (error is FormatException) return '服务响应异常，请稍后重试';
    if (error is PlatformException) return '系统操作未能完成，请稍后重试';

    if (error is Exception) {
      final rawMessage = error.toString();
      if (!rawMessage.startsWith('Exception: ')) return fallback;
      final message = rawMessage.substring('Exception: '.length).trim();
      const technicalMessages = {'发送验证码失败：缺少 ticket', '响应格式异常'};
      if (technicalMessages.contains(message) || message.isEmpty) {
        return fallback;
      }
      return message;
    }
    return fallback;
  }

  bool _isValidPassword(String password) {
    if (password.length < 8 || password.length > 20) return false;

    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(password);

    var kinds = 0;
    if (hasUpper) kinds++;
    if (hasLower) kinds++;
    if (hasDigit) kinds++;
    if (hasSymbol) kinds++;
    return kinds >= 3;
  }

  Future<void> _sendCode() async {
    if (_isLoading) return;
    final phone = _phoneController.text.trim();
    setState(
      () => _phoneError = phone.isEmpty
          ? '请输入手机号'
          : !RegExp(r'^\d{11}$').hasMatch(phone)
          ? '请输入 11 位手机号'
          : null,
    );
    if (_phoneError != null) {
      _phoneFocus.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _operationError = null;
    });
    try {
      final ticket = await _api.sendAuthCode(mobilePhone: phone);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _step = 1;
        _codeController.clear();
        _codeError = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('验证码已发送')));
    } catch (e, stackTrace) {
      AppLogger.I.logOperationFailure(
        'ForgetPassword',
        'send verification code failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _showError(_operationErrorMessage(e, fallback: '验证码发送失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_isLoading) return;
    final ticket = _ticket;
    if (ticket == null || ticket.isEmpty) {
      _showError('请先发送验证码');
      return;
    }
    final code = _codeController.text.trim();
    setState(
      () => _codeError = code.isEmpty
          ? '请输入验证码'
          : !RegExp(r'^\d{4,8}$').hasMatch(code)
          ? '验证码格式不正确'
          : null,
    );
    if (_codeError != null) {
      _codeFocus.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _operationError = null;
    });
    try {
      await _api.checkAuthCode(ticket: ticket, authCode: code);
      if (!mounted) return;
      setState(() {
        _step = 2;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('验证码验证成功')));
    } catch (e, stackTrace) {
      AppLogger.I.logOperationFailure(
        'ForgetPassword',
        'verify code failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _showError(_operationErrorMessage(e, fallback: '验证码验证失败，请检查后重试'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_isLoading) return;
    final ticket = _ticket;
    if (ticket == null || ticket.isEmpty) {
      _showError('请先发送验证码');
      return;
    }
    final pwd1 = _passwordController.text;
    final pwd2 = _password2Controller.text;
    setState(() {
      _passwordError = pwd1.isEmpty
          ? '请输入新密码'
          : !_isValidPassword(pwd1)
          ? '请输入 8–20 位密码，包含至少三种字符'
          : null;
      _confirmError = pwd2.isEmpty
          ? '请确认新密码'
          : pwd1 != pwd2
          ? '两次输入的密码不一致'
          : null;
    });
    if (_passwordError != null || _confirmError != null) {
      (_passwordError != null ? _passwordFocus : _confirmFocus).requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _operationError = null;
    });
    try {
      await _api.setNewPassword(ticket: ticket, password: pwd1);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('密码已重置，请用新密码登录')));
      Navigator.of(context).pop();
    } catch (e, stackTrace) {
      AppLogger.I.logOperationFailure(
        'ForgetPassword',
        'reset password failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _showError(_operationErrorMessage(e, fallback: '密码重置失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _modifyPhone() {
    if (_isLoading) return;
    setState(() {
      _step = 0;
      _ticket = null;
      _codeController.clear();
      _passwordController.clear();
      _password2Controller.clear();
      _codeError = null;
      _passwordError = null;
      _confirmError = null;
      _operationError = null;
    });
    _phoneFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('忘记密码')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '重置统一身份认证密码',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '验证手机号后设置新密码',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _StepHeader(step: _step),
                  if (_operationError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _operationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_step == 0) ...[
                    TextFormField(
                      controller: _phoneController,
                      focusNode: _phoneFocus,
                      enabled: !_isLoading,
                      onChanged: (_) => setState(() {
                        _phoneError = null;
                        _operationError = null;
                      }),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _sendCode(),
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: '手机号',
                        errorText: _phoneError,
                        errorMaxLines: 3,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isLoading ? null : _sendCode,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '发送验证码',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                  if (_step == 1) ...[
                    Text(
                      '验证码已发送到：${_phoneController.text.trim()}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: _codeController,
                      focusNode: _codeFocus,
                      enabled: !_isLoading,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _verifyCode(),
                      onChanged: (_) => setState(() {
                        _codeError = null;
                        _operationError = null;
                      }),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '验证码',
                        errorText: _codeError,
                        errorMaxLines: 3,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    _RecoveryActions(
                      secondary: OutlinedButton(
                        onPressed: _isLoading ? null : _modifyPhone,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('修改手机号'),
                      ),
                      primary: FilledButton(
                        onPressed: _isLoading ? null : _verifyCode,
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
                                ),
                              )
                            : Text(
                                '验证验证码',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading ? null : _sendCode,
                        child: const Text('重新发送验证码'),
                      ),
                    ),
                  ],
                  if (_step == 2) ...[
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      enabled: !_isLoading,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {
                        _passwordError = null;
                        _operationError = null;
                      }),
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '新密码',
                        errorText: _passwordError,
                        errorMaxLines: 3,
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '显示新密码' : '隐藏新密码',
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
                      ),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _password2Controller,
                      focusNode: _confirmFocus,
                      enabled: !_isLoading,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _resetPassword(),
                      onChanged: (_) => setState(() {
                        _confirmError = null;
                        _operationError = null;
                      }),
                      obscureText: _obscurePassword2,
                      decoration: InputDecoration(
                        labelText: '确认新密码',
                        errorText: _confirmError,
                        errorMaxLines: 3,
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword2 ? '显示确认密码' : '隐藏确认密码',
                          icon: Icon(
                            _obscurePassword2
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword2 = !_obscurePassword2,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '密码必须包含:大写字母、小写字母、数字、字符中任意三种以上组合，长度为8-20个字符。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    SizedBox(height: 16),
                    _RecoveryActions(
                      secondary: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() => _step = 1),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('返回'),
                      ),
                      primary: FilledButton(
                        onPressed: _isLoading ? null : _resetPassword,
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
                                ),
                              )
                            : Text(
                                '重置密码',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryActions extends StatelessWidget {
  final Widget secondary;
  final Widget primary;
  const _RecoveryActions({required this.secondary, required this.primary});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 360 ||
          MediaQuery.textScalerOf(context).scale(16) > 20;
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [primary, const SizedBox(height: 12), secondary],
        );
      }
      return Row(
        children: [
          Expanded(child: secondary),
          const SizedBox(width: 12),
          Expanded(child: primary),
        ],
      );
    },
  );
}

class _StepHeader extends StatelessWidget {
  final int step;

  const _StepHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.outline;
    final numberStyle = DefaultTextStyle.of(context).style
        .copyWith(fontWeight: FontWeight.bold);
    final numberMetrics = TextPainter(
      text: TextSpan(text: '3', style: numberStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final contentSize = numberMetrics.height > numberMetrics.width
        ? numberMetrics.height
        : numberMetrics.width;
    final circleSize = (contentSize + 12).clamp(28.0, double.infinity);
    numberMetrics.dispose();

    Widget dot(int index, String label) {
      final active = index == step;
      final done = index < step;
      final bg = done ? color : (active ? color : Colors.transparent);
      final fg = done || active
          ? Theme.of(context).colorScheme.onPrimary
          : outline;
      return Expanded(
        child: Column(
          children: [
            Container(
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: active || done ? color : outline),
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(fontWeight: FontWeight.bold, color: fg),
              ),
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: active ? color : outline,
                fontWeight: active ? FontWeight.bold : null,
              ),
            ),
          ],
        ),
      );
    }

    return Row(children: [dot(0, '手机号'), dot(1, '验证码'), dot(2, '新密码')]);
  }
}
