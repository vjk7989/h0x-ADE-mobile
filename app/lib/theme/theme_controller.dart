import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'themes.dart';

enum HxThemeMode { system, light, dark }

/// The theme choice, as the desktop keeps it: a mode plus one theme for
/// light and one for dark. "System" picks between them by the OS.
class ThemeSettings {
  const ThemeSettings({
    this.mode = HxThemeMode.system,
    this.light = kDefaultLightTheme,
    this.dark = kDefaultDarkTheme,
  });

  final HxThemeMode mode;
  final String light;
  final String dark;

  ThemeMode get themeMode => switch (mode) {
    HxThemeMode.system => ThemeMode.system,
    HxThemeMode.light => ThemeMode.light,
    HxThemeMode.dark => ThemeMode.dark,
  };

  /// The theme on screen when the OS looks [platform].
  ThemeSpec active(Brightness platform) {
    final isLight = switch (mode) {
      HxThemeMode.system => platform == Brightness.light,
      HxThemeMode.light => true,
      HxThemeMode.dark => false,
    };
    return themeById(isLight ? light : dark);
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings &&
      other.mode == mode &&
      other.light == light &&
      other.dark == dark;

  @override
  int get hashCode => Object.hash(mode, light, dark);
}

/// Set in main() and in tests (`SharedPreferences.setMockInitialValues`).
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider is not overridden'),
);

const _kMode = 'theme.mode';
const _kLight = 'theme.light';
const _kDark = 'theme.dark';

class ThemeController extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() {
    final p = ref.watch(sharedPrefsProvider);
    final mode = HxThemeMode.values.firstWhere(
      (m) => m.name == p.getString(_kMode),
      orElse: () => HxThemeMode.system,
    );
    // A stored id that no longer exists, or sits in the wrong slot, falls
    // back to the default instead of crashing at start-up.
    String slot(String key, bool light, String fallback) {
      final id = p.getString(key);
      if (id != null && isThemeId(id) && themeById(id).isLight == light) {
        return id;
      }
      return fallback;
    }

    return ThemeSettings(
      mode: mode,
      light: slot(_kLight, true, kDefaultLightTheme),
      dark: slot(_kDark, false, kDefaultDarkTheme),
    );
  }

  Future<void> setMode(HxThemeMode mode) async {
    state = ThemeSettings(mode: mode, light: state.light, dark: state.dark);
    await _save();
  }

  /// Picks [id]. It fills the light or the dark slot by its kind. If it is
  /// not the kind on screen now, the mode follows it, so the tap shows.
  Future<void> select(String id, {required Brightness platform}) async {
    final spec = themeById(id);
    final onScreen = state.active(platform).isLight;
    var mode = state.mode;
    if (spec.isLight != onScreen) {
      mode = spec.isLight ? HxThemeMode.light : HxThemeMode.dark;
    }
    state = ThemeSettings(
      mode: mode,
      light: spec.isLight ? id : state.light,
      dark: spec.isLight ? state.dark : id,
    );
    await _save();
  }

  Future<void> _save() async {
    final p = ref.read(sharedPrefsProvider);
    await p.setString(_kMode, state.mode.name);
    await p.setString(_kLight, state.light);
    await p.setString(_kDark, state.dark);
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);

const _splashChannel = MethodChannel('hyperox/splash');

/// Tells Android which splash the next cold start should show (13+): the
/// app's resolved mode, which can differ from the system's. Sent at start-up
/// and whenever the resolved brightness changes. Below 13 the splash follows
/// the system mode (a known limit).
class SplashThemeSync extends StatefulWidget {
  const SplashThemeSync({super.key, required this.child});

  final Widget child;

  @override
  State<SplashThemeSync> createState() => _SplashThemeSyncState();
}

class _SplashThemeSyncState extends State<SplashThemeSync> {
  bool? _light;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final light = Theme.of(context).brightness == Brightness.light;
    if (light == _light) return;
    _light = light;
    _splashChannel
        .invokeMethod<void>('setTheme', {'light': light})
        .catchError((_) {}); // no host (tests, desktop)
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
