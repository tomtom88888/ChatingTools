import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/app_settings.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/screens/home_screen.dart';
import 'package:replylikeme/services/exchange_store.dart';
import 'package:replylikeme/state/providers.dart';
import 'package:replylikeme/widgets/paper_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class _Store implements ExchangeStore {
  _Store(this.savedStats);

  final StyleMemoryStats? savedStats;

  @override
  Future<void> replaceAll(
    List<StoredExchange> exchanges, {
    required StyleMemoryStats stats,
  }) async {}

  @override
  Future<StyleMemoryStats?> stats() async => savedStats;

  @override
  Future<int> count() async => savedStats?.exchangeCount ?? 0;

  @override
  Future<List<StoredExchange>> all() async => const [];

  @override
  Future<List<ScoredExchange>> mostSimilar(
    Float32List query, {
    int limit = 8,
  }) async => const [];

  @override
  Future<void> deleteEverything() async {}
}

class _Key extends ApiKeyNotifier {
  @override
  Future<String?> build() async => 'sk-test-0123456789abcdefghij';
}

StyleMemoryStats hebrewStats() => StyleMemoryStats(
  exchangeCount: 2424,
  embeddingModel: AppSettings.defaultEmbeddingModel,
  dimensions: 512,
  myName: 'תום',
  theirName: 'מאיה',
  builtAt: DateTime(2026, 9, 20, 9, 48),
);

/// A 360x780 phone with a 24dp status bar and a 48dp three-button navigation
/// bar \u2014 the shape that hid the footnote underneath the system bar.
const double navBar = 48;
const double statusBar = 24;

Future<void> pumpHome(
  WidgetTester tester, {
  StyleMemoryStats? stats,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  ReceiveSharingIntent.setMockValues(
    initialMedia: const [],
    mediaStream: const Stream.empty(),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiKeyProvider.overrideWith(_Key.new),
        exchangeStoreProvider.overrideWithValue(_Store(stats)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(
                top: statusBar,
                bottom: navBar,
              ),
              padding: const EdgeInsets.only(
                top: statusBar,
                bottom: navBar,
              ),
            ),
            child: const HomeScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Flutter's test font draws every glyph one em wide, which inflates text far
/// beyond its real width and would make these geometry checks meaningless.
/// Load the faces the app actually ships instead.
Future<void> loadAppFonts() async {
  const families = <String, List<String>>{
    'Instrument Serif': [
      'assets/fonts/InstrumentSerif-400.ttf',
      'assets/fonts/InstrumentSerif-400Italic.ttf',
    ],
    'Public Sans': [
      'assets/fonts/PublicSans-400.ttf',
      'assets/fonts/PublicSans-500.ttf',
      'assets/fonts/PublicSans-600.ttf',
    ],
    'JetBrains Mono': [
      'assets/fonts/JetBrainsMono-400.ttf',
      'assets/fonts/JetBrainsMono-500.ttf',
    ],
  };
  for (final family in families.entries) {
    final loader = FontLoader(family.key);
    for (final asset in family.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppFonts);

  group('right-to-left names', () {
    test('a name is isolated so it cannot reorder the sentence', () {
      expect(bidiIsolate('מאיה'), '\u2068מאיה\u2069');
      expect(bidiIsolate('Sam'), '\u2068Sam\u2069');
      expect(bidiIsolate(''), '');
    });

    testWidgets('"learning from" puts me on the left and them on the right', (
      tester,
    ) async {
      await pumpHome(tester, stats: hebrewStats());

      // Measured, not asserted against a string: the two names are separate
      // widgets in a pinned left-to-right row, so a Hebrew name cannot swap
      // them the way it does inside one mixed-script sentence.
      final pair = find.byType(NamePairValue);
      expect(pair, findsOneWidget);

      final meRect = tester.getRect(
        find.descendant(of: pair, matching: find.text('תום')),
      );
      final themRect = tester.getRect(
        find.descendant(of: pair, matching: find.text('מאיה')),
      );
      expect(
        meRect.left,
        lessThan(themRect.left),
        reason: 'the two names render in the wrong order',
      );
    });

    testWidgets('the detail rows run the full width of the card', (
      tester,
    ) async {
      await pumpHome(tester, stats: hebrewStats());

      // Centred, shrink-wrapped rows leave the dividers as short stubs in the
      // middle of the card; the design runs them edge to edge.
      final rows = tester.widgetList<Widget>(find.byType(StackedRow));
      expect(rows.length, 3);

      final widths = find
          .byType(StackedRow)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)).width)
          .toSet();
      expect(
        widths.length,
        1,
        reason: 'rows should all be the same, full-card width',
      );
    });
  });

  group('system insets', () {
    testWidgets('the footnote clears the navigation bar when trained', (
      tester,
    ) async {
      await pumpHome(tester, stats: hebrewStats());

      final footnote = find.text('Your chat history never leaves this phone.');
      expect(footnote, findsOneWidget);

      final bottomOfText = tester.getRect(footnote).bottom;
      final screenBottom = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      expect(
        bottomOfText,
        lessThanOrEqualTo(screenBottom - navBar),
        reason: 'the footnote is hidden behind the navigation bar',
      );
    });

    testWidgets('the footnote clears the navigation bar when untrained', (
      tester,
    ) async {
      await pumpHome(tester);

      final footnote = find.text('Your chat history never leaves this phone.');
      final bottomOfText = tester.getRect(footnote).bottom;
      final screenBottom = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      expect(bottomOfText, lessThanOrEqualTo(screenBottom - navBar));
    });

    testWidgets('the wordmark clears the status bar', (tester) async {
      await pumpHome(tester, stats: hebrewStats());

      final top = tester.getRect(find.text('REPLYLIKEME')).top;
      expect(top, greaterThanOrEqualTo(statusBar));
    });

    testWidgets('nothing overflows on a narrow phone', (tester) async {
      await pumpHome(tester, stats: hebrewStats());
      expect(tester.takeException(), isNull);

      await pumpHome(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
