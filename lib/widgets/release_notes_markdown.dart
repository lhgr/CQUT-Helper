import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

enum ReleaseCalloutType { note, tip, important, warning, caution }

@immutable
class ReleaseNoteSegment {
  final String markdown;
  final ReleaseCalloutType? calloutType;

  const ReleaseNoteSegment({required this.markdown, this.calloutType});

  bool get isCallout => calloutType != null;
}

List<ReleaseNoteSegment> parseReleaseNoteSegments(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final segments = <ReleaseNoteSegment>[];
  final normalLines = <String>[];
  String? fenceCharacter;
  var fenceLength = 0;

  void flushNormal() {
    if (normalLines.any((line) => line.trim().isNotEmpty)) {
      segments.add(ReleaseNoteSegment(markdown: normalLines.join('\n')));
    }
    normalLines.clear();
  }

  for (var index = 0; index < lines.length;) {
    final line = lines[index];
    final fenceMatch = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;
      if (fenceCharacter == null) {
        fenceCharacter = marker[0];
        fenceLength = marker.length;
      } else if (marker[0] == fenceCharacter && marker.length >= fenceLength) {
        fenceCharacter = null;
        fenceLength = 0;
      }
      normalLines.add(line);
      index++;
      continue;
    }

    final alertMatch = fenceCharacter == null
        ? RegExp(
            r'^\s*>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$',
            caseSensitive: false,
          ).firstMatch(line)
        : null;
    if (alertMatch == null) {
      normalLines.add(line);
      index++;
      continue;
    }

    flushNormal();
    final type = ReleaseCalloutType.values.firstWhere(
      (value) => value.name == alertMatch.group(1)!.toLowerCase(),
    );
    index++;
    final calloutLines = <String>[];
    while (index < lines.length) {
      final quoted = RegExp(r'^\s*>\s?(.*)$').firstMatch(lines[index]);
      if (quoted == null) break;
      calloutLines.add(quoted.group(1) ?? '');
      index++;
    }
    segments.add(
      ReleaseNoteSegment(markdown: calloutLines.join('\n'), calloutType: type),
    );
  }
  flushNormal();
  return segments;
}

String formatReleaseNotesMarkdown(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final buffer = StringBuffer();
  var inFence = false;
  String? fenceCharacter;
  var fenceLength = 0;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final fenceMatch = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;
      if (!inFence) {
        inFence = true;
        fenceCharacter = marker[0];
        fenceLength = marker.length;
      } else if (marker[0] == fenceCharacter && marker.length >= fenceLength) {
        inFence = false;
        fenceCharacter = null;
        fenceLength = 0;
      }
      buffer.write(line);
    } else if (!inFence && line.isNotEmpty && !line.endsWith('  ')) {
      buffer
        ..write(line)
        ..write('  ');
    } else {
      buffer.write(line);
    }
    if (index != lines.length - 1) buffer.write('\n');
  }
  return buffer.toString();
}

bool isAnimatedReleaseImage(Uri uri) => uri.path.toLowerCase().endsWith('.gif');

class ReleaseNotesMarkdown extends StatelessWidget {
  final String data;
  final ValueChanged<String>? onTapLink;

  const ReleaseNotesMarkdown({super.key, required this.data, this.onTapLink});

  @override
  Widget build(BuildContext context) {
    final segments = parseReleaseNoteSegments(data);
    if (segments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < segments.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          if (segments[index].isCallout)
            _ReleaseCallout(
              segment: segments[index],
              markdownBuilder: (value) => _buildMarkdown(context, value),
            )
          else
            _buildMarkdown(context, segments[index].markdown),
        ],
      ],
    );
  }

  Widget _buildMarkdown(BuildContext context, String markdown) {
    return MarkdownBody(
      data: formatReleaseNotesMarkdown(markdown),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
      inlineSyntaxes: [_ReleaseHighlightSyntax(), _ReleaseTagSyntax()],
      builders: {
        'release-highlight': _ReleaseHighlightBuilder(),
        'release-tag': _ReleaseTagBuilder(),
      },
      imageBuilder: (uri, title, alt) =>
          _ReleaseImage(uri: uri, title: title, alt: alt),
      onTapLink: (text, href, title) {
        if (href != null && href.isNotEmpty) onTapLink?.call(href);
      },
    );
  }
}

