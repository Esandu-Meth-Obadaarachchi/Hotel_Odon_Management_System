import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The Odon design system.
///
/// The hotel's mark is ink on white, so the interface is too: chrome is
/// monochrome, and colour is reserved for information (meal plans on the
/// room board, meal counts, money in/out, warnings). If something is coloured,
/// it is telling you something.
///
/// Keep every screen on these tokens. Don't introduce new hex values in a
/// feature file; add them here with a name that says what they mean.

// ── Colour ──────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Surfaces
  static const canvas = Color(0xFFF4F5F3); // page background
  static const surface = Color(0xFFFFFFFF); // cards, sheets, bars
  static const sunken = Color(0xFFECEEEB); // tracks, wells, input fill
  static const hairline = Color(0xFFE2E5E1); // card borders, dividers
  static const hairlineStrong = Color(0xFFCDD1CC);

  // Ink (text + primary actions)
  static const ink = Color(0xFF121614);
  static const ink2 = Color(0xFF4A524D); // secondary text
  static const ink3 = Color(0xFF7F8782); // tertiary text, icons
  static const ink4 = Color(0xFFB3B9B4); // placeholders, disabled

  // Status
  static const success = Color(0xFF2C7A4E);
  static const warning = Color(0xFFB0690F);
  static const danger = Color(0xFFB4291E);
  static const info = Color(0xFF235D78);

  // Soft fills and lines for status surfaces (banners, chips, highlights).
  static const successSoft = Color(0xFFEAF3EE);
  static const successLine = Color(0xFFC3DCCC);
  static const dangerSoft = Color(0xFFFAEDEB);
  static const dangerLine = Color(0xFFEDC6C1);
  static const warningSoft = Color(0xFFF8F0E3);
  static const warningLine = Color(0xFFE8D1AC);
  static const infoSoft = Color(0xFFE9F0F3);
  static const infoLine = Color(0xFFBED1DB);

  // Meal plans (room board + package chips)
  static const fullBoard = Color(0xFF2F6B4D); // palm
  static const halfBoard = Color(0xFF2A5A84); // harbour
  static const bnb = Color(0xFFA86E25); // cinnamon
  static const roomOnly = Color(0xFF3D777B); // sea glass
  static const dinnerOnly = Color(0xFF9C4636); // clay
  static const blocked = Color(0xFF2A302C);

  // Meals
  static const breakfast = Color(0xFFA86E25);
  static const lunch = Color(0xFF2F6B4D);
  static const dinner = Color(0xFF2B3B63);

  /// Soft fill behind a coloured icon or label.
  static Color tint(Color c, [double a = 0.10]) => c.withValues(alpha: a);

  static const packages = <String, Color>{
    'Full Board': fullBoard,
    'Half Board': halfBoard,
    'BnB': bnb,
    'Room Only': roomOnly,
    'Dinner Only': dinnerOnly,
  };

  static Color forPackage(String? p) => packages[p] ?? ink3;
}

// ── Spacing, radii, elevation ───────────────────────────────────────────────

class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Page gutter on phones; widens on tablets/desktop via [AppLayout].
  static const gutter = 16.0;
}

class AppRadius {
  AppRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;

  static const card = BorderRadius.all(Radius.circular(lg));
  static const control = BorderRadius.all(Radius.circular(md));
}

class AppShadow {
  AppShadow._();

  /// Resting card: a hairline does the separating, the shadow just lifts.
  static const card = [
    BoxShadow(color: Color(0x08121614), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A121614), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Floating things: sheets, bars, the segmented thumb.
  static const float = [
    BoxShadow(color: Color(0x14121614), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F121614), blurRadius: 32, offset: Offset(0, 12)),
  ];
}

class AppLayout {
  AppLayout._();
  static const maxContent = 1180.0;
  static const maxForm = 760.0;
  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;
  static double gutter(BuildContext c) =>
      MediaQuery.sizeOf(c).width >= 700 ? 24 : AppSpace.gutter;

