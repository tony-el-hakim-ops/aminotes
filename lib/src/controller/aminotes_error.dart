import 'package:flutter/foundation.dart';

/// What went wrong, for [AminotesError.kind].
enum AminotesErrorKind {
  /// The note's content couldn't be loaded safely; it's shown read-only and
  /// kept unchanged (see `AminotesState.loadFailed`).
  load,

  /// A recording couldn't start or finish.
  recording,

  /// A voice note couldn't play, or an image file couldn't be read.
  media,

  /// The editor page reported a problem.
  editor,

  /// The device's WebView is too old to run the editor (older than Chrome
  /// 80; e.g. an Android 7 phone that never updated "Android System WebView").
  /// The editor can't open; the note stays visible as a preview. Ask the user
  /// to update Android System WebView from the Play Store.
  webView,
}

/// A problem the package recovered from, reported to `onError` so the host
/// app can log it or tell the user.
@immutable
class AminotesError {
  const AminotesError(this.kind, this.message, [this.error]);

  /// What went wrong.
  final AminotesErrorKind kind;

  /// A description for logs (English, not meant for users).
  final String message;

  /// The underlying exception, if any.
  final Object? error;

  @override
  String toString() => 'AminotesError(${kind.name}): $message';
}
