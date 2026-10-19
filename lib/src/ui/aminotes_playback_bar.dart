import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../controller/aminotes_controller.dart';
import '../media/voice_notes.dart';
import 'aminotes_strings.dart';

/// A ready-made bar for the voice note playing: play/pause, position you can
/// drag, Delete and Close. Show it while `controller.playback.value` isn't
/// null (the [AminotesToolbar] does this on its own). Optional: build your own
/// on [AminotesController.playback].
class AminotesPlaybackBar extends StatefulWidget {
  const AminotesPlaybackBar({super.key, required this.controller});

  /// The note whose voice note is playing.
  final AminotesController controller;

  @override
  State<AminotesPlaybackBar> createState() => _AminotesPlaybackBarState();
}

class _AminotesPlaybackBarState extends State<AminotesPlaybackBar> {
  // While the thumb is dragged: where it is (seeks once on release).
  double? _dragging;

  AminotesController get _controller => widget.controller;

  static String _format(Duration duration) {
    final seconds = duration.inSeconds % 60;
    return '${duration.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AminotesStrings.of(context);
    const figures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    // Taps here must not take focus from the editor (that closes the keyboard),
    // nor reach the editor's iframe on the web when drawn over it.
    return PointerInterceptor(
      child: ExcludeFocus(
        child: Material(
          color: colors.surfaceContainer,
          child: SizedBox(
            height: 52,
            child: ValueListenableBuilder<AminotesPlayback?>(
              valueListenable: _controller.playback,
              builder: (context, playback, _) {
                if (playback == null) return const SizedBox.shrink();
                final total = playback.duration.inMilliseconds.toDouble();
                final position = (_dragging ?? playback.position.inMilliseconds.toDouble()).clamp(0.0, total);
                return Row(
                  children: [
                    IconButton(
                      tooltip: playback.playing ? strings.pauseVoiceNote : strings.playVoiceNote,
                      icon: Icon(playback.playing ? Icons.pause : Icons.play_arrow),
                      onPressed: playback.playing ? _controller.pauseVoiceNote : _controller.resumeVoiceNote,
                    ),
                    Text(_format(Duration(milliseconds: position.round())), style: figures),
                    Expanded(
                      child: Slider(
                        value: position,
                        max: total > 0 ? total : 1,
                        onChanged: total > 0 ? (value) => setState(() => _dragging = value) : null,
                        onChangeEnd: (value) {
                          setState(() => _dragging = null);
                          _controller.seekVoiceNote(Duration(milliseconds: value.round()));
                        },
                      ),
                    ),
                    Text(_format(playback.duration), style: figures),
                    IconButton(
                      tooltip: strings.deleteVoiceNote,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _controller.deleteVoiceNote,
                    ),
                    IconButton(
                      tooltip: strings.closePlayback,
                      icon: const Icon(Icons.close),
                      onPressed: _controller.stopVoiceNote,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
