import 'package:flutter/material.dart';

/// Tasarım token'ları (2026-09-06 arayüz yenilemesi).
///
/// Kaynak: onaylı mockup — kâğıt zemin, mürekkep metin, tek mavi (yazı-logodan),
/// koyu temada simsiyah değil çok koyu lacivert. Gölge YOK (fotoğraf hariç),
/// yazı IBM Plex Sans; birim/formül/meta satırları IBM Plex Mono.
///
/// Eski alan adları (bgPrimary, textSecondary, radiusMd, shadowSm…) bilerek
/// korunuyor: ekranlar aynı adlarla yeni değerleri alıyor.
class AppTheme {
  // ── Yazı tipleri ──
  static const String fontSans = 'IBMPlexSans';
  static const String fontMono = 'IBMPlexMono';
  /// Yalnız f(x) işareti için (italik).
  static const String fontSerif = 'IBMPlexSerif';

  // ── Marka ──
  /// Beyaz üstünde okunur mavi: düğme, bağlantı, imleç, f(x) işareti.
  static const Color primary = Color(0xFF2A74B0);
  static const Color primaryDark = Color(0xFF1F5C8F);
  /// Koyu temanın mavisi (aynı ailenin açık tonu).
  static const Color primaryLight = Color(0xFF8CC3EE);
  static const Color primaryLighter = Color(0xFFE6F1F9);
  /// Yazı-logonun gök mavisi; tint ve vurgular için.
  static const Color sky = Color(0xFF60A8D8);
  /// Öğretmenin kalemi — YALNIZ çizim katmanı ve hata vurgusu.
  static const Color pen = Color(0xFFD9433B);

  // ── Açık tema ──
  static const Color bgPrimary = Color(0xFFFFFFFF);   // yüzey (kart, alan)
  static const Color bgSecondary = Color(0xFFFBFBF8); // kâğıt (scaffold)
  static const Color bgTertiary = Color(0xFFF1F2EF);  // hafif dolgu
  static const Color textPrimary = Color(0xFF1B2027);
  static const Color textSecondary = Color(0xFF5B6470);
  static const Color textMuted = Color(0xFF98A0AA);
  static const Color border = Color(0xFFDEE2E6);
  static const Color borderLight = Color(0xFFECEEF0);
  static const Color tint = Color(0x2460A8D8);        // sky %14

  // ── Koyu tema (lacivert) ──
  static const Color bgPrimaryDark = Color(0xFF151C2E);
  static const Color bgSecondaryDark = Color(0xFF0E1422);
  static const Color bgTertiaryDark = Color(0xFF1C2538);
  static const Color textPrimaryDark = Color(0xFFE6EAF2);
  static const Color textSecondaryDark = Color(0xFFA7B1C4);
  static const Color textMutedDark = Color(0xFF6E7A94);
  static const Color borderDark = Color(0xFF26314A);
  static const Color borderLightDark = Color(0xFF1F283A);
  static const Color tintDark = Color(0x297DB8E8);    // %16
  static const Color penDark = Color(0xFFF0645C);

  // ── Durum renkleri (sessiz) ──
  static const Color success = Color(0xFF2F855A);
  static const Color warning = Color(0xFFB7791F);
  static const Color danger = Color(0xFFC9403A);
  static const Color successDark = Color(0xFF6CC496);
  static const Color warningDark = Color(0xFFE0B25A);

  // ── Sohbet balonları ──
  static const Color userBubbleBg = Color(0xFFEEF5FB);
  static const Color aiBubbleBg = Color(0xFFFFFFFF);
  static const Color userBubbleBgDark = Color(0xFF1B2842);
  static const Color aiBubbleBgDark = Color(0xFF151C2E);

  // ── Köşeler ──
  static const double radiusSm = 8.0;   // küçük öğe, görsel
  static const double radiusMd = 12.0;  // alan, kart, düğme
  static const double radiusLg = 16.0;  // composer
  static const double radiusXl = 20.0;  // alt sayfa

