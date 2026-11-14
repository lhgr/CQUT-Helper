import 'dart:async';

import 'package:material_ui/material_ui.dart';

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
  bool _staticText = false;
  Timer? _pauseTimer;
  double? _lastWidth;
  TextScaler? _lastTextScaler;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final staticText =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    if (staticText != _staticText || scaler != _lastTextScaler) {
      _staticText = staticText;
      _lastTextScaler = scaler;
      _restart();
    }
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.pixelsPerSecond != widget.pixelsPerSecond ||
        oldWidget.pause != widget.pause) {
      _restart();
    }
  }

  void _restart() {
    _loopGeneration++;
    _loopScheduled = false;
    _pauseTimer?.cancel();
    _pauseTimer = null;
  }

  void _scheduleLoop() {
    if (_loopScheduled || _staticText) return;
    _loopScheduled = true;
    final generation = ++_loopGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _loopGeneration ||
          !_controller.hasClients) {
        return;
      }
      _controller.jumpTo(0);
      _queueTravel(generation, forward: true);
    });
  }

  void _queueTravel(int generation, {required bool forward}) {
    if (!mounted || generation != _loopGeneration || !_controller.hasClients) {
      return;
    }
    final maxExtent = _controller.position.maxScrollExtent;
    if (maxExtent <= 0) {
      _loopScheduled = false;
      return;
    }
    final travelDuration = Duration(
      milliseconds: (maxExtent / widget.pixelsPerSecond * 1000).round().clamp(
        300,
        12000,
      ),
    );
    _pauseTimer = Timer(widget.pause, () async {
      _pauseTimer = null;
      if (!mounted ||
          generation != _loopGeneration ||
          !_controller.hasClients) {
        return;
      }
      await _controller.animateTo(
        forward ? _controller.position.maxScrollExtent : 0,
        duration: travelDuration,
        curve: Curves.linear,
      );
      if (!mounted || generation != _loopGeneration) return;
      _queueTravel(generation, forward: !forward);
    });
  }

  @override
  void dispose() {
    _loopGeneration++;
    _pauseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_staticText) {
      return Text(widget.text, style: widget.style, softWrap: true);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_lastWidth != constraints.maxWidth) {
          _lastWidth = constraints.maxWidth;
          _restart();
        }
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
      },
    );
  }
}
