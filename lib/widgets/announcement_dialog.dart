import 'package:cqut_helper/model/announcement_model.dart';
import 'package:cqut_helper/widgets/release_notes_markdown.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool?> showAnnouncementDialog({
  required BuildContext context,
  required AnnouncementModel item,
  bool requireAcknowledgement = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: !requireAcknowledgement,
    builder: (context) => AnnouncementDialog(
      item: item,
      requireAcknowledgement: requireAcknowledgement,
    ),
  );
}

class AnnouncementDialog extends StatefulWidget {
  const AnnouncementDialog({
    super.key,
    required this.item,
    this.requireAcknowledgement = false,
  });

  final AnnouncementModel item;
  final bool requireAcknowledgement;

  @override
  State<AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<AnnouncementDialog> {
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.pop(context, true);
  }

  Future<void> _openLink(BuildContext context, String href) async {
    final uri = Uri.tryParse(href);
    try {
      if (uri != null && await launchUrl(uri)) return;
    } catch (_) {
      // Show the same feedback for unavailable handlers and launch failures.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final requireAcknowledgement = widget.requireAcknowledgement;
    return PopScope(
      canPop: !requireAcknowledgement,
      child: AlertDialog(
        constraints: const BoxConstraints(maxWidth: 560),
        scrollable: true,
        title: Text(item.title),
        content: ReleaseNotesMarkdown(
          data: item.contentMarkdown,
          onTapLink: (href) => _openLink(context, href),
        ),
        actions: [
          if (item.linkUrl case final String link when link.isNotEmpty)
            TextButton(
              onPressed: () => _openLink(context, link),
              child: const Text('打开链接'),
            ),
          FilledButton(
            onPressed: _close,
            child: Text(requireAcknowledgement ? '我已知晓' : '关闭'),
          ),
        ],
      ),
    );
  }
}
