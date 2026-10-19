/// Android/iOS record AAC, which every device plays: nothing to convert.
Future<({String src, String mimeType})?> makePlayableEverywhere(
  String src, {
  bool force = false,
  bool fallback = false,
}) async => null;
