import 'package:flutter/widgets.dart';

/// Every text the package shows: toolbar tooltips, dialogs, and labels inside
/// the editor. English and Arabic are built in and picked from the app's
/// locale; wrap a subtree in [AminotesStringsScope] to change any of them.
@immutable
class AminotesStrings {
  const AminotesStrings({
    required this.bold,
    required this.italic,
    required this.underline,
    required this.strikethrough,
    required this.inlineCode,
    required this.codeBlock,
    required this.textColor,
    required this.highlight,
    required this.defaultTextColor,
    required this.noHighlight,
    required this.colorNames,
    required this.link,
    required this.addLink,
    required this.editLink,
    required this.removeLink,
    required this.linkHint,
    required this.cancel,
    required this.ok,
    required this.heading,
    required this.bulletList,
    required this.numberedList,
    required this.checklist,
    required this.indent,
    required this.outdent,
    required this.quote,
    required this.divider,
    required this.undo,
    required this.redo,
    required this.hideKeyboard,
    required this.unsupportedBlock,
    required this.voiceNote,
    required this.recordVoiceNote,
    required this.cancelRecording,
    required this.finishRecording,
    required this.microphoneDenied,
    required this.recordingFailed,
    required this.image,
    required this.imageFromGallery,
    required this.imageFromCamera,
    required this.imageFailed,
    required this.insertTable,
    required this.addRowBelow,
    required this.addColumnAfter,
    required this.deleteRow,
    required this.deleteColumn,
    required this.headerRow,
    required this.deleteTable,
    required this.viewImage,
    required this.deleteImage,
    required this.playVoiceNote,
    required this.pauseVoiceNote,
    required this.deleteVoiceNote,
    required this.closePlayback,
    required this.alignImageLeft,
    required this.alignImageCenter,
    required this.alignImageRight,
  });

  final String bold;
  final String italic;
  final String underline;
  final String strikethrough;
  final String inlineCode;
  final String codeBlock;
  final String textColor;
  final String highlight;
  final String defaultTextColor;
  final String noHighlight;

  /// Names for [AminotesPalette] colors, keyed by `#rrggbb`. Other colors use
  /// their hex code.
  final Map<String, String> colorNames;

  final String link;
  final String addLink;
  final String editLink;
  final String removeLink;
  final String linkHint;
  final String cancel;
  final String ok;

  /// "Heading {level}"; `{level}` is replaced.
  final String heading;
  final String bulletList;
  final String numberedList;
  final String checklist;
  final String indent;
  final String outdent;
  final String quote;
  final String divider;
  final String undo;
  final String redo;
  final String hideKeyboard;

  /// Shown inside the note for content this version can't edit;
  /// `{type}` is replaced by its kind (e.g. "callout").
  final String unsupportedBlock;

  /// Spoken label of a voice note, before its duration.
  final String voiceNote;
  final String recordVoiceNote;
  final String cancelRecording;
  final String finishRecording;
  final String microphoneDenied;
  final String recordingFailed;
  final String image;
  final String imageFromGallery;
  final String imageFromCamera;
  final String imageFailed;
  final String insertTable;
  final String addRowBelow;

  /// After the current column in reading order (right of it in English,
  /// left of it in Arabic).
  final String addColumnAfter;
  final String deleteRow;
  final String deleteColumn;
  final String headerRow;
  final String deleteTable;
  final String viewImage;
  final String deleteImage;
  final String playVoiceNote;
  final String pauseVoiceNote;
  final String deleteVoiceNote;
  final String closePlayback;
  final String alignImageLeft;
  final String alignImageCenter;
  final String alignImageRight;

  String headingLevel(int level) => heading.replaceAll('{level}', '$level');

