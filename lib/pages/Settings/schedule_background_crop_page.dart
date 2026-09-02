import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ScheduleBackgroundCropPage extends StatefulWidget {
  final String imagePath;
  final double targetAspectRatio;

  const ScheduleBackgroundCropPage({
    super.key,
    required this.imagePath,
    required this.targetAspectRatio,
  });

  @override
  State<ScheduleBackgroundCropPage> createState() =>
      _ScheduleBackgroundCropPageState();
}

class _ScheduleBackgroundCropPageState
    extends State<ScheduleBackgroundCropPage> {
  ui.Image? _image;
  Object? _loadError;
  Size _viewportSize = Size.zero;
  Offset _offset = Offset.zero;
  double _scale = 1;
  double _minimumScale = 1;
  double _gestureStartScale = 1;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;
  bool _initializedForViewport = false;
  bool _cropping = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _initializeViewport(Size size) {
    final image = _image;
    if (image == null || size.isEmpty) return;
    _viewportSize = size;
    _minimumScale = math.max(
      size.width / image.width,
      size.height / image.height,
    );
    _scale = _minimumScale;
    _offset = Offset(
      (size.width - image.width * _scale) / 2,
      (size.height - image.height * _scale) / 2,
    );
    _initializedForViewport = true;
  }

  Offset _clampOffset(Offset value, double scale) {
    final image = _image;
    if (image == null) return value;
    final imageWidth = image.width * scale;
    final imageHeight = image.height * scale;
    return Offset(
      value.dx.clamp(_viewportSize.width - imageWidth, 0).toDouble(),
      value.dy.clamp(_viewportSize.height - imageHeight, 0).toDouble(),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _scale;
    _gestureStartOffset = _offset;
    _gestureStartFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final image = _image;
    if (image == null) return;
    final nextScale = (_gestureStartScale * details.scale).clamp(
      _minimumScale,
      _minimumScale * 6,
    );
    final sourcePoint =
        (_gestureStartFocalPoint - _gestureStartOffset) / _gestureStartScale;
    final nextOffset = details.localFocalPoint - sourcePoint * nextScale;
    setState(() {
      _scale = nextScale;
      _offset = _clampOffset(nextOffset, nextScale);
    });
  }

  Future<void> _confirmCrop() async {
    final image = _image;
    if (image == null || _cropping || _viewportSize.isEmpty) return;
    setState(() => _cropping = true);
    try {
      final sourceRect = Rect.fromLTWH(
        -_offset.dx / _scale,
        -_offset.dy / _scale,
        _viewportSize.width / _scale,
        _viewportSize.height / _scale,
      );
      final outputWidth = sourceRect.width.round().clamp(1, image.width);
      final outputHeight = sourceRect.height.round().clamp(1, image.height);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        sourceRect,
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final cropped = await recorder.endRecording().toImage(
        outputWidth,
        outputHeight,
      );
      final bytes = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      if (bytes == null) throw StateError('无法生成裁切图片');
      final directory = await getTemporaryDirectory();
      final target = File(
        p.join(
          directory.path,
          'schedule_background_crop_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await target.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      if (mounted) Navigator.of(context).pop(target.path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _cropping = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('裁切失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('裁切背景图片')),
      body: _loadError != null
          ? Center(child: Text('无法读取图片：$_loadError'))
          : _image == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AspectRatio(
                        aspectRatio: widget.targetAspectRatio,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = constraints.biggest;
                            if (!_initializedForViewport ||
                                _viewportSize != size) {
                              _initializeViewport(size);
                            }
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              child: ClipRect(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onScaleStart: _onScaleStart,
                                  onScaleUpdate: _onScaleUpdate,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Positioned(
                                        left: _offset.dx,
                                        top: _offset.dy,
                                        width: _image!.width * _scale,
                                        height: _image!.height * _scale,
                                        child: RawImage(
                                          image: _image,
                                          fit: BoxFit.fill,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      ),
                                      IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '拖动图片调整位置，双指缩放；裁切比例与课表页一致。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _cropping ? null : _confirmCrop,
                        icon: _cropping
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.crop),
                        label: Text(_cropping ? '正在裁切…' : '确定裁切'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