  /// Side inset that centres a column of at most [maxWidth] inside slivers.
  static double inset(BuildContext c, [double maxWidth = maxContent]) {
    final w = MediaQuery.sizeOf(c).width;
    final g = gutter(c);
    final centred = (w - maxWidth) / 2;
    return centred > g ? centred : g;
  }

  static EdgeInsets sliverPadding(BuildContext c,
          {double maxWidth = maxContent, double top = 0, double bottom = 0}) {
    final x = inset(c, maxWidth);
    return EdgeInsets.fromLTRB(x, top, x, bottom);
  }
}

// ── Motion ──────────────────────────────────────────────────────────────────

class AppMotion {
  AppMotion._();

  /// Critically damped ease-out: arrives without overshoot.
  static const ease = Cubic(0.22, 1, 0.36, 1);
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);

  static bool reduced(BuildContext c) =>
      MediaQuery.maybeDisableAnimationsOf(c) ?? false;
}

// ── Type ────────────────────────────────────────────────────────────────────

class AppText {
  AppText._();

  static TextStyle _base(double size, FontWeight w,
          {double height = 1.35, double tracking = 0, Color color = AppColors.ink}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: w,
        height: height,
        letterSpacing: tracking,
        color: color,
      );

  /// Page titles. Tight leading and negative tracking at display size.
  static TextStyle get largeTitle =>
      _base(30, FontWeight.w700, height: 1.1, tracking: -0.8);
  static TextStyle get title =>
      _base(20, FontWeight.w700, height: 1.2, tracking: -0.4);
  static TextStyle get headline =>
      _base(16, FontWeight.w600, height: 1.3, tracking: -0.2);
  static TextStyle get body => _base(15, FontWeight.w400, height: 1.45);
  static TextStyle get bodyStrong => _base(15, FontWeight.w600, height: 1.4);
  static TextStyle get callout =>
      _base(14, FontWeight.w500, height: 1.4, color: AppColors.ink2);
  static TextStyle get footnote =>
      _base(13, FontWeight.w500, height: 1.35, color: AppColors.ink3);

  /// Small upper-case label above a group ("GROUND FLOOR").
  static TextStyle get eyebrow => _base(11, FontWeight.w700,
      height: 1.2, tracking: 0.9, color: AppColors.ink3);

