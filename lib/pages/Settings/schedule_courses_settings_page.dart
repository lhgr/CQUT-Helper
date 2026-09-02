import 'dart:io';

import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/hidden_courses_sheet.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:cqut_helper/utils/background_color_extractor.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'schedule_background_crop_page.dart';
import 'schedule_layout_preview.dart';
import 'settings_schedule_scope.dart';

class ScheduleCoursesSettingsPage extends StatefulWidget {
  final SettingsScheduleScope scope;

  const ScheduleCoursesSettingsPage({super.key, required this.scope});

  @override
  State<ScheduleCoursesSettingsPage> createState() =>
      _ScheduleCoursesSettingsPageState();
}

class _ScheduleCoursesSettingsPageState
    extends State<ScheduleCoursesSettingsPage> {
  static const ScheduleLayoutSettings _defaultLayout = ScheduleLayoutSettings();

  final ScheduleSettingsManager _manager = ScheduleSettingsManager();
  final ImagePicker _imagePicker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _handlingPop = false;
  bool _extractingThemeColor = false;
  bool _backgroundChanged = false;
  bool _backgroundRemoved = false;
  bool _showWeekend = false;
  bool _timeInfoEnabled = true;
  ScheduleLayoutSettings _layout = const ScheduleLayoutSettings();
  String? _pickedImagePath;
  Color? _pendingExtractedThemeColor;
  int? _hiddenCourseCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _manager.load();
    final hiddenCourses = widget.scope.canManageCourses
        ? await ScheduleCustomizationManager.instance.hiddenCourses(
            userId: widget.scope.userId,
            yearTerm: widget.scope.yearTerm,
          )
        : null;
    if (!mounted) return;
    setState(() {
      _showWeekend = _manager.showWeekend;
      _timeInfoEnabled = _manager.timeInfoEnabled;
      _layout = _manager.layoutSettings;
      _hiddenCourseCount = hiddenCourses?.length;
      _loading = false;
      _dirty = false;
      _backgroundChanged = false;
      _backgroundRemoved = false;
      _pendingExtractedThemeColor = null;
    });
  }

  void _change(VoidCallback update) {
    setState(() {
      update();
      _dirty = true;
    });
  }

  Future<void> _changeDisplaySettings({
    bool? showWeekend,
    bool? timeInfoEnabled,
  }) async {
    setState(() {
      _showWeekend = showWeekend ?? _showWeekend;
      _timeInfoEnabled = timeInfoEnabled ?? _timeInfoEnabled;
    });
    await _manager.save(
      showWeekend: _showWeekend,
      timeInfoEnabled: _timeInfoEnabled,
      backgroundPollingEnabled: _manager.backgroundPollingEnabled,
      noticeApiBaseUrl: _manager.noticeApiBaseUrl,
    );
  }

  Future<void> _pickBackground() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 92,
      );
      if (image == null || !mounted) return;
      final screenSize = MediaQuery.sizeOf(context);
      final croppedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => ScheduleBackgroundCropPage(
            imagePath: image.path,
            targetAspectRatio: screenSize.width / screenSize.height,
          ),
        ),
      );
      if (croppedPath == null || !mounted) return;
      _change(() {
        _pickedImagePath = croppedPath;
        _layout = _layout.copyWith(backgroundImagePath: croppedPath);
        _pendingExtractedThemeColor = null;
        _backgroundChanged = true;
        _backgroundRemoved = false;
      });
      final shouldExtract = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('从背景图片取色？'),
          content: const Text('可以提取背景图片的代表色，保存课表设置后将其作为应用主题色。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('暂不取色'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('开始取色'),
            ),
          ],
        ),
      );
      if (shouldExtract == true && mounted) {
        await _extractThemeColor(croppedPath);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法读取图片：$error')));
    }
  }

  void _removeBackground() {
    _change(() {
      _pickedImagePath = null;
      _layout = _layout.copyWith(clearBackgroundImage: true);
      _pendingExtractedThemeColor = null;
      _backgroundChanged = true;
      _backgroundRemoved = true;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('保存后将删除背景图，并切换为系统自动取色')));
  }

  Future<void> _extractThemeColor([String? sourcePath]) async {
    final path = sourcePath ?? _layout.backgroundImagePath;
    if (path == null || path.trim().isEmpty || _extractingThemeColor) return;
    setState(() => _extractingThemeColor = true);
    try {
      final color = await BackgroundColorExtractor.extractFromPath(path);
      if (!mounted) return;
      if (color == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未能从这张图片提取合适的主题色')));
        return;
      }
      _change(() => _pendingExtractedThemeColor = color);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已完成取色，保存课表设置后应用')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('背景取色失败：$error')));
    } finally {
      if (mounted) setState(() => _extractingThemeColor = false);
    }
  }

  Future<String?> _persistPickedBackground() async {
    final sourcePath = _pickedImagePath;
    if (sourcePath == null) return _layout.backgroundImagePath;
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final directory = await getApplicationDocumentsDirectory();
    final rawExtension = p.extension(sourcePath).toLowerCase();
    final extension = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(rawExtension)
        ? rawExtension
        : '.jpg';
    final target = File(
      p.join(directory.path, 'schedule_background$extension'),
    );
    if (p.normalize(source.path) != p.normalize(target.path)) {
      await source.copy(target.path);
    }
    return target.path;
  }

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      final backgroundPath = await _persistPickedBackground();
      final layout = backgroundPath == null
          ? _layout.copyWith(clearBackgroundImage: true)
          : _layout.copyWith(backgroundImagePath: backgroundPath);
      if (_backgroundChanged && backgroundPath != null) {
        if (!mounted) return false;
        await ScheduleBackground.precacheFile(context, backgroundPath);
        if (!mounted) return false;
      }
      await _manager.save(
        showWeekend: _showWeekend,
        timeInfoEnabled: _timeInfoEnabled,
        backgroundPollingEnabled: _manager.backgroundPollingEnabled,
        noticeApiBaseUrl: _manager.noticeApiBaseUrl,
        notify: false,
      );
      await _manager.saveLayoutSettings(layout);
      final themeManager = ThemeManager();
      if (layout.backgroundImagePath == null || _backgroundRemoved) {
        await themeManager.clearScheduleBackgroundColor();
      } else if (_pendingExtractedThemeColor != null) {
        await themeManager.applyScheduleBackgroundColor(
          _pendingExtractedThemeColor!,
        );
      } else if (_backgroundChanged) {
        await themeManager.invalidateScheduleBackgroundColor();
      }
      if (!mounted) return false;
      setState(() {
        _layout = layout;
        _pickedImagePath = null;
        _dirty = false;
        _backgroundChanged = false;
        _backgroundRemoved = false;
        _pendingExtractedThemeColor = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('课表布局已保存')));
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handlePopInvoked(bool didPop) async {
    if (didPop || !_dirty || _handlingPop) return;
    _handlingPop = true;
    final action = await showDialog<_UnsavedAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改尚未保存'),
        content: const Text('离开前是否保存“课表布局自定义”的修改？'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _UnsavedAction.keepEditing),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _UnsavedAction.discard),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, _UnsavedAction.save),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == _UnsavedAction.discard) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    } else if (action == _UnsavedAction.save) {
      final saved = await _save();
      if (saved && mounted) Navigator.of(context).pop();
    }
    _handlingPop = false;
  }

  void _reset() {
    _change(() {
      _showWeekend = false;
      _timeInfoEnabled = true;
      _layout = const ScheduleLayoutSettings();
      _pickedImagePath = null;
      _pendingExtractedThemeColor = null;
      _backgroundChanged = true;
      _backgroundRemoved = true;
    });
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重置课表设置？'),
        content: const Text('界面显示与课程卡片设置将恢复默认值，自定义背景图片也会被移除。确认后仍需保存才能生效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _reset();
  }

  Future<void> _openHiddenCourses() async {
    if (!widget.scope.canManageCourses) return;
    await showHiddenCoursesSheet(
      context,
      userId: widget.scope.userId,
      yearTerm: widget.scope.yearTerm,
    );
    if (mounted) await _loadHiddenCourseCount();
  }

  Future<void> _loadHiddenCourseCount() async {
    final hiddenCourses = await ScheduleCustomizationManager.instance
        .hiddenCourses(
          userId: widget.scope.userId,
          yearTerm: widget.scope.yearTerm,
        );
    if (mounted) setState(() => _hiddenCourseCount = hiddenCourses.length);
  }

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      appBar: AppBar(
        title: const Text('课表布局自定义'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _confirmReset,
            child: const Text('重置'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonal(
              onPressed: !_dirty || _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final previewHeight = (constraints.maxHeight * 0.42)
                    .clamp(210.0, 310.0)
                    .toDouble();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: Row(
                        children: [
                          Text(
                            '实时预览',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          Text(
                            '可横向、纵向滑动',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        height: previewHeight,
                        child: ScheduleLayoutPreview(
                          settings: _layout,
                          showWeekend: _showWeekend,
                          timeInfoEnabled: _timeInfoEnabled,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          Text(
                            '功能设置',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Card(
                            elevation: 0,
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: const Text('显示节次时间'),
                                  subtitle: const Text('关闭后仅保留节次数字'),
                                  value: _timeInfoEnabled,
                                  onChanged: (value) => _changeDisplaySettings(
                                    timeInfoEnabled: value,
                                  ),
                                ),
                                SwitchListTile(
                                  title: const Text('显示周末'),
                                  subtitle: const Text('关闭后仅显示周一到周五'),
                                  value: _showWeekend,
                                  onChanged: (value) => _changeDisplaySettings(
                                    showWeekend: value,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(context, '界面显示'),
                          Card(
                            elevation: 0,
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.image_outlined),
                                  title: const Text('自定义背景图片'),
                                  subtitle: Text(
                                    _layout.backgroundImagePath == null
                                        ? '未选择图片'
                                        : '已选择，可在上方实时预览',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_layout.backgroundImagePath != null)
                                        IconButton(
                                          tooltip: '移除背景',
                                          onPressed: _removeBackground,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      TextButton(
                                        onPressed: _pickBackground,
                                        child: Text(
                                          _layout.backgroundImagePath == null
                                              ? '选择'
                                              : '更换',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_layout.backgroundImagePath != null) ...[
                                  const Divider(height: 1),
                                  ListTile(
                                    leading: _ThemeColorPreview(
                                      color:
                                          _pendingExtractedThemeColor ??
                                          (_backgroundChanged
                                              ? null
                                              : ThemeManager()
                                                    .scheduleBackgroundColor),
                                    ),
                                    title: const Text('从背景图片取色'),
                                    subtitle: Text(
                                      _extractingThemeColor
                                          ? '正在分析背景图片…'
                                          : _pendingExtractedThemeColor != null
                                          ? '已提取颜色，保存后将作为主题色'
                                          : !_backgroundChanged &&
                                                ThemeManager().colorSource ==
                                                    ThemeColorSource
                                                        .scheduleBackground
                                          ? '当前正在使用背景图片主题色'
                                          : '提取代表色并应用为全局主题色',
                                    ),
                                    trailing: FilledButton.tonal(
                                      onPressed: _extractingThemeColor
                                          ? null
                                          : _extractThemeColor,
                                      child: Text(
                                        _extractingThemeColor ? '取色中…' : '提取颜色',
                                      ),
                                    ),
                                  ),
                                  _slider(
                                    context,
                                    label: '背景图片不透明度',
                                    value: _layout.backgroundOpacity,
                                    defaultValue:
                                        _defaultLayout.backgroundOpacity,
                                    min: 0.05,
                                    max: 1,
                                    divisions: 19,
                                    valueLabel:
                                        '${(_layout.backgroundOpacity * 100).round()}%',
                                    onChanged: (value) => _change(
                                      () => _layout = _layout.copyWith(
                                        backgroundOpacity: value,
                                      ),
                                    ),
                                  ),
                                  _slider(
                                    context,
                                    label: '背景模糊度',
                                    value: _layout.backgroundBlur,
                                    defaultValue: _defaultLayout.backgroundBlur,
                                    min: 0,
                                    max: 20,
                                    divisions: 20,
                                    valueLabel: _layout.backgroundBlur
                                        .round()
                                        .toString(),
                                    onChanged: (value) => _change(
                                      () => _layout = _layout.copyWith(
                                        backgroundBlur: value,
                                      ),
                                    ),
                                  ),
                                ],
                                _slider(
                                  context,
                                  label: '网格宽度',
                                  value: _layout.gridCellWidth,
                                  defaultValue: _defaultLayout.gridCellWidth,
                                  min: ScheduleLayoutSettings.minGridCellWidth,
                                  max: ScheduleLayoutSettings.maxGridCellWidth,
                                  divisions: 28,
                                  valueLabel:
                                      '${_layout.gridCellWidth.round()} dp',
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      gridCellWidth: value,
                                    ),
                                  ),
                                ),
                                _slider(
                                  context,
                                  label: '网格高度',
                                  value: _layout.gridCellHeight,
                                  defaultValue: _defaultLayout.gridCellHeight,
                                  min: ScheduleLayoutSettings.minGridCellHeight,
                                  max: ScheduleLayoutSettings.maxGridCellHeight,
                                  divisions: 28,
                                  valueLabel:
                                      '${_layout.gridCellHeight.round()} dp',
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      gridCellHeight: value,
                                    ),
                                  ),
                                ),
                                SwitchListTile(
                                  title: const Text('显示网格线'),
                                  subtitle: const Text('关闭后隐藏课表横向与纵向分隔线'),
                                  value: _layout.showGridLines,
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      showGridLines: value,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _sectionTitle(context, '课程卡片'),
                          Card(
                            elevation: 0,
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: const Text('隐藏上课地点'),
                                  value: _layout.hideLocation,
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      hideLocation: value,
                                    ),
                                  ),
                                ),
                                SwitchListTile(
                                  title: const Text('隐藏授课老师'),
                                  value: _layout.hideTeacher,
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      hideTeacher: value,
                                    ),
                                  ),
                                ),
                                SwitchListTile(
                                  title: const Text('移除地点前的校区标识'),
                                  subtitle: const Text('仅移除“花溪校区”和“两江校区”'),
                                  value: _layout.removeCampusPrefix,
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      removeCampusPrefix: value,
                                    ),
                                  ),
                                ),
                                SwitchListTile(
                                  title: const Text('文字水平居中'),
                                  value: _layout.horizontalCenter,
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      horizontalCenter: value,
                                    ),
                                  ),
                                ),
                                SwitchListTile(
                                  title: const Text('文字垂直居中'),
                                  value: _layout.verticalCenter,
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      verticalCenter: value,
                                    ),
                                  ),
                                ),
                                _slider(
                                  context,
                                  label: '课程卡片不透明度',
                                  value: _layout.cardOpacity,
                                  defaultValue: _defaultLayout.cardOpacity,
                                  min: 0.1,
                                  max: 1,
                                  divisions: 18,
                                  valueLabel:
                                      '${(_layout.cardOpacity * 100).round()}%',
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      cardOpacity: value,
                                    ),
                                  ),
                                ),
                                _slider(
                                  context,
                                  label: '卡片圆角',
                                  value: _layout.cardRadius,
                                  defaultValue: _defaultLayout.cardRadius,
                                  min: 0,
                                  max: 28,
                                  divisions: 28,
                                  valueLabel:
                                      '${_layout.cardRadius.round()} dp',
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      cardRadius: value,
                                    ),
                                  ),
                                ),
                                _slider(
                                  context,
                                  label: '文字缩放',
                                  value: _layout.textScale,
                                  defaultValue: _defaultLayout.textScale,
                                  min: 0.7,
                                  max: 1.5,
                                  divisions: 16,
                                  valueLabel:
                                      '${(_layout.textScale * 100).round()}%',
                                  onChanged: (value) => _change(
                                    () => _layout = _layout.copyWith(
                                      textScale: value,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _sectionTitle(context, '课程管理'),
                          Card(
                            elevation: 0,
                            child: ListTile(
                              leading: const Icon(
                                Icons.visibility_off_outlined,
                              ),
                              title: const Text('已隐藏课程'),
                              subtitle: Text(
                                !widget.scope.canManageCourses
                                    ? '请先打开一次课表以确定当前学期'
                                    : _hiddenCourseCount == 0
                                    ? '${widget.scope.yearTerm} 学期 · 暂无隐藏课程'
                                    : '${widget.scope.yearTerm} 学期 · $_hiddenCourseCount 门',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: widget.scope.canManageCourses
                                  ? _openHiddenCourses
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) => _handlePopInvoked(didPop),
      child: page,
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required double value,
    required double defaultValue,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    final isDefault = (value - defaultValue).abs() < 0.0001;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              if (!isDefault)
                IconButton(
                  tooltip: '重置$label',
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? () => onChanged(defaultValue) : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 19),
                ),
              Text(
                valueLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

enum _UnsavedAction { keepEditing, discard, save }

class _ThemeColorPreview extends StatelessWidget {
  final Color? color;

  const _ThemeColorPreview({this.color});

  @override
  Widget build(BuildContext context) {
    final value = color;
    if (value == null) return const Icon(Icons.colorize_outlined);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: value,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}
