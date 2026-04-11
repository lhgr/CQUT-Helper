import 'package:cqut/api/auth/forget_password_api.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';

class ForgetPasswordPage extends StatefulWidget {
  const ForgetPasswordPage({super.key});

  @override
  State<ForgetPasswordPage> createState() => _ForgetPasswordPageState();
}

class _ForgetPasswordPageState extends State<ForgetPasswordPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();

  final ForgetPasswordApi _api = ForgetPasswordApi();

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
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _cleanException(Object e) {
    var msg = e.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring(11);
    }
    return msg;
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
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError('请输入手机号');
      return;
    }
    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      _showError('请输入 11 位手机号');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final ticket = await _api.sendAuthCode(mobilePhone: phone);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _step = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('验证码已发送')),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(_cleanException(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    final ticket = _ticket;
    if (ticket == null || ticket.isEmpty) {
      _showError('请先发送验证码');
      return;
    }
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showError('请输入验证码');
      return;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(code)) {
      _showError('验证码格式不正确');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _api.checkAuthCode(ticket: ticket, authCode: code);
      if (!mounted) return;
      setState(() {
        _step = 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('验证码验证成功')),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(_cleanException(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final ticket = _ticket;
    if (ticket == null || ticket.isEmpty) {
      _showError('请先发送验证码');
      return;
    }
    final pwd1 = _passwordController.text;
    final pwd2 = _password2Controller.text;
    if (pwd1.isEmpty || pwd2.isEmpty) {
      _showError('请输入并确认新密码');
      return;
    }
    if (pwd1 != pwd2) {
      _showError('两次输入的密码不一致');
      return;
    }
    if (!_isValidPassword(pwd1)) {
      _showError('密码不符合规则');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAnalytics.instance.logEvent(name: 'forgot_password_set_new_password');
      await _api.setNewPassword(ticket: ticket, password: pwd1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('密码已重置，请用新密码登录')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showError(_cleanException(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('忘记密码')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepHeader(step: _step),
              SizedBox(height: 24),
              if (_step == 0) ...[
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: '手机号',
                    prefixIcon: Icon(Icons.phone_android),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
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
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '验证码',
                    prefixIcon: Icon(Icons.verified_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isLoading ? null : () => setState(() => _step = 0),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('返回'),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                  ],
                ),
              ],
              if (_step == 2) ...[
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '新密码',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _password2Controller,
                  obscureText: _obscurePassword2,
                  decoration: InputDecoration(
                    labelText: '确认新密码',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword2 ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword2 = !_obscurePassword2),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isLoading ? null : () => setState(() => _step = 1),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('返回'),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int step;

  const _StepHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.outline;

    Widget dot(int index, String label) {
      final active = index == step;
      final done = index < step;
      final bg = done ? color : (active ? color : Colors.transparent);
      final fg = done || active ? Theme.of(context).colorScheme.onPrimary : outline;
      return Expanded(
        child: Column(
          children: [
            Container(
              width: 28,
              height: 28,
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

    return Row(
      children: [
        dot(0, '手机号'),
        dot(1, '验证码'),
        dot(2, '新密码'),
      ],
    );
  }
}
