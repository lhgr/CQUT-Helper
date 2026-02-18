import 'package:cqut/manager/cache_cleanup_manager.dart';
import 'package:flutter/material.dart';

class ClearCachePage extends StatefulWidget {
  const ClearCachePage({super.key});

  @override
  State<ClearCachePage> createState() => _ClearCachePageState();
}

class _ClearCachePageState extends State<ClearCachePage> {
  bool _loading = true;
  bool _clearing = false;
  List<AppCacheUsage> _usages = const [];
  final Set<AppCacheType> _selected = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final usages = await CacheCleanupManager.getUsages();
      if (!mounted) return;
      setState(() {
        _usages = usages;
        _selected.removeWhere(
          (t) => !usages.any((u) => u.type == t && u.supported),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _usages = const [];
        _selected.clear();
        _loading = false;
      });
    }
  }

  int get _selectedBytes {
    int total = 0;
    for (final u in _usages) {
      if (!_selected.contains(u.type)) continue;
      final b = u.bytes;
      if (b == null) continue;
      total += b;
    }
    return total;
  }

  bool get _canClear {
    return !_clearing &&
        _selected.isNotEmpty &&
        _usages.any((u) => _selected.contains(u.type) && u.supported);
  }

  Future<void> _confirmAndClear() async {
    if (!_canClear) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('清理缓存'),
          content: Text('确定清理所选缓存吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('确定'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _clearing = true);
    try {
      await CacheCleanupManager.clear(_selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清理所选缓存')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清理失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSizeText = _formatBytes(_selectedBytes);

    return Scaffold(
      appBar: AppBar(
        title: Text('清理缓存'),
        actions: [
          IconButton(
            onPressed: _clearing ? null : _refresh,
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                for (final u in _usages) _buildUsageTile(u),
                SizedBox(height: 12),
                Text(
                  '已选占用：$selectedSizeText',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 72),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _canClear ? _confirmAndClear : null,
            icon: _clearing
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.cleaning_services),
            label: Text(_clearing ? '正在清理...' : '清理所选'),
          ),
        ),
      ),
    );
  }

  Widget _buildUsageTile(AppCacheUsage u) {
    final selected = _selected.contains(u.type);
    final sizeText = u.bytes == null ? '无法统计' : _formatBytes(u.bytes!);
    final subtitle = '${u.description}\n占用：$sizeText${u.supported ? '' : '（不可清理）'}';

    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: (!u.supported || _clearing)
            ? null
            : (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(u.type);
                  } else {
                    _selected.remove(u.type);
                  }
                });
              },
        title: Text(u.title),
        subtitle: Text(subtitle),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const k = 1024;
    if (bytes < k) return '$bytes B';
    final kb = bytes / k;
    if (kb < k) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / k;
    if (mb < k) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / k;
    return '${gb.toStringAsFixed(1)} GB';
  }
}