  /// Figures that line up when they change (counts, money).
  static TextStyle number(double size,
          {FontWeight weight = FontWeight.w700, Color color = AppColors.ink}) =>
      _base(size, weight, height: 1.05, tracking: size >= 24 ? -0.9 : -0.2, color: color)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

// ── Theme ───────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final textTheme = GoogleFonts.hankenGroteskTextTheme().apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.ink,
      onPrimary: Colors.white,
      primaryContainer: AppColors.sunken,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.ink2,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.sunken,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.info,
      onTertiary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: Color(0xFFFBEAE8),
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.ink2,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surface,
      surfaceContainerHighest: AppColors.sunken,
      outline: AppColors.hairlineStrong,
      outlineVariant: AppColors.hairline,
      shadow: Color(0xFF121614),
      scrim: Color(0x66121614),
      inverseSurface: AppColors.ink,
      onInverseSurface: Colors.white,
      inversePrimary: Colors.white,
      surfaceTint: Colors.transparent,
    );

    final controlShape =
        RoundedRectangleBorder(borderRadius: AppRadius.control);
    final buttonText = AppText.bodyStrong.copyWith(fontSize: 15);

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      highlightColor: AppColors.ink.withValues(alpha: 0.04),
      splashColor: AppColors.ink.withValues(alpha: 0.06),
      hoverColor: AppColors.ink.withValues(alpha: 0.03),
      dividerColor: AppColors.hairline,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        // One spatial model everywhere: pages push in from the right and can
        // be dragged back from the left edge, mid-transition included.
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.ink, size: 22),
        actionsIconTheme: const IconThemeData(color: AppColors.ink, size: 22),
        titleTextStyle: AppText.title.copyWith(fontSize: 19),
        shape: const Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      dividerTheme: const DividerThemeData(
          color: AppColors.hairline, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: AppColors.ink2, size: 22),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.ink2,
        textColor: AppColors.ink,
        titleTextStyle: AppText.bodyStrong,
        subtitleTextStyle: AppText.footnote,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.sunken,
          disabledForegroundColor: AppColors.ink4,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: controlShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.sunken,
          disabledForegroundColor: AppColors.ink4,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: controlShape,
          textStyle: buttonText,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: AppColors.surface,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: const BorderSide(color: AppColors.hairlineStrong),
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(48, 44),
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(44, 44),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 4,
        highlightElevation: 1,
        extendedTextStyle: buttonText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: AppText.callout.copyWith(color: AppColors.ink3),
        floatingLabelStyle: AppText.callout
            .copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
        hintStyle: AppText.callout.copyWith(color: AppColors.ink4),
        helperStyle: AppText.footnote,
        prefixIconColor: AppColors.ink3,
        suffixIconColor: AppColors.ink3,
        border: border(AppColors.hairlineStrong),
        enabledBorder: border(AppColors.hairlineStrong),
        focusedBorder: border(AppColors.ink, 1.5),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 1.5),
        disabledBorder: border(AppColors.hairline),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.ink,
        disabledColor: AppColors.sunken,
        checkmarkColor: Colors.white,
        side: const BorderSide(color: AppColors.hairlineStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: AppText.callout.copyWith(color: AppColors.ink),
        secondaryLabelStyle: AppText.callout.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.ink : AppColors.surface),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? Colors.white : AppColors.ink2),
          side: const WidgetStatePropertyAll(
              BorderSide(color: AppColors.hairlineStrong)),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.ink,
        unselectedLabelColor: AppColors.ink3,
        indicatorColor: AppColors.ink,
        dividerColor: AppColors.hairline,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: AppText.bodyStrong.copyWith(fontSize: 14),
        unselectedLabelStyle: AppText.callout.copyWith(fontSize: 14),
        overlayColor:
            WidgetStatePropertyAll(AppColors.ink.withValues(alpha: 0.04)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: AppText.title,
        contentTextStyle: AppText.body.copyWith(color: AppColors.ink2),
        barrierColor: const Color(0x66121614),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: AppColors.hairlineStrong,
        dragHandleSize: Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppText.callout.copyWith(color: Colors.white),
        actionTextColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x33121614),
        textStyle: AppText.body,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.control,
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
        textStyle: AppText.body,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: AppColors.sunken,
        circularTrackColor: Colors.transparent,
        refreshBackgroundColor: AppColors.surface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.success : AppColors.hairlineStrong),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.ink : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: AppColors.hairlineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.ink : AppColors.hairlineStrong),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.ink,
        inactiveTrackColor: AppColors.sunken,
        thumbColor: AppColors.ink,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.surface,
        headerForegroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        todayBorder: const BorderSide(color: AppColors.ink),
        todayForegroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : AppColors.ink),
        todayBackgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.ink : Colors.transparent),
        dayBackgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.ink : null),
        rangeSelectionBackgroundColor: AppColors.sunken,
        rangePickerBackgroundColor: AppColors.surface,
        rangePickerHeaderBackgroundColor: AppColors.surface,
        rangePickerHeaderForegroundColor: AppColors.ink,
        rangePickerSurfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.surface,
        dialHandColor: AppColors.ink,
        dialBackgroundColor: AppColors.sunken,
        hourMinuteColor: AppColors.sunken,
        dayPeriodColor: AppColors.sunken,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: AppText.footnote.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: AppColors.ink2,
        collapsedIconColor: AppColors.ink3,
        textColor: AppColors.ink,
        collapsedTextColor: AppColors.ink,
        shape: Border(),
        collapsedShape: Border(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.sunken,
        labelTextStyle: WidgetStatePropertyAll(
            AppText.footnote.copyWith(fontSize: 11, color: AppColors.ink)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.ink,
        selectionColor: AppColors.info.withValues(alpha: 0.18),
        selectionHandleColor: AppColors.ink,
      ),
    );
  }
}
