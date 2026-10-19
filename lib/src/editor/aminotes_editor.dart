import 'package:flutter/material.dart';

import '../controller/aminotes_controller.dart';
import '../controller/aminotes_state.dart';
import '../preview/aminotes_preview.dart';
import '../ui/aminotes_strings.dart';
import 'aminotes_theme.dart';

/// The editing area for the note in [controller]. Place it anywhere, at any
/// size: a small note box, a full-screen page, a dialog.
///
/// It only shows the text. Build your own toolbar on [AminotesController]
/// (or use `AminotesToolbar`) and put it where you like, e.g. above the
/// keyboard: when `controller.state.value.focused` is true.
///
/// One controller can be shown by several editors (e.g. a box and a
/// full-screen route on top of it); only the most recently built one displays
/// the note, the others show [inactiveChild].
class AminotesEditor extends StatefulWidget {
  const AminotesEditor({
    super.key,
    required this.controller,
    this.theme,
    this.placeholder,
    this.autofocus = false,
    this.inactiveChild,
    this.autoHeight = false,
    this.minHeight = 48,
    this.maxHeight = double.infinity,
    this.previewWhileLoading = true,
  });

  /// The note to show and edit. One controller can be shown by several
  /// editors in turn (see [inactiveChild]).
  final AminotesController controller;

  /// Text colours, font and padding. Unset values come from the app's [Theme].
  final AminotesTheme? theme;

  /// Shown while the note is empty, e.g. "Write a note…".
  final String? placeholder;

  /// Puts the cursor in the note once it has loaded. On Android and iOS the
  /// keyboard may still need a tap to open: the system only opens it for
  /// a user's touch.
  final bool autofocus;

  /// Shown while another editor displays this controller's note.
  final Widget? inactiveChild;

  /// Sizes the editor to its content, between [minHeight] and [maxHeight]
  /// (it scrolls inside beyond that), instead of filling the space it's given.
  /// For a note box that grows as the user types.
  final bool autoHeight;

  /// With [autoHeight]: the smallest height, even for an empty note.
  final double minHeight;

  /// With [autoHeight]: the largest height; longer notes scroll inside.
  final double maxHeight;

  /// Shows the note (as an `AminotesPreview`) while the editor page loads,
  /// so it never appears blank. Only for notes loaded as JSON.
  final bool previewWhileLoading;

  @override
  State<AminotesEditor> createState() => _AminotesEditorState();
}

class _AminotesEditorState extends State<AminotesEditor> with WidgetsBindingObserver {
  var _lastKeyboardInset = 0.0;

  AminotesController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.attach(this);
    if (widget.autofocus) _controller.ready.then((_) => mounted ? _controller.focus() : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(AminotesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detach(this);
      widget.controller.attach(this);
    }
    _configure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.detach(this);
    super.dispose();
  }

  // The Android back button hides the keyboard but leaves the web editor
  // focused; unfocus it too so toolbars bound to `focused` go away with it.
  @override
  void didChangeMetrics() {
    if (!mounted || _controller.activeEditor.value != this) return;
    final inset = View.of(context).viewInsets.bottom;
    if (_lastKeyboardInset > 0 && inset == 0 && _controller.state.value.focused) _controller.unfocus();
    _lastKeyboardInset = inset;
  }

  void _configure() {
    if (_controller.activeEditor.value != this) return;
    final theme = (widget.theme ?? const AminotesTheme()).resolve(Theme.of(context), Directionality.of(context));
    final strings = AminotesStrings.of(context);
    _controller.configure(
      placeholder: widget.placeholder ?? '',
      direction: Directionality.of(context),
      labels: {'unsupportedBlock': strings.unsupportedBlock, 'voiceNote': strings.voiceNote},
      themeVars: theme.toCssVariables(),
      dark: theme.brightness == Brightness.dark,
      css: theme.css ?? '',
      fonts: theme.fonts,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Object?>(
      valueListenable: _controller.activeEditor,
      builder: (context, active, _) {
        if (active != this) {
          final placeholder = widget.inactiveChild ?? const SizedBox.expand();
          // Keep the box the note's size while another editor shows it.
          return widget.autoHeight ? _sizedToContent(placeholder) : placeholder;
        }
        // This editor just became the active one (e.g. the full-screen route
        // closed): its theme and placeholder apply again.
        WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _configure() : null);
        // A dialog, sheet or route above this one: the page mustn't take its
        // clicks (in a browser it would, being an iframe).
        _controller.hostInteractive = ModalRoute.isCurrentOf(context) ?? true;
        // Inside a scrolling list (e.g. a note box on a long screen) the list
        // takes vertical drags: claim them for the note while it's taller than
        // its box (to scroll it) or being edited (e.g. resizing an image).
        // Always the same widgets around the host: changing them would
        // recreate the view (and reload the web iframe).
        Widget editor = LayoutBuilder(
          builder: (context, constraints) => ValueListenableBuilder<double?>(
            valueListenable: _controller.contentHeight,
            builder: (context, contentHeight, _) => ValueListenableBuilder<AminotesState>(
              valueListenable: _controller.state,
              builder: (context, state, _) {
                final box = widget.autoHeight ? widget.maxHeight : constraints.maxHeight;
                final overflows = contentHeight != null && box.isFinite && contentHeight > box + 1;
                return _controller.buildHost(context, claimVerticalDrags: state.focused || overflows);
              },
            ),
          ),
        );
        if (widget.previewWhileLoading) editor = _withLoadingPreview(editor);
        if (widget.autoHeight) editor = _sizedToContent(editor);
        return editor;
      },
    );
  }

  // Always the same widgets around the host, whatever the note's format:
  // changing them would recreate the editor view, and on the web that reloads
  // the iframe (losing focus mid-typing).
  Widget _withLoadingPreview(Widget editor) {
    return ValueListenableBuilder<AminotesState>(
      valueListenable: _controller.state,
      builder: (context, state, child) {
        final json = state.ready ? null : _controller.knownJson;
        return Stack(
          children: [
            child!,
            if (json != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: AminotesPreview(json: json, theme: widget.theme),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: editor,
    );
  }

  Widget _sizedToContent(Widget editor) {
    return ValueListenableBuilder<double?>(
      valueListenable: _controller.contentHeight,
      builder: (context, height, child) => AnimatedSize(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment.topCenter,
        child: SizedBox(height: (height ?? widget.minHeight).clamp(widget.minHeight, widget.maxHeight), child: child),
      ),
      child: editor,
    );
  }
}
