import 'package:cqut_helper/widgets/release_notes_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses GitHub-style alert blocks without changing fenced code', () {
    const source = '''
普通内容

> [!WARNING]
> 升级前请先同步数据
> **该操作不可撤销**

```text
> [!CAUTION]
> 这只是代码示例
```
''';

    final segments = parseReleaseNoteSegments(source);

    expect(segments, hasLength(3));
    expect(segments[0].isCallout, isFalse);
    expect(segments[1].calloutType, ReleaseCalloutType.warning);
    expect(segments[1].markdown, contains('升级前请先同步数据'));
    expect(segments[2].isCallout, isFalse);
    expect(segments[2].markdown, contains('[!CAUTION]'));
  });

  test('preserves fenced-code contents while formatting normal lines', () {
    const source = '第一行\n```text\ncode\n```';

    final formatted = formatReleaseNotesMarkdown(source);

    expect(formatted, '第一行  \n```text\ncode\n```');
  });

  test('detects GIF addresses case-insensitively', () {
    expect(
      isAnimatedReleaseImage(Uri.parse('https://example.com/demo.GIF')),
      isTrue,
    );
    expect(
      isAnimatedReleaseImage(Uri.parse('https://example.com/image.png')),
      isFalse,
    );
  });

  testWidgets('renders semantic highlights, tags and callouts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReleaseNotesMarkdown(
              data: '''
[[NEW]] 新增功能

{{danger:停止支持旧版本}}

> [!CAUTION]
> 操作前请备份数据
''',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('新增'), findsOneWidget);
    expect(find.text('停止支持旧版本'), findsOneWidget);
    expect(find.text('警告'), findsOneWidget);
    expect(find.text('操作前请备份数据'), findsOneWidget);

    final highlighted = tester.widget<Text>(find.text('停止支持旧版本'));
    expect(highlighted.style?.color, isNotNull);
    expect(highlighted.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('opens links and rejects unsupported image schemes', (
    tester,
  ) async {
    String? openedUrl;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReleaseNotesMarkdown(
            data:
                '[项目主页](https://example.com)\n\n![图片](ftp://example.com/a.png)',
            onTapLink: (url) => openedUrl = url,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('项目主页'));
    expect(openedUrl, 'https://example.com');
    expect(find.text('不支持的图片地址'), findsOneWidget);
  });
}