  // ── Gölgeler: yok. Fotoğraf gibi fiziksel nesneler [shadowPhoto] kullanır. ──
  static List<BoxShadow> get shadowSm => const [];
  static List<BoxShadow> get shadowMd => const [];
  static List<BoxShadow> get shadowLg => const [];
  static List<BoxShadow> get shadowPhoto => [
        BoxShadow(
          color: Colors.black.withOpacity(0.14),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.10),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// Mono meta satırı (eyebrow): "Soru · Çoktan seçmeli", "Düşündü · 142 kelime".
  static TextStyle mono({
    double fontSize = 12,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: fontMono,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        paper: bgSecondary,
        surface: bgPrimary,
        fill: bgTertiary,
        ink: textPrimary,
        ink2: textSecondary,
        ink3: textMuted,
        line: border,
        blue: primary,
        onBlue: Colors.white,
        tintColor: tint,
        red: danger,
      );

  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        paper: bgSecondaryDark,
        surface: bgPrimaryDark,
        fill: bgTertiaryDark,
        ink: textPrimaryDark,
        ink2: textSecondaryDark,
        ink3: textMutedDark,
        line: borderDark,
        blue: primaryLight,
        onBlue: const Color(0xFF0F1A24),
        tintColor: tintDark,
        red: penDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color paper,
    required Color surface,
    required Color fill,
    required Color ink,
    required Color ink2,
    required Color ink3,
    required Color line,
    required Color blue,
    required Color onBlue,
    required Color tintColor,
    required Color red,
  }) {
    final isDark = brightness == Brightness.dark;
    OutlineInputBorder kenar(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: c, width: w),
        );
    final govde = TextStyle(fontFamily: fontSans, color: ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontSans,
      primaryColor: blue,
      scaffoldBackgroundColor: paper,
      canvasColor: surface,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: blue,
        onPrimary: onBlue,
        secondary: sky,
        onSecondary: ink,
        surface: surface,
        onSurface: ink,
        error: red,
        onError: Colors.white,
        outline: line,
        surfaceContainerHighest: fill,
        onSurfaceVariant: ink2,
      ),
      textTheme: TextTheme(
        displaySmall: govde.copyWith(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.2),
        headlineSmall: govde.copyWith(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: -0.2, height: 1.25),
        titleLarge: govde.copyWith(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
        titleMedium: govde.copyWith(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4),
        bodyLarge: govde.copyWith(fontSize: 15, height: 1.5),
        bodyMedium: govde.copyWith(fontSize: 13.5, height: 1.5),
        bodySmall: govde.copyWith(fontSize: 12, height: 1.4, color: ink2),
        labelLarge: govde.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500),
        labelMedium: govde.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: ink2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: govde.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        iconTheme: IconThemeData(color: ink, size: 22),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: kenar(line),
        enabledBorder: kenar(line),
        focusedBorder: kenar(blue, 1.5),
        errorBorder: kenar(red),
        focusedErrorBorder: kenar(red, 1.5),
        hintStyle: govde.copyWith(color: ink3, fontSize: 14),
        labelStyle: govde.copyWith(color: ink2, fontSize: 14),
        helperStyle: govde.copyWith(color: ink3, fontSize: 12),
        errorStyle: govde.copyWith(color: red, fontSize: 12),
        floatingLabelBehavior: FloatingLabelBehavior.never,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: onBlue,
          disabledBackgroundColor: line,
          disabledForegroundColor: ink3,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: govde.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: onBlue,
          disabledBackgroundColor: line,
          disabledForegroundColor: ink3,
          minimumSize: const Size(0, 38),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: govde.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: line),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: govde.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blue,
          textStyle: govde.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink2),
      ),
      cardTheme: CardTheme(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: line),
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? fill : ink,
        contentTextStyle: govde.copyWith(color: isDark ? ink : paper, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        behavior: SnackBarBehavior.floating,
        actionTextColor: isDark ? blue : sky,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        titleTextStyle: govde.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
        contentTextStyle: govde.copyWith(fontSize: 14, height: 1.5, color: ink2),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: ink2,
        textColor: ink,
        titleTextStyle: govde.copyWith(fontSize: 14.5),
        subtitleTextStyle: govde.copyWith(fontSize: 12.5, color: ink2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? paper : ink3),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? ink : line),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? blue : Colors.transparent),
        checkColor: WidgetStateProperty.all(onBlue),
        side: BorderSide(color: ink3, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? blue : ink3),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: blue,
        inactiveTrackColor: line,
        thumbColor: blue,
        overlayColor: tintColor,
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: blue),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: govde.copyWith(fontSize: 14),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: line),
        ),
      ),
      extensions: [
        MaarifxColors(
          blue: blue,
          onBlue: onBlue,
          tint: tintColor,
          warn: isDark ? warningDark : warning,
          ok: isDark ? successDark : success,
          pen: isDark ? penDark : pen,
          fill: fill,
        ),
      ],
    );
  }
}

