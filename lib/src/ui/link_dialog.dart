import 'package:flutter/material.dart';

import 'aminotes_strings.dart';

/// Asks for a URL. Returns the trimmed URL, `''` when [removable] and the user
/// taps Remove, or null when cancelled.
Future<String?> showUrlDialog(
  BuildContext context, {
  required String title,
  String initialUrl = '',
  bool removable = false,
}) {
  // Dialogs are built above the caller's subtree; carry its strings (and any
  // AminotesStringsScope override) along.
  final strings = AminotesStrings.of(context);
  return showDialog<String>(
    context: context,
    builder: (_) => AminotesStringsScope(
      strings: strings,
      child: _UrlDialog(title: title, initialUrl: initialUrl, removable: removable),
    ),
  );
}

// The State owns the controller so it is disposed only after the dialog's
// closing animation, never while the TextField is still on screen.
class _UrlDialog extends StatefulWidget {
  const _UrlDialog({required this.title, required this.initialUrl, required this.removable});

  final String title;
  final String initialUrl;
  final bool removable;

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  late final _controller = TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isNotEmpty) Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AminotesStrings.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        // URLs read left to right, also in an Arabic app.
        textDirection: TextDirection.ltr,
        // The hint is a URL too: keep it left to right.
        decoration: InputDecoration(hintText: strings.linkHint, hintTextDirection: TextDirection.ltr),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        if (widget.removable) TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(strings.removeLink)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.cancel)),
        FilledButton(onPressed: _submit, child: Text(strings.ok)),
      ],
    );
  }
}
