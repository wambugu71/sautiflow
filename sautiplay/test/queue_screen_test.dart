import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiplay/album_detail_screen.dart';
import 'package:sautiplay/queue_screen.dart';

void main() {
  final sampleQueue = [
    TrackInfo(
      videoId: 'track-1',
      title: 'A Very Long Song Title That Should Be Visible On Mobile',
      artist: 'Artist One',
      durationSeconds: 215,
    ),
    TrackInfo(
      videoId: 'track-2',
      title: 'Second Track Name',
      artist: 'Artist Two',
      durationSeconds: 184,
    ),
  ];

  Widget buildSubject({
    required Size size,
    List<TrackInfo>? queue,
    String? videoId,
    void Function(int)? onPlayQueueIndex,
    void Function(int, int)? onReorderQueue,
    void Function(int)? onRemoveFromQueue,
  }) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: SizedBox(
          width: size.width,
          height: size.height,
          child: QueueScreen(
            queue: queue ?? sampleQueue,
            videoId: videoId ?? 'track-1',
            onPlayQueueIndex: onPlayQueueIndex ?? (_) {},
            onReorderQueue: onReorderQueue ?? (_, __) {},
            onRemoveFromQueue: onRemoveFromQueue,
          ),
        ),
      ),
    );
  }

  testWidgets('mobile layout gives song title generous width and uses overflow menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int? reorderedFrom;
    int? reorderedTo;
    int? removedIndex;

    await tester.pumpWidget(
      buildSubject(
        size: const Size(360, 800),
        onReorderQueue: (from, to) {
          reorderedFrom = from;
          reorderedTo = to;
        },
        onRemoveFromQueue: (index) => removedIndex = index,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final titleFinder = find.text(sampleQueue.first.title);
    expect(titleFinder, findsOneWidget);

    // Song title should get >= 160px on a 360px mobile screen.
    final titleBox = tester.getSize(titleFinder);
    expect(titleBox.width, greaterThanOrEqualTo(160));

    // Compact layout uses a single overflow menu button instead of inline reorder buttons.
    expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.vertical_align_top_rounded), findsNothing);

    // Open menu on second item and trigger Move to Top.
    await tester.tap(find.byIcon(Icons.more_vert_rounded).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Move to Top'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reorderedFrom, 1);
    expect(reorderedTo, 0);

    // Open menu on first item and trigger Remove from Queue.
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Remove from Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(removedIndex, 0);
  });

  testWidgets('wide layout shows inline reorder and remove buttons',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      buildSubject(
        size: const Size(900, 800),
        onRemoveFromQueue: (_) {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(find.byIcon(Icons.vertical_align_top_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.vertical_align_bottom_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
  });

  testWidgets('empty queue renders empty state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      buildSubject(
        size: const Size(360, 800),
        queue: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Queue is empty'), findsOneWidget);
  });
}
