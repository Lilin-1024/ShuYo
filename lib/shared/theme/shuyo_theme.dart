import 'package:flutter/material.dart';

import '../shuyo_text_styles.dart';

class ShuYoThemeSpec {
  const ShuYoThemeSpec({
    required this.id,
    required this.name,
    required this.colors,
  });

  final String id;
  final String name;
  final ShuYoColors colors;

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
      textTheme: ShuYoTextStyles.theme.apply(
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
        titleTextStyle: ShuYoTextStyles.headerTitle(color: colors.textPrimary),
        toolbarTextStyle: ShuYoTextStyles.label(color: colors.textPrimary),
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
        titleTextStyle: ShuYoTextStyles.sectionTitle(
          color: colors.textPrimary,
        ),
        contentTextStyle: ShuYoTextStyles.bodyCompact(
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
class ShuYoColors extends ThemeExtension<ShuYoColors> {
  const ShuYoColors({
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
    required this.largeAction,
    required this.onLargeAction,
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
  final Color largeAction;
  final Color onLargeAction;
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
  ShuYoColors copyWith({
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
    Color? largeAction,
    Color? onLargeAction,
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
    return ShuYoColors(
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
      largeAction: largeAction ?? this.largeAction,
      onLargeAction: onLargeAction ?? this.onLargeAction,
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
  ShuYoColors lerp(ThemeExtension<ShuYoColors>? other, double t) {
    if (other is! ShuYoColors) {
      return this;
    }
    return ShuYoColors(
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
      largeAction: Color.lerp(largeAction, other.largeAction, t)!,
      onLargeAction: Color.lerp(onLargeAction, other.onLargeAction, t)!,
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

class ShuYoThemes {
  const ShuYoThemes._();

  static const defaultId = 'paper_light';
  static const systemDarkId = 'default_dark';
  static const systemLightId = defaultId;

  static const all = <ShuYoThemeSpec>[
    ShuYoThemeSpec(
      id: systemDarkId,
      name: '深色',
      colors: ShuYoColors(
        brightness: Brightness.dark,
        background: Color(0xFF0D0D0D),
        surface: Color(0xFF151719),
        surfaceAlt: Color(0xFF1B2025),
        surfaceMuted: Color(0xFF222A31),
        border: Color(0xFF26313A),
        borderStrong: Color(0xFF364651),
        textPrimary: Color(0xFFF0F4F7),
        textSecondary: Color(0xFFD0DAE2),
        textTertiary: Color(0xFF9AA9B4),
        textMuted: Color(0xFF75848E),
        accent: Color(0xFF41AEF2),
        accentAlt: Color(0xFF2994F2),
        accentSoft: Color(0xFF102B3D),
        largeAction: Color(0xFF0678BF),
        onLargeAction: Color(0xFFFFFFFF),
        onAccent: Color(0xFFFFFFFF),
        onAccentSoft: Color(0xFF96D7FF),
        navSelected: Color(0xFFF0F4F7),
        navUnselected: Color(0xFF87949C),
        selectedFill: Color(0xFFF0F4F7),
        onSelectedFill: Color(0xFF0D0D0D),
        chipFill: Color(0xFF151719),
        chipBorder: Color(0xFF303B44),
        listAuthor: Color(0xFF98A4AC),
        detailAuthor: Color(0xFFD0DAE2),
        danger: Color(0xFFE36C61),
        onDanger: Color(0xFFFFFFFF),
        warning: Color(0xFFD6A85A),
        success: Color(0xFF78B76F),
        disabledFill: Color(0xFF252B31),
        inverseSurface: Color(0xFFF0F4F7),
        inverseOnSurface: Color(0xFF0D0D0D),
        scheduleEmptyCell: Color(0xFF333D45),
        scheduleCourseFill: Color(0xFFF0F4F7),
        scheduleCourseText: Color(0xFF17202A),
        scheduleCourseMetaText: Color(0xFF435360),
        schedulePalette: [
          Color(0xFF56B9F3),
          Color(0xFF4EA4F4),
          Color(0xFFE0B867),
          Color(0xFFE68A82),
          Color(0xFFAE98D0),
          Color(0xFF82BBC8),
          Color(0xFF6EC7A6),
          Color(0xFFE29A56),
          Color(0xFF7BA8E8),
          Color(0xFFD889B1),
          Color(0xFF8DC78A),
          Color(0xFFB69BD8),
          Color(0xFF62B7C7),
          Color(0xFFE28B8B),
          Color(0xFF9BB86B),
          Color(0xFFCB9B67),
        ],
      ),
    ),
    ShuYoThemeSpec(
      id: defaultId,
      name: '纸白',
      colors: ShuYoColors(
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
        largeAction: Color(0xFF237A57),
        onLargeAction: Color(0xFFFFFFFF),
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
          Color(0xFF5DBA82),
          Color(0xFF6C96CA),
          Color(0xFFD2A24B),
          Color(0xFFD97B70),
          Color(0xFF9B87C4),
          Color(0xFF65AEA5),
          Color(0xFF6EAFD8),
          Color(0xFFE0A45F),
          Color(0xFFD58FB0),
          Color(0xFF7FBA78),
          Color(0xFFB89ACF),
          Color(0xFF5EA6C0),
          Color(0xFFE08B62),
          Color(0xFF8EA9D5),
          Color(0xFFB0B85C),
          Color(0xFFCA8C83),
        ],
      ),
    ),
    ShuYoThemeSpec(
      id: 'ink_teal',
      name: '墨青',
      colors: ShuYoColors(
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
        largeAction: Color(0xFF58C7B4),
        onLargeAction: Color(0xFF031714),
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
          Color(0xFF69D1C0),
          Color(0xFF7EAEE0),
          Color(0xFFE5B66A),
          Color(0xFFE58A82),
          Color(0xFFB39BD8),
          Color(0xFF96D0A4),
          Color(0xFF84C4E8),
          Color(0xFFE6A65E),
          Color(0xFFE09BC0),
          Color(0xFF9CCB7C),
          Color(0xFFC28FE0),
          Color(0xFF6FC0C5),
          Color(0xFFE58F6D),
          Color(0xFF9AAEE5),
          Color(0xFFC2C86E),
          Color(0xFFD39BA0),
        ],
      ),
    ),
    ShuYoThemeSpec(
      id: 'graphite_coral',
      name: '石墨珊瑚',
      colors: ShuYoColors(
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
        largeAction: Color(0xFFE2624B),
        onLargeAction: Color(0xFFFFFFFF),
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
          Color(0xFFEC7963),
          Color(0xFF84B9C5),
          Color(0xFFE2AF5C),
          Color(0xFFAA95CA),
          Color(0xFF8AC987),
          Color(0xFFD88CA4),
          Color(0xFF78B7D2),
          Color(0xFFE2A45B),
          Color(0xFFE18A72),
          Color(0xFF9AB7DF),
          Color(0xFFB0CC78),
          Color(0xFFC493D7),
          Color(0xFF6FC3B6),
          Color(0xFFED987E),
          Color(0xFFC0AA63),
          Color(0xFF9FA6D4),
        ],
      ),
    ),
    ShuYoThemeSpec(
      id: 'morning_coral',
      name: '晨白珊瑚',
      colors: ShuYoColors(
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
        largeAction: Color(0xFFD85D49),
        onLargeAction: Color(0xFFFFFFFF),
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
          Color(0xFFE27460),
          Color(0xFF6F9FC0),
          Color(0xFFD39B50),
          Color(0xFF9C8CCA),
          Color(0xFF72AA85),
          Color(0xFFD58EA0),
          Color(0xFF6EA8C6),
          Color(0xFFDCA05B),
          Color(0xFFE18A6F),
          Color(0xFF8EA8D1),
          Color(0xFF8DBB72),
          Color(0xFFB48ACD),
          Color(0xFF63B4A5),
          Color(0xFFE69A83),
          Color(0xFFC5A05A),
          Color(0xFFA89BCB),
        ],
      ),
    ),
  ];

  static ShuYoThemeSpec byId(String? id) {
    for (final theme in all) {
      if (theme.id == id) {
        return theme;
      }
    }
    for (final theme in all) {
      if (theme.id == defaultId) {
        return theme;
      }
    }
    return all.first;
  }

  static String systemThemeIdFor(Brightness brightness) {
    return brightness == Brightness.dark ? systemDarkId : systemLightId;
  }
}

extension ShuYoThemeContext on BuildContext {
  ShuYoColors get shuyoColors {
    return Theme.of(this).extension<ShuYoColors>() ??
        ShuYoThemes.byId(ShuYoThemes.defaultId).colors;
  }
}
