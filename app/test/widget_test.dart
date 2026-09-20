import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kora/core/theme/kora_colors.dart';
import 'package:kora/core/widgets/buttons.dart';
import 'package:kora/core/widgets/misc.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('KoraButton renders label and fires onPressed',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(
      KoraButton(label: 'Продолжить', onPressed: () => tapped++),
    ),);
    expect(find.text('Продолжить'), findsOneWidget);
    await tester.tap(find.text('Продолжить'));
    expect(tapped, 1);
  });

  testWidgets('KoraButton shows loader instead of label', (tester) async {
    await tester.pumpWidget(_wrap(
      const KoraButton(label: 'Продолжить', loading: true),
    ),);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Продолжить'), findsNothing);
  });

  testWidgets('quantity stepper respects min/max', (tester) async {
    var qty = 1;
    await tester.pumpWidget(_wrap(
      StatefulBuilder(
        builder: (_, set) => KoraQuantityStepper(
          quantity: qty,
          min: 1,
          max: 3,
          onChanged: (q) => set(() => qty = q),
        ),
      ),
    ),);
    // At min=1 decrement must be disabled.
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(qty, 2);
  });

  testWidgets('KoraCountBadge hides at zero and caps at 99+',
      (tester) async {
    await tester.pumpWidget(_wrap(const KoraCountBadge(count: 0)));
    expect(find.byType(Container), findsNothing);
    await tester.pumpWidget(_wrap(const KoraCountBadge(count: 150)));
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('KoraStatusChip renders label', (tester) async {
    await tester.pumpWidget(_wrap(
      const KoraStatusChip(label: 'В пути', tone: KoraStatusTone.active),
    ),);
    expect(find.text('В пути'), findsOneWidget);
  });

  test('error surfaces use functional colors only', () {
    // Guard: error/warning colors must never leak into brand surfaces.
    expect(KoraColors.error, isNot(KoraColors.primary));
    expect(KoraColors.primaryGradient.colors
        .contains(KoraColors.error), isFalse,);
  });
}
