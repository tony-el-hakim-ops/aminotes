import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How the note text looks inside the editor.
///
/// The editing area is a web page, so it can't use Flutter widgets or
/// TextStyles; these values are sent to it as CSS. Anything left null is taken
/// from the app's Material [Theme] by [AminotesTheme.resolve].
@immutable
class AminotesTheme {
  const AminotesTheme({
    this.brightness,
    this.backgroundColor,
    this.textColor,
    this.mutedTextColor,
    this.accentColor,
    this.accentContainerColor,
    this.onAccentContainerColor,
    this.surfaceColor,
    this.borderColor,
    this.codeBackgroundColor,
    this.selectionColor,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
    this.padding,
    this.fonts = const [],
    this.css,
  });

  /// Light or dark (form controls such as checkboxes follow it).
  final Brightness? brightness;

  /// Behind the text. Defaults to transparent so the host app's own
  /// background (the note box, the page) shows through.
  final Color? backgroundColor;

  /// Body text.
  final Color? textColor;

  /// Placeholder, quotes, completed checklist items, list bullets.
  final Color? mutedTextColor;

  /// Caret, links, quote bar, checkboxes, selection outline.
  final Color? accentColor;

  /// Voice note pill background and text.
  final Color? accentContainerColor;

  /// Text and icons on [accentContainerColor] (voice note pills).
  final Color? onAccentContainerColor;

  /// Table header cells.
  final Color? surfaceColor;

  /// Table borders and dividers.
  final Color? borderColor;

  /// Behind inline code and code blocks.
  final Color? codeBackgroundColor;

  /// Behind selected text.
  final Color? selectionColor;

  /// The font: one of [fonts] (e.g. your brand font), or one installed on the
  /// device (e.g. `'sans-serif'`).
  final String? fontFamily;

  /// In logical pixels, like Flutter font sizes.
  final double? fontSize;

  /// Line height as a multiple of [fontSize].
  final double? lineHeight;

  /// Space between the editor's edges and the text. [EdgeInsetsDirectional]
  /// follows the app's text direction.
  final EdgeInsetsGeometry? padding;

  /// Font files from your app's assets for the editor to use, e.g. your brand
  /// font. Name the family in [fontFamily]. Use the same family name as in
  /// your pubspec `fonts:` so `AminotesPreview` (plain Flutter) matches.
  final List<AminotesFont> fonts;

  /// Extra CSS for the note's content, applied after the package's own styles
  /// so it can change anything the other settings don't: heading sizes,
  /// spacing, checkbox shape, the voice note pill… See "Styling with CSS" in
  /// the README for the elements you can target. Doesn't affect
  /// `AminotesPreview`.
  final String? css;

