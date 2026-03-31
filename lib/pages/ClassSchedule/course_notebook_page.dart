import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cqut/manager/course_notebook_manager.dart';
import 'package:cqut/utils/course_notebook_key_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

class CourseNotebookPage extends StatefulWidget {
  final String courseName;
  final String? yearTerm;
  final String? subtitle;

  const CourseNotebookPage({
    super.key,
    required this.courseName,
    this.yearTerm,
    this.subtitle,
  });

  @override
  State<CourseNotebookPage> createState() => _CourseNotebookPageState();
}

class _CourseNotebookPageState extends State<CourseNotebookPage> {
  final CourseNotebookManager _manager = CourseNotebookManager.I;
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Timer? _saveDebounce;
  bool _loading = true;
  bool _savingImage = false;
  String? _error;
  List<CourseNoteImage> _images = <CourseNoteImage>[];
  String _courseKey = '';

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final normalizedName = normalizeCourseName(widget.courseName);
      final record = await _manager.loadRecord(
        courseName: normalizedName,
        yearTerm: widget.yearTerm,
      );
      final key = await _manager.buildCourseKey(
        courseName: normalizedName,
        yearTerm: widget.yearTerm,
      );
      if (!mounted) {
        return;
      }
      _courseKey = key;
      _images = record.images.where((e) => e.path.trim().isNotEmpty).toList();
      _textController.text = record.text;
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '加载记事本失败：$e';
      });
    }
  }

  void _onTextChanged() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        await _manager.saveText(
          courseName: widget.courseName,
          yearTerm: widget.yearTerm,
          text: _textController.text,
        );
      } catch (_) {}
    });
    setState(() {});
  }

  Future<void> _pickAndAddPhoto() async {
    if (_savingImage) {
      return;
    }
    setState(() {
      _savingImage = true;
    });
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
      );
      if (photo == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _savingImage = false;
        });
        return;
      }
      final bytes = await photo.readAsBytes();
      final compressed = await _compress(bytes);
      final dir = await _manager.ensureCourseImageDir(
        courseName: widget.courseName,
        yearTerm: widget.yearTerm,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${dir.path}${Platform.pathSeparator}img_$now.jpg';
      final file = File(filePath);
      await file.writeAsBytes(compressed, flush: true);
      final image = CourseNoteImage(
        id: now.toString(),
        path: file.path,
        createdAt: now,
        displayName: '图片_$now',
      );
      final next = List<CourseNoteImage>.from(_images)..add(image);
      await _manager.saveImages(
        courseName: widget.courseName,
        yearTerm: widget.yearTerm,
        images: next,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _images = next;
        _savingImage = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savingImage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('拍照失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<Uint8List> _compress(Uint8List bytes) async {
    final result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1440,
      minHeight: 1440,
      quality: 72,
      format: CompressFormat.jpeg,
    );
    if (result.isEmpty) {
      return bytes;
    }
    return result;
  }

  Future<void> _deleteImage(int index) async {
    if (index < 0 || index >= _images.length) {
      return;
    }
    final target = _images[index];
    final next = List<CourseNoteImage>.from(_images)..removeAt(index);
    await _manager.saveImages(
      courseName: widget.courseName,
      yearTerm: widget.yearTerm,
      images: next,
    );
    await _manager.deleteRecordImageFile(target.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _images = next;
    });
  }

  Future<void> _reorderImages(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _images.length) {
      return;
    }
    if (newIndex > _images.length) {
      newIndex = _images.length;
    }
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex) {
      return;
    }
    final next = List<CourseNoteImage>.from(_images);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    await _manager.saveImages(
      courseName: widget.courseName,
      yearTerm: widget.yearTerm,
      images: next,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _images = next;
    });
  }

  Future<void> _renameImage(int index) async {
    if (index < 0 || index >= _images.length) {
      return;
    }
    final target = _images[index];
    final initialName = target.displayName.trim().isEmpty
        ? '图片_${index + 1}'
        : target.displayName.trim();
    final controller = TextEditingController(text: initialName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('编辑图片名称'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 1,
            decoration: const InputDecoration(
              hintText: '请输入图片名称',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) {
      return;
    }
    final next = List<CourseNoteImage>.from(_images);
    next[index] = target.copyWith(displayName: newName);
    await _manager.saveImages(
      courseName: widget.courseName,
      yearTerm: widget.yearTerm,
      images: next,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _images = next;
    });
  }

  void _showPreview(CourseNoteImage image) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            child: Image.file(File(image.path), fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle;
    return Scaffold(
      appBar: AppBar(
        title: Text(normalizeCourseName(widget.courseName)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              subtitle?.trim().isNotEmpty == true
                  ? subtitle!.trim()
                  : (widget.yearTerm?.trim().isNotEmpty == true
                        ? '${widget.yearTerm}学期 · $_courseKey'
                        : _courseKey),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: isWide
                              ? Row(
                                  children: [
                                    Expanded(flex: 6, child: _buildTextCard()),
                                    const SizedBox(width: 12),
                                    Expanded(flex: 5, child: _buildMediaCard()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Expanded(flex: 5, child: _buildTextCard()),
                                    const SizedBox(height: 12),
                                    Expanded(flex: 4, child: _buildMediaCard()),
                                  ],
                                ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildTextCard() {
    final count = _textController.text.runes.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '课程笔记',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '字数：$count（自动保存）',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '记录本课程的重点、作业安排、复习计划...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '课堂照片 (${_images.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _savingImage ? null : _pickAndAddPhoto,
                  icon: _savingImage
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: Text(_savingImage ? '处理中' : '拍照'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _images.isEmpty
                  ? Center(
                      child: Text(
                        '暂无图片，点击右上角拍照添加',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: _images.length,
                      onReorder: _reorderImages,
                      itemBuilder: (context, index) {
                        final image = _images[index];
                        final displayName = image.displayName.trim().isEmpty
                            ? '图片 ${index + 1}'
                            : image.displayName.trim();
                        return Card(
                          key: ValueKey(image.id),
                          child: ListTile(
                            leading: GestureDetector(
                              onTap: () => _showPreview(image),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(image.path),
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 50,
                                      height: 50,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.broken_image),
                                    );
                                  },
                                ),
                              ),
                            ),
                            title: Text(displayName),
                            subtitle: Text(
                              DateTime.fromMillisecondsSinceEpoch(
                                image.createdAt,
                              ).toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _renameImage(index),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  onPressed: () => _deleteImage(index),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
