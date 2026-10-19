import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../controller/aminotes_controller.dart';
import 'aminotes_strings.dart';

/// A ready-made bar for a voice note being recorded: pulsing dot, elapsed
/// time, input level, Cancel and Done. Show it while
/// `controller.recording.value` isn't null (the [AminotesToolbar] does this on
/// its own). Optional: build your own on [AminotesController.recording].
class AminotesRecordingBar extends StatefulWidget {
  const AminotesRecordingBar({super.key, required this.controller});

  /// The note being recorded into.
  final AminotesController controller;

  @override
  State<AminotesRecordingBar> createState() => _AminotesRecordingBarState();
}

class _AminotesRecordingBarState extends State<AminotesRecordingBar> with SingleTickerProviderStateMixin {
  late final Timer _ticker;
  late final AnimationController _pulse;
  StreamSubscription<double>? _levels;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
    _levels = widget.controller.recording.value?.levels().listen(
      // dBFS: about -60 (silence) to 0 (loudest) → 0..1.
      (db) => setState(() => _level = ((db + 60) / 60).clamp(0, 1)),
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    _pulse.dispose();
    _levels?.cancel();
    super.dispose();
  }

  static String _format(Duration duration) {
    final seconds = duration.inSeconds % 60;
    return '${duration.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AminotesStrings.of(context);
    final elapsed = widget.controller.recording.value?.elapsed ?? Duration.zero;
    // Taps here must not take focus from the editor (that closes the keyboard),
    // nor reach the editor's iframe on the web when drawn over it.
    return PointerInterceptor(
      child: ExcludeFocus(
        child: Material(
          color: colors.surfaceContainer,
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                IconButton(
                  tooltip: strings.cancelRecording,
                  icon: const Icon(Icons.close),
                  onPressed: widget.controller.cancelVoiceNote,
                ),
                FadeTransition(
                  opacity: _pulse,
                  child: Icon(Icons.fiber_manual_record, color: colors.error, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  _format(elapsed),
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _level,
                      minHeight: 6,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: widget.controller.finishVoiceNote,
                  icon: const Icon(Icons.check),
                  label: Text(strings.finishRecording),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