class _ReleaseHighlightSyntax extends md.InlineSyntax {
  _ReleaseHighlightSyntax()
    : super(
        r'\{\{(danger|warning|success|info|accent|muted)\s*:\s*([^{}\n]+?)\}\}',
        startCharacter: 123,
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('release-highlight', match.group(2)!);
    element.attributes['kind'] = match.group(1)!.toLowerCase();
    parser.addNode(element);
    return true;
  }
}

class _ReleaseTagSyntax extends md.InlineSyntax {
  _ReleaseTagSyntax()
    : super(
        r'\[\[(NEW|FIX|OPTIMIZE|BREAKING|BETA)\]\]',
        startCharacter: 91,
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.empty('release-tag');
    element.attributes['kind'] = match.group(1)!.toUpperCase();
    parser.addNode(element);
    return true;
  }
}

class _ReleaseHighlightBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final kind = element.attributes['kind'] ?? 'accent';
    return Text(
      element.textContent,
      style:
          (parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style)
              .copyWith(
                color: _semanticColor(context, kind),
                fontWeight: FontWeight.w700,
              ),
    );
  }
}

class _ReleaseTagBuilder extends MarkdownElementBuilder {
  static const labels = {
    'NEW': '新增',
    'FIX': '修复',
    'OPTIMIZE': '优化',
    'BREAKING': '重大调整',
    'BETA': '测试',
  };

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final kind = element.attributes['kind'] ?? 'NEW';
    final color = _semanticColor(context, switch (kind) {
      'FIX' || 'BREAKING' => 'danger',
      'OPTIMIZE' => 'success',
      'BETA' => 'warning',
      _ => 'info',
    });
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        labels[kind] ?? kind,
        style:
            (parentStyle ??
                    preferredStyle ??
                    DefaultTextStyle.of(context).style)
                .copyWith(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
      ),
    );
  }
}

class _ReleaseCallout extends StatelessWidget {
  final ReleaseNoteSegment segment;
  final Widget Function(String markdown) markdownBuilder;

  const _ReleaseCallout({required this.segment, required this.markdownBuilder});

  @override
  Widget build(BuildContext context) {
    final type = segment.calloutType!;
    final (label, icon, kind) = switch (type) {
      ReleaseCalloutType.note => ('说明', Icons.info_outline, 'info'),
      ReleaseCalloutType.tip => ('建议', Icons.lightbulb_outline, 'success'),
      ReleaseCalloutType.important => (
        '重要',
        Icons.priority_high_rounded,
        'accent',
      ),
      ReleaseCalloutType.warning => (
        '注意',
        Icons.warning_amber_rounded,
        'warning',
      ),
      ReleaseCalloutType.caution => (
        '警告',
        Icons.error_outline_rounded,
        'danger',
      ),
    };
    final color = _semanticColor(context, kind);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (segment.markdown.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            markdownBuilder(segment.markdown),
          ],
        ],
      ),
    );
  }
}

class _ReleaseImage extends StatelessWidget {
  final Uri uri;
  final String? title;
  final String? alt;

  const _ReleaseImage({required this.uri, this.title, this.alt});

  @override
  Widget build(BuildContext context) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const _ReleaseImageError(message: '不支持的图片地址');
    }
    final url = uri.toString();
    final caption = (title?.trim().isNotEmpty ?? false)
        ? title!.trim()
        : (alt?.trim() ?? '');
    final isAnimated = isAnimatedReleaseImage(uri);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _showPreview(context, url, caption),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 96,
                      maxHeight: 320,
                    ),
                    child: Image.network(
                      url,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const SizedBox(
                              height: 160,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                      errorBuilder: (context, error, stackTrace) =>
                          const _ReleaseImageError(message: '图片加载失败'),
                    ),
                  ),
                  if (isAnimated)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'GIF',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showPreview(BuildContext context, String url, String caption) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const _ReleaseImageError(message: '图片加载失败'),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filled(
                tooltip: '关闭预览',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
            if (caption.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseImageError extends StatelessWidget {
  final String message;

  const _ReleaseImageError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined),
          const SizedBox(width: 8),
          Text(message),
        ],
      ),
    );
  }
}

Color _semanticColor(BuildContext context, String kind) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (kind) {
    'danger' => Theme.of(context).colorScheme.error,
    'warning' => dark ? Colors.orange.shade300 : Colors.orange.shade800,
    'success' => dark ? Colors.green.shade300 : Colors.green.shade700,
    'info' => dark ? Colors.lightBlue.shade300 : Colors.blue.shade700,
    'muted' => Theme.of(context).colorScheme.onSurfaceVariant,
    _ => Theme.of(context).colorScheme.primary,
  };
}
