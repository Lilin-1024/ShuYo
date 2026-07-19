import 'package:flutter/material.dart';

import '../lehu_text_styles.dart';

class LehuThemeSpec {
  const LehuThemeSpec({
    required this.id,
    required this.name,
    required this.colors,
  });

  final String id;
  final String name;
  final LehuColors colors;

  List<Color> get previewColors => [
        colors.background,
        colors.textPrimary,
        colors.accent,
      ];

  ThemeData themeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: colors.brightness,
    ).copyWith(
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.accentAlt,
      onSecondary: colors.onAccent,
      error: colors.danger,
      onError: colors.onDanger,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.surfaceMuted,
      outline: colors.borderStrong,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      extensions: [colors],
      textTheme: LehuTextStyles.theme.apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: LehuTextStyles.headerTitle(color: colors.textPrimary),
        toolbarTextStyle: LehuTextStyles.label(color: colors.textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.background,
        selectedItemColor: colors.navSelected,
        unselectedItemColor: colors.navUnselected,
        type: BottomNavigationBarType.fixed,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
      ),
      iconTheme: IconThemeData(color: colors.textSecondary),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.accent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.disabledFill,
          disabledForegroundColor: colors.textMuted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        labelStyle: TextStyle(color: colors.textTertiary),
        hintStyle: TextStyle(color: colors.textMuted),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.accent, width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: LehuTextStyles.sectionTitle(
          color: colors.textPrimary,
        ),
        contentTextStyle: LehuTextStyles.bodyCompact(
          color: colors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.inverseSurface,
        contentTextStyle: TextStyle(color: colors.inverseOnSurface),
      ),
    );
  }
}

@immutable
class LehuColors extends ThemeExtension<LehuColors> {
  const LehuColors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.accent,
    required this.accentAlt,
    required this.accentSoft,
    required this.onAccent,
    required this.onAccentSoft,
    required this.navSelected,
    required this.navUnselected,
    required this.selectedFill,
    required this.onSelectedFill,
    required this.chipFill,
    required this.chipBorder,
    required this.listAuthor,
    required this.detailAuthor,
    required this.danger,
    required this.onDanger,
    required this.warning,
    required this.success,
    required this.disabledFill,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.scheduleEmptyCell,
    required this.scheduleCourseFill,
    required this.scheduleCourseText,
    required this.scheduleCourseMetaText,
    required this.schedulePalette,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textMuted;
  final Color accent;
  final Color accentAlt;
  final Color accentSoft;
  final Color onAccent;
  final Color onAccentSoft;
  final Color navSelected;
  final Color navUnselected;
  final Color selectedFill;
  final Color onSelectedFill;
  final Color chipFill;
  final Color chipBorder;
  final Color listAuthor;
  final Color detailAuthor;
  final Color danger;
  final Color onDanger;
  final Color warning;
  final Color success;
  final Color disabledFill;
  final Color inverseSurface;
  final Color inverseOnSurface;
  final Color scheduleEmptyCell;
  final Color scheduleCourseFill;
  final Color scheduleCourseText;
  final Color scheduleCourseMetaText;
  final List<Color> schedulePalette;

