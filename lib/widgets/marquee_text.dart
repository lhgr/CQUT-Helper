import 'package:flutter/material.dart';

/// Scrolls a single line back and forth only when it exceeds the available
/// width. This keeps helper text readable without increasing form height.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double pixelsPerSecond;
  final Duration pause;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.pixelsPerSecond = 32,
    this.pause = const Duration(milliseconds: 800),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _controller = ScrollController();
  int _loopGeneration = 0;
  bool _loopScheduled = false;

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.pixelsPerSecond != widget.pixelsPerSecond ||
        oldWidget.pause != widget.pause) {
      _restart();
    }
  }

  void _restart() {
    _loopGeneration++;
    _loopScheduled = false;
    if (_controller.hasClients) _controller.jumpTo(0);
  }

  void _scheduleLoop() {
    if (_loopScheduled) return;
    _loopScheduled = true;
    final generation = ++_loopGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runLoop(generation);
    });
  }

  Future<void> _runLoop(int generation) async {
    if (!mounted || generation != _loopGeneration || !_controller.hasClients) {
      return;
    }
    final maxExtent = _controller.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final travelDuration = Duration(
      milliseconds: (maxExtent / widget.pixelsPerSecond * 1000).round().clamp(
        300,
        12000,
      ),
    );
    while (mounted && generation == _loopGeneration) {
      await Future<void>.delayed(widget.pause);
      if (!mounted || generation != _loopGeneration) return;
      await _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: travelDuration,
        curve: Curves.linear,
      );
      if (!mounted || generation != _loopGeneration) return;
      await Future<void>.delayed(widget.pause);
      if (!mounted || generation != _loopGeneration) return;
      await _controller.animateTo(
        0,
        duration: travelDuration,
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _loopGeneration++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleLoop();
    return Semantics(
      label: widget.text,
      child: ClipRect(
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: ExcludeSemantics(
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: widget.style,
            ),
          ),
        ),
      ),
    );
  }
}
