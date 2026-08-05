// Smoke test mínimo del árbol de widgets.
//
// El template por defecto de Flutter referenciaba `MyApp` y un contador que no
// existen en esta app (la raíz real es `GymProApp`, que requiere ProviderScope +
// init async de Firebase/Supabase y no es apta para un pump directo). Este test
// verifica que el framework de test funciona y que un árbol básico se construye.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('El árbol de widgets básico se construye', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('GymPro'))),
      ),
    );

    expect(find.text('GymPro'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
