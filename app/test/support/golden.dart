import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Mock frame sizes in dp (design/tokens.md section 6).
enum Frame {
  phone(Size(360, 800)),
  tablet(Size(840, 900));

  const Frame(this.size);
  final Size size;
}

/// Pumps [child] in a [frame] at [textScale], light or dark, with
/// device pixel ratio 1 so a golden is 1 px per dp. Goldens are generated
/// on ubuntu only (the app-goldens workflow).
Future<void> pumpGolden(
  WidgetTester tester,
  Widget child, {
  Frame frame = Frame.phone,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = frame.size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1F62D0),
    brightness: brightness,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: scheme, fontFamily: 'Geist'),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
