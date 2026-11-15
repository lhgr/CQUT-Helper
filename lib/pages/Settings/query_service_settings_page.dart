import 'package:cqut_helper/manager/exam_repository.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:material_ui/material_ui.dart';

enum _ServiceMode { official, custom }

class QueryServiceSettingsPage extends StatefulWidget {
  const QueryServiceSettingsPage({super.key});
  @override
  State<QueryServiceSettingsPage> createState() =>
      _QueryServiceSettingsPageState();
}

class _QueryServiceSettingsPageState extends State<QueryServiceSettingsPage> {
  final _controller = TextEditingController();
  _ServiceMode _mode = _ServiceMode.official;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await ScheduleSettingsManager.loadNoticeApiBaseUrl();
    if (!mounted) return;
    _mode = url == ScheduleSettingsManager.officialNoticeApiBaseUrl
        ? _ServiceMode.official
        : _ServiceMode.custom;
    if (_mode == _ServiceMode.custom) _controller.text = url;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final value = _mode == _ServiceMode.official
        ? ScheduleSettingsManager.officialNoticeApiBaseUrl
        : _controller.text.trim();
    if (!ScheduleSettingsManager.isValidNoticeApiBaseUrl(value)) {
      setState(() {
        _error = value.isEmpty ? '请输入自定义服务地址' : '请输入不含路径的 HTTPS 服务地址';
        _saveError = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _saveError = null;
    });
    try {
      if (_mode == _ServiceMode.custom) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: const Text('使用自定义服务'),
            content: const Text(
              '考试与调课查询将通过此服务进行，你的学号和登录验证信息会发送给该服务。使用不可信的服务可能导致账号信息泄露，请确认地址及服务提供方可信。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认并保存'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
      }
      await ScheduleSettingsManager.saveQueryServiceBaseUrl(value);
      ExamRepository.instance.invalidate();
      if (mounted) {
        final normalized = ScheduleSettingsManager.normalizeNoticeApiBaseUrl(
          value,
        );
        setState(() {
          _mode = normalized == ScheduleSettingsManager.officialNoticeApiBaseUrl
              ? _ServiceMode.official
              : _ServiceMode.custom;
          if (_mode == _ServiceMode.custom) _controller.text = normalized;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('教务查询服务地址已保存')));
      }
    } catch (_) {
      if (mounted) setState(() => _saveError = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('教务查询服务')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Text('用于考试安排与调课通知。调课通知可在“通知与提醒”中开启。'),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                child: RadioGroup<_ServiceMode>(
                  groupValue: _mode,
                  onChanged: (value) {
                    if (_saving || value == null) return;
                    setState(() {
                      _mode = value;
                      _error = null;
                      _saveError = null;
                    });
                  },
                  child: Column(
                    children: [
                      RadioListTile<_ServiceMode>(
                        title: const Text('官方服务'),
                        subtitle: const Text(
                          ScheduleSettingsManager.officialNoticeApiBaseUrl,
                        ),
                        value: _ServiceMode.official,
                        enabled: !_saving,
                      ),
                      const Divider(height: 1),
                      RadioListTile<_ServiceMode>(
                        title: const Text('自定义服务'),
                        value: _ServiceMode.custom,
                        enabled: !_saving,
                      ),
                      if (_mode == _ServiceMode.custom)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: TextField(
                            controller: _controller,
                            enabled: !_saving,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: '教务查询服务地址',
                              hintText: 'https://example.com',
                              errorText: _error,
                              errorMaxLines: 3,
                            ),
                            onChanged: (_) {
                              if (_error != null || _saveError != null) {
                                setState(() {
                                  _error = null;
                                  _saveError = null;
                                });
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存地址'),
              ),
            ],
          ),
  );
}