  static const english = AminotesStrings(
    bold: 'Bold',
    italic: 'Italic',
    underline: 'Underline',
    strikethrough: 'Strikethrough',
    inlineCode: 'Inline code',
    codeBlock: 'Code block',
    textColor: 'Text color',
    highlight: 'Highlight',
    defaultTextColor: 'Default color',
    noHighlight: 'No highlight',
    colorNames: {
      '#e53935': 'Red',
      '#fb8c00': 'Orange',
      '#43a047': 'Green',
      '#1e88e5': 'Blue',
      '#8e24aa': 'Purple',
      '#757575': 'Grey',
      '#fff59d': 'Yellow',
      '#c5e1a5': 'Green',
      '#b3e5fc': 'Blue',
      '#f8bbd0': 'Pink',
      '#ffcc80': 'Orange',
      '#e1bee7': 'Purple',
    },
    link: 'Link',
    addLink: 'Add link',
    editLink: 'Edit link',
    removeLink: 'Remove',
    linkHint: 'https://',
    cancel: 'Cancel',
    ok: 'OK',
    heading: 'Heading {level}',
    bulletList: 'Bullet list',
    numberedList: 'Numbered list',
    checklist: 'Checklist',
    indent: 'Indent',
    outdent: 'Outdent',
    quote: 'Quote',
    divider: 'Divider',
    undo: 'Undo',
    redo: 'Redo',
    hideKeyboard: 'Hide keyboard',
    unsupportedBlock: 'Unsupported content ({type}), kept unchanged',
    voiceNote: 'Voice note',
    recordVoiceNote: 'Record voice note',
    cancelRecording: 'Cancel recording',
    finishRecording: 'Done',
    microphoneDenied: 'Allow microphone access to record voice notes.',
    recordingFailed: "Couldn't start recording.",
    image: 'Image',
    imageFromGallery: 'Choose from gallery',
    imageFromCamera: 'Take a photo',
    imageFailed: "Couldn't add the image.",
    insertTable: 'Insert table',
    addRowBelow: 'Add row below',
    addColumnAfter: 'Add column after',
    deleteRow: 'Delete row',
    deleteColumn: 'Delete column',
    headerRow: 'Header row',
    deleteTable: 'Delete table',
    viewImage: 'View image',
    deleteImage: 'Delete image',
    playVoiceNote: 'Play',
    pauseVoiceNote: 'Pause',
    deleteVoiceNote: 'Delete voice note',
    closePlayback: 'Close player',
    alignImageLeft: 'Align left',
    alignImageCenter: 'Center',
    alignImageRight: 'Align right',
  );

  static const arabic = AminotesStrings(
    bold: 'غامق',
    italic: 'مائل',
    underline: 'تسطير',
    strikethrough: 'يتوسطه خط',
    inlineCode: 'رمز برمجي',
    codeBlock: 'كتلة رمز برمجي',
    textColor: 'لون النص',
    highlight: 'تظليل',
    defaultTextColor: 'اللون الافتراضي',
    noHighlight: 'بدون تظليل',
    colorNames: {
      '#e53935': 'أحمر',
      '#fb8c00': 'برتقالي',
      '#43a047': 'أخضر',
      '#1e88e5': 'أزرق',
      '#8e24aa': 'بنفسجي',
      '#757575': 'رمادي',
      '#fff59d': 'أصفر',
      '#c5e1a5': 'أخضر',
      '#b3e5fc': 'أزرق',
      '#f8bbd0': 'وردي',
      '#ffcc80': 'برتقالي',
      '#e1bee7': 'بنفسجي',
    },
    link: 'رابط',
    addLink: 'إضافة رابط',
    editLink: 'تعديل الرابط',
    removeLink: 'إزالة',
    linkHint: 'https://',
    cancel: 'إلغاء',
    ok: 'موافق',
    heading: 'عنوان {level}',
    bulletList: 'قائمة نقطية',
    numberedList: 'قائمة مرقمة',
    checklist: 'قائمة مهام',
    indent: 'زيادة المسافة البادئة',
    outdent: 'إنقاص المسافة البادئة',
    quote: 'اقتباس',
    divider: 'فاصل',
    undo: 'تراجع',
    redo: 'إعادة',
    hideKeyboard: 'إخفاء لوحة المفاتيح',
    unsupportedBlock: 'محتوى غير مدعوم ({type})، محفوظ دون تغيير',
    voiceNote: 'ملاحظة صوتية',
    recordVoiceNote: 'تسجيل ملاحظة صوتية',
    cancelRecording: 'إلغاء التسجيل',
    finishRecording: 'تم',
    microphoneDenied: 'اسمح بالوصول إلى الميكروفون لتسجيل الملاحظات الصوتية.',
    recordingFailed: 'تعذّر بدء التسجيل.',
    image: 'صورة',
    imageFromGallery: 'اختيار من المعرض',
    imageFromCamera: 'التقاط صورة',
    imageFailed: 'تعذّرت إضافة الصورة.',
    insertTable: 'إدراج جدول',
    addRowBelow: 'إضافة صف أسفل',
    addColumnAfter: 'إضافة عمود بعد',
    deleteRow: 'حذف الصف',
    deleteColumn: 'حذف العمود',
    headerRow: 'صف العناوين',
    deleteTable: 'حذف الجدول',
    viewImage: 'عرض الصورة',
    deleteImage: 'حذف الصورة',
    playVoiceNote: 'تشغيل',
    pauseVoiceNote: 'إيقاف مؤقت',
    deleteVoiceNote: 'حذف الملاحظة الصوتية',
    closePlayback: 'إغلاق المشغّل',
    alignImageLeft: 'محاذاة لليسار',
    alignImageCenter: 'توسيط',
    alignImageRight: 'محاذاة لليمين',
  );

