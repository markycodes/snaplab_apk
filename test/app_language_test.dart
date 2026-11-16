import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/app_language.dart';

void main() {
  tearDown(() {
    appLanguageNotifier.value = AppLanguage.english;
  });

  testWidgets('localized text updates when the app language changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const material.MaterialApp(
        home: material.Scaffold(
          body: Text(
            'Make it yours',
            style: material.TextStyle(
              fontFamily: 'DancingScript',
              fontSize: 24,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Make it yours'), findsOneWidget);
    final heading = tester.widget<material.Text>(find.text('Make it yours'));
    expect(heading.style?.fontFamily, 'DancingScript');

    appLanguageNotifier.value = AppLanguage.tagalog;
    await tester.pump();

    expect(find.text('Gawin itong iyo'), findsOneWidget);
    expect(find.text('Make it yours'), findsNothing);
  });

  testWidgets('long body copy keeps its normal readable font', (tester) async {
    const bodyCopy =
        'This longer instruction remains in the normal readable font.';
    await tester.pumpWidget(
      const material.MaterialApp(home: material.Scaffold(body: Text(bodyCopy))),
    );

    final body = tester.widget<material.Text>(find.text(bodyCopy));
    expect(body.style?.fontFamily, isNot('DancingScript'));
  });

  testWidgets('short interactive labels stay in the readable font', (
    tester,
  ) async {
    await tester.pumpWidget(
      const material.MaterialApp(
        home: material.Scaffold(body: Text('Save photo')),
      ),
    );

    final label = tester.widget<material.Text>(find.text('Save photo'));
    expect(label.style?.fontFamily, isNot('DancingScript'));
  });

  test('Tagalog translations preserve unknown and dynamic content', () {
    expect(
      translateAppText('INSERTED ₱20 / ₱20', AppLanguage.tagalog),
      'NAILAGAY NA ₱20 / ₱20',
    );
    expect(
      translateAppText('PHOTO 2 OF 4', AppLanguage.tagalog),
      'LITRATO 2 SA 4',
    );
    expect(
      translateAppText(
        'Tap the shutter to take this photo.',
        AppLanguage.tagalog,
      ),
      'Pindutin ang shutter para kunan ang litrato.',
    );
    expect(
      translateAppText('Creating cartoon photo 2 of 4...', AppLanguage.tagalog),
      'Ginagawa ang cartoon na litrato 2 of 4...',
    );
    expect(
      translateAppText(
        'Are you sure you want to convert this image into a cartoon?',
        AppLanguage.tagalog,
      ),
      'Sigurado ka bang gusto mong gawing cartoon ang larawang ito?',
    );
    expect(translateAppText('Smile!', AppLanguage.tagalog), 'Ngumiti!');
    expect(
      translateAppText('Custom customer message', AppLanguage.tagalog),
      'Custom customer message',
    );
  });
}