/// Tema uzantısı: parlaklığa göre değişen ama ColorScheme'de yeri olmayan renkler.
class MaarifxColors extends ThemeExtension<MaarifxColors> {
  final Color blue;
  final Color onBlue;
  final Color tint;
  final Color warn;
  final Color ok;
  final Color pen;
  final Color fill;

  const MaarifxColors({
    required this.blue,
    required this.onBlue,
    required this.tint,
    required this.warn,
    required this.ok,
    required this.pen,
    required this.fill,
  });

  @override
  MaarifxColors copyWith({
    Color? blue,
    Color? onBlue,
    Color? tint,
    Color? warn,
    Color? ok,
    Color? pen,
    Color? fill,
  }) =>
      MaarifxColors(
        blue: blue ?? this.blue,
        onBlue: onBlue ?? this.onBlue,
        tint: tint ?? this.tint,
        warn: warn ?? this.warn,
        ok: ok ?? this.ok,
        pen: pen ?? this.pen,
        fill: fill ?? this.fill,
      );

  @override
  MaarifxColors lerp(ThemeExtension<MaarifxColors>? other, double t) {
    if (other is! MaarifxColors) return this;
    return MaarifxColors(
      blue: Color.lerp(blue, other.blue, t)!,
      onBlue: Color.lerp(onBlue, other.onBlue, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      pen: Color.lerp(pen, other.pen, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
    );
  }
}

/// Türkçe'ye uygun BÜYÜK HARF: Dart'ın toUpperCase'i i→I yapar ("SEÇMELI").
String trBuyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

// Tema-duyarlı kısayollar. Eski adlar korunuyor; yenileri altta.
extension ThemeColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  MaarifxColors get _mx =>
      Theme.of(this).extension<MaarifxColors>() ??
      const MaarifxColors(
        blue: AppTheme.primary,
        onBlue: Colors.white,
        tint: AppTheme.tint,
        warn: AppTheme.warning,
        ok: AppTheme.success,
        pen: AppTheme.pen,
        fill: AppTheme.bgTertiary,
      );

  Color get bgPrimary =>
      isDarkMode ? AppTheme.bgPrimaryDark : AppTheme.bgPrimary;
  Color get bgSecondary =>
      isDarkMode ? AppTheme.bgSecondaryDark : AppTheme.bgSecondary;
  Color get bgTertiary =>
      isDarkMode ? AppTheme.bgTertiaryDark : AppTheme.bgTertiary;
  Color get textPrimary =>
      isDarkMode ? AppTheme.textPrimaryDark : AppTheme.textPrimary;
  Color get textSecondary =>
      isDarkMode ? AppTheme.textSecondaryDark : AppTheme.textSecondary;
  Color get textMuted =>
      isDarkMode ? AppTheme.textMutedDark : AppTheme.textMuted;
  Color get borderColor =>
      isDarkMode ? AppTheme.borderDark : AppTheme.border;
  Color get userBubbleBg =>
      isDarkMode ? AppTheme.userBubbleBgDark : AppTheme.userBubbleBg;
  Color get aiBubbleBg =>
      isDarkMode ? AppTheme.aiBubbleBgDark : AppTheme.aiBubbleBg;

  /// Marka mavisi (açıkta koyu, koyuda açık ton).
  Color get blue => _mx.blue;
  Color get onBlue => _mx.onBlue;
  /// Gök mavisi tint (seçili satır, kullanıcı vurgusu).
  Color get tint => _mx.tint;
  Color get warn => _mx.warn;
  Color get ok => _mx.ok;
  Color get pen => _mx.pen;

  /// Yazı-logo: temaya göre açık/koyu sürüm.
  String get wordmarkAsset => isDarkMode
      ? 'assets/images/MaarifxyaziKoyu.png'
      : 'assets/images/Maarifxyazi.png';

  /// Mono meta satırı stili.
  TextStyle mono({double fontSize = 12, Color? color, FontWeight fontWeight = FontWeight.w400}) =>
      AppTheme.mono(fontSize: fontSize, color: color ?? textMuted, fontWeight: fontWeight);

  /// Büyük harfli mono etiket: "HESAP", "SORU · ÇOKTAN SEÇMELİ".
  TextStyle get eyebrow =>
      AppTheme.mono(fontSize: 10.5, color: textMuted, letterSpacing: 0.9);
}