  /// The strings for [context]: an [AminotesStringsScope] above it, else
  /// Arabic for an Arabic locale, else English.
  static AminotesStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AminotesStringsScope>();
    if (scope != null) return scope.strings;
    final locale = Localizations.maybeLocaleOf(context);
    return locale?.languageCode == 'ar' ? arabic : english;
  }

  AminotesStrings copyWith({
    String? bold,
    String? italic,
    String? underline,
    String? strikethrough,
    String? inlineCode,
    String? codeBlock,
    String? textColor,
    String? highlight,
    String? defaultTextColor,
    String? noHighlight,
    Map<String, String>? colorNames,
    String? link,
    String? addLink,
    String? editLink,
    String? removeLink,
    String? linkHint,
    String? cancel,
    String? ok,
    String? heading,
    String? bulletList,
    String? numberedList,
    String? checklist,
    String? indent,
    String? outdent,
    String? quote,
    String? divider,
    String? undo,
    String? redo,
    String? hideKeyboard,
    String? unsupportedBlock,
    String? voiceNote,
    String? recordVoiceNote,
    String? cancelRecording,
    String? finishRecording,
    String? microphoneDenied,
    String? recordingFailed,
    String? image,
    String? imageFromGallery,
    String? imageFromCamera,
    String? imageFailed,
    String? insertTable,
    String? addRowBelow,
    String? addColumnAfter,
    String? deleteRow,
    String? deleteColumn,
    String? headerRow,
    String? deleteTable,
    String? viewImage,
    String? deleteImage,
    String? playVoiceNote,
    String? pauseVoiceNote,
    String? deleteVoiceNote,
    String? closePlayback,
    String? alignImageLeft,
    String? alignImageCenter,
    String? alignImageRight,
  }) => AminotesStrings(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strikethrough: strikethrough ?? this.strikethrough,
    inlineCode: inlineCode ?? this.inlineCode,
    codeBlock: codeBlock ?? this.codeBlock,
    textColor: textColor ?? this.textColor,
    highlight: highlight ?? this.highlight,
    defaultTextColor: defaultTextColor ?? this.defaultTextColor,
    noHighlight: noHighlight ?? this.noHighlight,
    colorNames: colorNames ?? this.colorNames,
    link: link ?? this.link,
    addLink: addLink ?? this.addLink,
    editLink: editLink ?? this.editLink,
    removeLink: removeLink ?? this.removeLink,
    linkHint: linkHint ?? this.linkHint,
    cancel: cancel ?? this.cancel,
    ok: ok ?? this.ok,
    heading: heading ?? this.heading,
    bulletList: bulletList ?? this.bulletList,
    numberedList: numberedList ?? this.numberedList,
    checklist: checklist ?? this.checklist,
    indent: indent ?? this.indent,
    outdent: outdent ?? this.outdent,
    quote: quote ?? this.quote,
    divider: divider ?? this.divider,
    undo: undo ?? this.undo,
    redo: redo ?? this.redo,
    hideKeyboard: hideKeyboard ?? this.hideKeyboard,
    unsupportedBlock: unsupportedBlock ?? this.unsupportedBlock,
    voiceNote: voiceNote ?? this.voiceNote,
    recordVoiceNote: recordVoiceNote ?? this.recordVoiceNote,
    cancelRecording: cancelRecording ?? this.cancelRecording,
    finishRecording: finishRecording ?? this.finishRecording,
    microphoneDenied: microphoneDenied ?? this.microphoneDenied,
    recordingFailed: recordingFailed ?? this.recordingFailed,
    image: image ?? this.image,
    imageFromGallery: imageFromGallery ?? this.imageFromGallery,
    imageFromCamera: imageFromCamera ?? this.imageFromCamera,
    imageFailed: imageFailed ?? this.imageFailed,
    insertTable: insertTable ?? this.insertTable,
    addRowBelow: addRowBelow ?? this.addRowBelow,
    addColumnAfter: addColumnAfter ?? this.addColumnAfter,
    deleteRow: deleteRow ?? this.deleteRow,
    deleteColumn: deleteColumn ?? this.deleteColumn,
    headerRow: headerRow ?? this.headerRow,
    deleteTable: deleteTable ?? this.deleteTable,
    viewImage: viewImage ?? this.viewImage,
    deleteImage: deleteImage ?? this.deleteImage,
    playVoiceNote: playVoiceNote ?? this.playVoiceNote,
    pauseVoiceNote: pauseVoiceNote ?? this.pauseVoiceNote,
    deleteVoiceNote: deleteVoiceNote ?? this.deleteVoiceNote,
    closePlayback: closePlayback ?? this.closePlayback,
    alignImageLeft: alignImageLeft ?? this.alignImageLeft,
    alignImageCenter: alignImageCenter ?? this.alignImageCenter,
    alignImageRight: alignImageRight ?? this.alignImageRight,
  );
}

/// Overrides [AminotesStrings] for everything below it, e.g.
/// `AminotesStringsScope(strings: AminotesStrings.english.copyWith(bold: 'Strong'), child: ...)`.
class AminotesStringsScope extends InheritedWidget {
  const AminotesStringsScope({super.key, required this.strings, required super.child});

  final AminotesStrings strings;

  @override
  bool updateShouldNotify(AminotesStringsScope oldWidget) => strings != oldWidget.strings;
}
