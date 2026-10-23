import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/core/theme/app_theme.dart';
import 'package:paws_log/core/widgets/cat_illustration.dart';

/// A way to *look* at the illustration, not a test.
///
/// Skipped by default: a golden comparison is tied to the machine and the
/// Flutter version that produced it, and this file exists to preview a
/// drawing rather than to guard it. To use it:
///
///     flutter test test/preview/cat_preview_test.dart --update-goldens \
///       --dart-define=PREVIEW=true
///
/// then open `test/preview/cat.png`.
void main() {
  testWidgets('cat', (tester) async {
    tester.view
      ..physicalSize = const Size(900, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(child: SleepingCat(size: 560)),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(SleepingCat),
      matchesGoldenFile('cat.png'),
    );
  }, skip: !const bool.fromEnvironment('PREVIEW'));
}