  @override
  LehuColors copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceMuted,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textMuted,
    Color? accent,
    Color? accentAlt,
    Color? accentSoft,
    Color? onAccent,
    Color? onAccentSoft,
    Color? navSelected,
    Color? navUnselected,
    Color? selectedFill,
    Color? onSelectedFill,
    Color? chipFill,
    Color? chipBorder,
    Color? listAuthor,
    Color? detailAuthor,
    Color? danger,
    Color? onDanger,
    Color? warning,
    Color? success,
    Color? disabledFill,
    Color? inverseSurface,
    Color? inverseOnSurface,
    Color? scheduleEmptyCell,
    Color? scheduleCourseFill,
    Color? scheduleCourseText,
    Color? scheduleCourseMetaText,
    List<Color>? schedulePalette,
  }) {
    return LehuColors(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentAlt: accentAlt ?? this.accentAlt,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      onAccentSoft: onAccentSoft ?? this.onAccentSoft,
      navSelected: navSelected ?? this.navSelected,
      navUnselected: navUnselected ?? this.navUnselected,
      selectedFill: selectedFill ?? this.selectedFill,
      onSelectedFill: onSelectedFill ?? this.onSelectedFill,
      chipFill: chipFill ?? this.chipFill,
      chipBorder: chipBorder ?? this.chipBorder,
      listAuthor: listAuthor ?? this.listAuthor,
      detailAuthor: detailAuthor ?? this.detailAuthor,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      disabledFill: disabledFill ?? this.disabledFill,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      inverseOnSurface: inverseOnSurface ?? this.inverseOnSurface,
      scheduleEmptyCell: scheduleEmptyCell ?? this.scheduleEmptyCell,
      scheduleCourseFill: scheduleCourseFill ?? this.scheduleCourseFill,
      scheduleCourseText: scheduleCourseText ?? this.scheduleCourseText,
      scheduleCourseMetaText:
          scheduleCourseMetaText ?? this.scheduleCourseMetaText,
      schedulePalette: schedulePalette ?? this.schedulePalette,
    );
  }

  @override
  LehuColors lerp(ThemeExtension<LehuColors>? other, double t) {
    if (other is! LehuColors) {
      return this;
    }
    return LehuColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentAlt: Color.lerp(accentAlt, other.accentAlt, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      onAccentSoft: Color.lerp(onAccentSoft, other.onAccentSoft, t)!,
      navSelected: Color.lerp(navSelected, other.navSelected, t)!,
      navUnselected: Color.lerp(navUnselected, other.navUnselected, t)!,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t)!,
      onSelectedFill: Color.lerp(onSelectedFill, other.onSelectedFill, t)!,
      chipFill: Color.lerp(chipFill, other.chipFill, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      listAuthor: Color.lerp(listAuthor, other.listAuthor, t)!,
      detailAuthor: Color.lerp(detailAuthor, other.detailAuthor, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      disabledFill: Color.lerp(disabledFill, other.disabledFill, t)!,
      inverseSurface: Color.lerp(inverseSurface, other.inverseSurface, t)!,
      inverseOnSurface:
          Color.lerp(inverseOnSurface, other.inverseOnSurface, t)!,
      scheduleEmptyCell:
          Color.lerp(scheduleEmptyCell, other.scheduleEmptyCell, t)!,
      scheduleCourseFill:
          Color.lerp(scheduleCourseFill, other.scheduleCourseFill, t)!,
      scheduleCourseText:
          Color.lerp(scheduleCourseText, other.scheduleCourseText, t)!,
      scheduleCourseMetaText:
          Color.lerp(scheduleCourseMetaText, other.scheduleCourseMetaText, t)!,
      schedulePalette: _lerpPalette(schedulePalette, other.schedulePalette, t),
    );
  }

  static List<Color> _lerpPalette(
    List<Color> a,
    List<Color> b,
    double t,
  ) {
    final length = a.length < b.length ? a.length : b.length;
    return [
      for (var index = 0; index < length; index++)
        Color.lerp(a[index], b[index], t)!,
    ];
  }
}

class LehuThemes {
  const LehuThemes._();

  static const defaultId = 'default_dark';