  /// Fills every unset value from [theme]; [direction] resolves directional
  /// padding.
  AminotesTheme resolve(ThemeData theme, [TextDirection direction = TextDirection.ltr]) {
    final colors = theme.colorScheme;
    return AminotesTheme(
      brightness: brightness ?? theme.brightness,
      backgroundColor: backgroundColor ?? Colors.transparent,
      textColor: textColor ?? colors.onSurface,
      mutedTextColor: mutedTextColor ?? colors.onSurfaceVariant,
      accentColor: accentColor ?? colors.primary,
      accentContainerColor: accentContainerColor ?? colors.primaryContainer,
      onAccentContainerColor: onAccentContainerColor ?? colors.onPrimaryContainer,
      surfaceColor: surfaceColor ?? colors.surfaceContainerHighest,
      borderColor: borderColor ?? colors.outlineVariant,
      codeBackgroundColor: codeBackgroundColor ?? colors.surfaceContainerHigh,
      selectionColor: selectionColor ?? colors.primary.withValues(alpha: 0.25),
      fontFamily: fontFamily,
      fontSize: fontSize ?? theme.textTheme.bodyLarge?.fontSize ?? 16,
      lineHeight: lineHeight ?? 1.5,
      padding: (padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)).resolve(direction),
      fonts: fonts,
      css: css,
    );
  }

  /// The CSS custom properties the editor page reads (see tiptap/webview/editor.css).
  Map<String, String> toCssVariables() {
    final pad = (padding ?? EdgeInsets.zero).resolve(TextDirection.ltr);
    return {
      '--bg': ?_css(backgroundColor),
      '--text': ?_css(textColor),
      '--muted': ?_css(mutedTextColor),
      '--primary': ?_css(accentColor),
      '--primary-container': ?_css(accentContainerColor),
      '--on-primary-container': ?_css(onAccentContainerColor),
      '--surface': ?_css(surfaceColor),
      '--border': ?_css(borderColor),
      '--code-bg': ?_css(codeBackgroundColor),
      '--selection': ?_css(selectionColor),
      if (fontFamily != null) '--font-family': "'${fontFamily!.replaceAll("'", '')}', sans-serif",
      if (fontSize != null) '--font-size': '${fontSize}px',
      if (lineHeight != null) '--line-height': '$lineHeight',
      if (padding != null) ...{
        '--pad-top': '${pad.top}px',
        '--pad-right': '${pad.right}px',
        '--pad-bottom': '${pad.bottom}px',
        '--pad-left': '${pad.left}px',
      },
    };
  }

  static String? _css(Color? color) {
    if (color == null) return null;
    int channel(double value) => (value * 255).round().clamp(0, 255);
    return 'rgba(${channel(color.r)}, ${channel(color.g)}, ${channel(color.b)}, ${color.a.toStringAsFixed(3)})';
  }

  @override
  bool operator ==(Object other) =>
      other is AminotesTheme &&
      other.brightness == brightness &&
      other.backgroundColor == backgroundColor &&
      other.textColor == textColor &&
      other.mutedTextColor == mutedTextColor &&
      other.accentColor == accentColor &&
      other.accentContainerColor == accentContainerColor &&
      other.onAccentContainerColor == onAccentContainerColor &&
      other.surfaceColor == surfaceColor &&
      other.borderColor == borderColor &&
      other.codeBackgroundColor == codeBackgroundColor &&
      other.selectionColor == selectionColor &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.padding == padding &&
      listEquals(other.fonts, fonts) &&
      other.css == css;

  @override
  int get hashCode => Object.hash(
    brightness,
    backgroundColor,
    textColor,
    mutedTextColor,
    accentColor,
    accentContainerColor,
    onAccentContainerColor,
    surfaceColor,
    borderColor,
    codeBackgroundColor,
    selectionColor,
    fontFamily,
    fontSize,
    lineHeight,
    padding,
    Object.hashAll(fonts),
    css,
  );
}

/// A font file from the app's assets, for [AminotesTheme.fonts].
///
/// ```dart
/// AminotesTheme(
///   fontFamily: 'Poppins',
///   fonts: [
///     AminotesFont('Poppins', 'assets/fonts/Poppins-Regular.ttf'),
///     AminotesFont('Poppins', 'assets/fonts/Poppins-Bold.ttf', weight: FontWeight.w700),
///   ],
/// )
/// ```
///
/// Without a bold (or italic) file, the browser draws a slanted or thickened
/// version of the regular one.
@immutable
class AminotesFont {
  const AminotesFont(this.family, this.asset, {this.weight = FontWeight.w400, this.style = FontStyle.normal});

  /// The name to use in [AminotesTheme.fontFamily].
  final String family;

  /// The asset path, as declared in your pubspec (`.ttf`, `.otf`, `.woff`
  /// or `.woff2`).
  final String asset;

  /// The weight this file draws.
  final FontWeight weight;

  /// Normal or italic.
  final FontStyle style;

  @override
  bool operator ==(Object other) =>
      other is AminotesFont &&
      other.family == family &&
      other.asset == asset &&
      other.weight == weight &&
      other.style == style;

  @override
  int get hashCode => Object.hash(family, asset, weight, style);
}
