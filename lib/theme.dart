import 'package:flutter/material.dart';

import 'models/models.dart';

/// Yumuşak ve sade palet. Ferahlık; açık zemin, ince kenarlık ve %10'luk soluk
/// simge/etiket zeminleriyle sağlanır. Yazı ve düğmede kullanılan tonlar ise
/// şantiyede güneş altında da okunacak koyulukta tutuldu (beyaz zemin üzerinde
/// kontrast ≥ 4:1; etiketlerde eski paletten düşük değil).
class AppColors {
  const AppColors._();

  static const brand = Color(0xFFCC5D18);
  static const brandDark = Color(0xFFF59A55);
  static const ink = Color(0xFF1F2A35);
  static const green = Color(0xFF23834F);
  static const red = Color(0xFFCF4136);
  static const amber = Color(0xFFA4680A);
  static const blue = Color(0xFF2C72C0);
  static const purple = Color(0xFF7352C4);
  static const teal = Color(0xFF13806F);
  static const grey = Color(0xFF6A7480);

  /// Geriye dönük uyumluluk (eski ekran kodu için).
  static const orange = brand;

  static Color forKind(ListingKind kind) => switch (kind) {
        ListingKind.yuk => brand,
        ListingKind.makine => blue,
        ListingKind.malzeme => green,
        ListingKind.personel => purple,
        ListingKind.sicil => teal,
      };
}

IconData kindIcon(ListingKind kind) => switch (kind) {
      ListingKind.yuk => Icons.local_shipping_rounded,
      ListingKind.makine => Icons.construction_rounded,
      ListingKind.malzeme => Icons.inventory_2_rounded,
      ListingKind.personel => Icons.work_rounded,
      ListingKind.sicil => Icons.engineering_rounded,
    };

IconData machineIcon(MachineType t) => switch (t) {
      MachineType.silindir ||
      MachineType.tandemSilindir ||
      MachineType.lastikliSilindir => Icons.compress_rounded,
      MachineType.greyder => Icons.agriculture_rounded,
      MachineType.ekskavator ||
      MachineType.miniEkskavator => Icons.precision_manufacturing_rounded,
      MachineType.finiser || MachineType.asfaltKesici => Icons.add_road_rounded,
      MachineType.loder ||
      MachineType.paletliLoder ||
      MachineType.miniYukleyici ||
      MachineType.teleskopik => Icons.front_loader,
      MachineType.bekoloder => Icons.construction_rounded,
      MachineType.dozer || MachineType.skrayper => Icons.landslide_rounded,
      MachineType.vinc ||
      MachineType.kuleVinc ||
      MachineType.paletliVinc => Icons.crop_rotate_rounded,
      MachineType.kamyon ||
      MachineType.cekici ||
      MachineType.suTankeri ||
      MachineType.silobas ||
      MachineType.betonMikser => Icons.local_shipping_rounded,
      MachineType.platform => Icons.elevator_rounded,
      MachineType.forklift => Icons.warehouse_rounded,
      MachineType.betonPompa => Icons.water_drop_rounded,
      MachineType.kazik || MachineType.delici => Icons.vertical_align_bottom_rounded,
      MachineType.kirmaEleme => Icons.grain_rounded,
      MachineType.kompresor || MachineType.jenerator => Icons.bolt_rounded,
      MachineType.diger => Icons.handyman_rounded,
    };

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final brand = isDark ? AppColors.brandDark : AppColors.brand;
  final background = isDark ? const Color(0xFF12171C) : const Color(0xFFF8F9FB);
  final surface = isDark ? const Color(0xFF1A2027) : Colors.white;
  final border = isDark ? const Color(0xFF2C343D) : const Color(0xFFEBEEF2);
  final text = isDark ? const Color(0xFFE8EBEF) : AppColors.ink;
  final muted = isDark ? const Color(0xFF9FA9B4) : const Color(0xFF66717E);
  // Koyu temada vurgu rengi açık olduğundan üzerindeki yazı koyu olmalı (beyaz okunmaz).
  final onBrand = isDark ? const Color(0xFF1E1408) : Colors.white;

  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: brightness).copyWith(
    primary: brand,
    onPrimary: onBrand,
    surface: surface,
    onSurface: text,
    onSurfaceVariant: muted,
    outline: border,
    outlineVariant: border,
    error: AppColors.red,
  );

  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );

  final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);

  return base.copyWith(
    scaffoldBackgroundColor: background,
    dividerColor: border,
    dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    appBarTheme: AppBarThemeData(
      backgroundColor: background,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border)),
    ),
    listTileTheme: ListTileThemeData(iconColor: muted, contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: muted.withValues(alpha: 0.8)),
      border: inputBorder(border),
      enabledBorder: inputBorder(border),
      focusedBorder: inputBorder(brand, 1.6),
      errorBorder: inputBorder(AppColors.red),
      focusedErrorBorder: inputBorder(AppColors.red, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: onBrand,
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        minimumSize: const Size(64, 50),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: brand, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: brand, foregroundColor: onBrand),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: brand.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? text : muted,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: brand.withValues(alpha: 0.10),
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: text, fontWeight: FontWeight.w500, fontSize: 13.5),
      showCheckmark: false,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: brand,
      unselectedLabelColor: muted,
      indicatorColor: brand,
      dividerColor: border,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: brand.withValues(alpha: 0.10),
        selectedForegroundColor: text,
        side: BorderSide(color: border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: brand),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onBrand : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? brand : null),
    ),
  );
}