  static const all = <LehuThemeSpec>[
    LehuThemeSpec(
      id: defaultId,
      name: '默认深色',
      colors: LehuColors(
        brightness: Brightness.dark,
        background: Color(0xFF000000),
        surface: Color(0xFF111111),
        surfaceAlt: Color(0xFF171717),
        surfaceMuted: Color(0xFF1C1C1C),
        border: Color(0xFF202020),
        borderStrong: Color(0xFF303030),
        textPrimary: Color(0xFFEDEDED),
        textSecondary: Color(0xFFD6D6D6),
        textTertiary: Color(0xFF9B9B9B),
        textMuted: Color(0xFF777777),
        accent: Color(0xFF66E0A3),
        accentAlt: Color(0xFF7EB6FF),
        accentSoft: Color(0xFF143625),
        onAccent: Color(0xFF07140D),
        onAccentSoft: Color(0xFF66E0A3),
        navSelected: Color(0xFFFFFFFF),
        navUnselected: Color(0xFF8A8A8A),
        selectedFill: Color(0xFFEDEDED),
        onSelectedFill: Color(0xFF000000),
        chipFill: Color(0xFF171717),
        chipBorder: Color(0xFF303030),
        listAuthor: Color(0xFF9B9B9B),
        detailAuthor: Color(0xFFD6D6D6),
        danger: Color(0xFFE85B52),
        onDanger: Color(0xFFFFFFFF),
        warning: Color(0xFFE0B45B),
        success: Color(0xFF7ED38F),
        disabledFill: Color(0xFF2A2A2A),
        inverseSurface: Color(0xFFEDEDED),
        inverseOnSurface: Color(0xFF111111),
        scheduleEmptyCell: Color(0xFF555555),
        scheduleCourseFill: Color(0xFFFFFFFF),
        scheduleCourseText: Color(0xFF242424),
        scheduleCourseMetaText: Color(0xFF393939),
        schedulePalette: [
          Color(0xFF4FCB8C),
          Color(0xFF6CA8E8),
          Color(0xFFE7B94F),
          Color(0xFFE77770),
          Color(0xFF9E89CF),
          Color(0xFF69B9B1),
        ],
      ),
    ),
    LehuThemeSpec(
      id: 'paper_light',
      name: '纸白',
      colors: LehuColors(
        brightness: Brightness.light,
        background: Color(0xFFF7F7F4),
        surface: Color(0xFFFFFFFF),
        surfaceAlt: Color(0xFFF0F1EE),
        surfaceMuted: Color(0xFFE8EAE6),
        border: Color(0xFFE1E2DE),
        borderStrong: Color(0xFFD1D4CF),
        textPrimary: Color(0xFF191B1B),
        textSecondary: Color(0xFF3E4542),
        textTertiary: Color(0xFF69736E),
        textMuted: Color(0xFF929A95),
        accent: Color(0xFF237A57),
        accentAlt: Color(0xFF496F9F),
        accentSoft: Color(0xFFDDEDE5),
        onAccent: Color(0xFFFFFFFF),
        onAccentSoft: Color(0xFF14543B),
        navSelected: Color(0xFF111313),
        navUnselected: Color(0xFF77817B),
        selectedFill: Color(0xFF202624),
        onSelectedFill: Color(0xFFFFFFFF),
        chipFill: Color(0xFFF1F2EF),
        chipBorder: Color(0xFFDDE0DA),
        listAuthor: Color(0xFF6F7772),
        detailAuthor: Color(0xFF39423D),
        danger: Color(0xFFC74339),
        onDanger: Color(0xFFFFFFFF),
        warning: Color(0xFFB27622),
        success: Color(0xFF2C8A58),
        disabledFill: Color(0xFFE2E4DF),
        inverseSurface: Color(0xFF202624),
        inverseOnSurface: Color(0xFFFFFFFF),
        scheduleEmptyCell: Color(0xFFE6E8E3),
        scheduleCourseFill: Color(0xFFFFFFFF),
        scheduleCourseText: Color(0xFF202423),
        scheduleCourseMetaText: Color(0xFF59625D),
        schedulePalette: [
          Color(0xFF4A9D70),
          Color(0xFF5B83B4),
          Color(0xFFC4953D),
          Color(0xFFC86C5F),
          Color(0xFF8C78B6),
          Color(0xFF559E96),
        ],
      ),
    ),
    LehuThemeSpec(
      id: 'ink_teal',
      name: '墨青',
      colors: LehuColors(
        brightness: Brightness.dark,
        background: Color(0xFF071210),
        surface: Color(0xFF101C19),
        surfaceAlt: Color(0xFF14231F),
        surfaceMuted: Color(0xFF1B2C27),
        border: Color(0xFF223730),
        borderStrong: Color(0xFF345046),
        textPrimary: Color(0xFFEAF2EE),
        textSecondary: Color(0xFFC6D5CE),
        textTertiary: Color(0xFF91A39B),
        textMuted: Color(0xFF6E8178),
        accent: Color(0xFF58C7B4),
        accentAlt: Color(0xFFD9A955),
        accentSoft: Color(0xFF173D37),
        onAccent: Color(0xFF031714),
        onAccentSoft: Color(0xFF85DFD0),
        navSelected: Color(0xFFEAF2EE),
        navUnselected: Color(0xFF7F938A),
        selectedFill: Color(0xFFEAF2EE),
        onSelectedFill: Color(0xFF071210),
        chipFill: Color(0xFF101C19),
        chipBorder: Color(0xFF345046),
        listAuthor: Color(0xFF90A29A),
        detailAuthor: Color(0xFFC6D5CE),
        danger: Color(0xFFE36C61),
        onDanger: Color(0xFFFFFFFF),
        warning: Color(0xFFD9A955),
        success: Color(0xFF76D199),
        disabledFill: Color(0xFF22302C),
        inverseSurface: Color(0xFFEAF2EE),
        inverseOnSurface: Color(0xFF071210),
        scheduleEmptyCell: Color(0xFF2B4039),
        scheduleCourseFill: Color(0xFFEAF2EE),
        scheduleCourseText: Color(0xFF14231F),
        scheduleCourseMetaText: Color(0xFF3B524A),
        schedulePalette: [
          Color(0xFF58C7B4),
          Color(0xFF6CA2D8),
          Color(0xFFD9A955),
          Color(0xFFD87872),
          Color(0xFFA891D1),
          Color(0xFF86C596),
        ],
      ),
    ),
    LehuThemeSpec(
      id: 'graphite_coral',
      name: '石墨珊瑚',
      colors: LehuColors(
        brightness: Brightness.dark,
        background: Color(0xFF101010),
        surface: Color(0xFF181818),
        surfaceAlt: Color(0xFF202020),
        surfaceMuted: Color(0xFF292929),
        border: Color(0xFF2E2E2E),
        borderStrong: Color(0xFF414141),
        textPrimary: Color(0xFFF0EFED),
        textSecondary: Color(0xFFD2D0CD),
        textTertiary: Color(0xFFA19D98),
        textMuted: Color(0xFF7F7A75),
        accent: Color(0xFFE2624B),
        accentAlt: Color(0xFF78B7A6),
        accentSoft: Color(0xFF3B201B),
        onAccent: Color(0xFFFFFFFF),
        onAccentSoft: Color(0xFFFFA190),
        navSelected: Color(0xFFF0EFED),
        navUnselected: Color(0xFF8E8984),
        selectedFill: Color(0xFFF0EFED),
        onSelectedFill: Color(0xFF101010),
        chipFill: Color(0xFF181818),
        chipBorder: Color(0xFF414141),
        listAuthor: Color(0xFF9D9893),
        detailAuthor: Color(0xFFD2D0CD),
        danger: Color(0xFFE2624B),
        onDanger: Color(0xFFFFFFFF),
        warning: Color(0xFFD7A04B),
        success: Color(0xFF78B76F),
        disabledFill: Color(0xFF2D2D2D),
        inverseSurface: Color(0xFFF0EFED),
        inverseOnSurface: Color(0xFF101010),
        scheduleEmptyCell: Color(0xFF4A4743),
        scheduleCourseFill: Color(0xFFF4F0EC),
        scheduleCourseText: Color(0xFF24201D),
        scheduleCourseMetaText: Color(0xFF5B524B),
        schedulePalette: [
          Color(0xFFE2624B),
          Color(0xFF78A9B7),
          Color(0xFFD7A04B),
          Color(0xFF9F88BF),
          Color(0xFF78B76F),
          Color(0xFFC77D92),
        ],
      ),
    ),
    LehuThemeSpec(
      id: 'morning_coral',
      name: '晨白珊瑚',
      colors: LehuColors(
        brightness: Brightness.light,
        background: Color(0xFFFCF8F5),
        surface: Color(0xFFFFFFFF),
        surfaceAlt: Color(0xFFF4EFEB),
        surfaceMuted: Color(0xFFEDE5DF),
        border: Color(0xFFE4DAD3),
        borderStrong: Color(0xFFD2C4BA),
        textPrimary: Color(0xFF24201F),
        textSecondary: Color(0xFF514A45),
        textTertiary: Color(0xFF7B7068),
        textMuted: Color(0xFF9B9189),
        accent: Color(0xFFD85D49),
        accentAlt: Color(0xFF438C7C),
        accentSoft: Color(0xFFF8DED8),
        onAccent: Color(0xFFFFFFFF),
        onAccentSoft: Color(0xFF8F3225),
        navSelected: Color(0xFF24201F),
        navUnselected: Color(0xFF877D75),
        selectedFill: Color(0xFF2A2523),
        onSelectedFill: Color(0xFFFFFFFF),
        chipFill: Color(0xFFF4EFEB),
        chipBorder: Color(0xFFE2D7CE),
        listAuthor: Color(0xFF786F68),
        detailAuthor: Color(0xFF514A45),
        danger: Color(0xFFC74339),
        onDanger: Color(0xFFFFFFFF),
        warning: Color(0xFFAD7627),
        success: Color(0xFF438C58),
        disabledFill: Color(0xFFE8DFD8),
        inverseSurface: Color(0xFF2A2523),
        inverseOnSurface: Color(0xFFFFFFFF),
        scheduleEmptyCell: Color(0xFFECE2DA),
        scheduleCourseFill: Color(0xFFFFFFFF),
        scheduleCourseText: Color(0xFF24201F),
        scheduleCourseMetaText: Color(0xFF665D56),
        schedulePalette: [
          Color(0xFFD85D49),
          Color(0xFF5587A8),
          Color(0xFFBE8940),
          Color(0xFF8C7DB2),
          Color(0xFF57936C),
          Color(0xFFC77D8F),
        ],
      ),
    ),
  ];

  static LehuThemeSpec byId(String? id) {
    for (final theme in all) {
      if (theme.id == id) {
        return theme;
      }
    }
    return all.first;
  }
}

extension LehuThemeContext on BuildContext {
  LehuColors get lehuColors {
    return Theme.of(this).extension<LehuColors>() ??
        LehuThemes.all.first.colors;
  }
}
