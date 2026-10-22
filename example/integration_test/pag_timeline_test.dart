// Integration tests for the iOS setProgress/start/stop timeline fix (PR #111).
//
// These drive the real Dart PAGView API -> MethodChannel -> native
// TGFlutterPagRender on a running iOS simulator and assert on the real
// animation-event timing reported back through the channel. The animation self
// drives through the native CADisplayLink + textureFrameAvailable, so no manual
// frame pumping is needed to advance it; pumping here only keeps the widget tree
// alive while real wall-clock time passes.
//
// Run: cd example && flutter test integration_test/pag_timeline_test.dart -d <ios-sim-id>

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pag/pag.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Event timelines captured across a single mounted PAGView.
  late List<DateTime> starts;
  late List<DateTime> ends;
  late List<DateTime> cancels;
  late List<DateTime> repeats;
  late GlobalKey<PAGViewState> pagKey;
  late Completer<void> inited;

  PAGViewState stateOf() {
    final s = pagKey.currentState;
    expect(s, isNotNull, reason: 'PAGViewState must be available');
    return s!;
  }

  // Advances real wall-clock time while keeping the widget tree pumping so the
  // texture keeps compositing and channel callbacks keep arriving.
  Future<void> waitReal(WidgetTester tester, Duration d) async {
    final deadline = DateTime.now().add(d);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  // Waits until predicate holds or timeout elapses, pumping meanwhile.
  Future<bool> waitFor(
      WidgetTester tester, bool Function() cond, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (cond()) return true;
      await tester.pump(const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return cond();
  }

  Future<void> mountPag(WidgetTester tester) async {
    starts = <DateTime>[];
    ends = <DateTime>[];
    cancels = <DateTime>[];
    repeats = <DateTime>[];
    pagKey = GlobalKey<PAGViewState>();
    inited = Completer<void>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PAGView.asset(
            'data/0.pag',
            key: pagKey,
            width: 100,
            height: 100,
            repeatCount: 1,
            initProgress: 0,
            autoPlay: false,
            onInit: () {
              if (!inited.isCompleted) inited.complete();
            },
            onAnimationStart: () => starts.add(DateTime.now()),
            onAnimationEnd: () => ends.add(DateTime.now()),
            onAnimationCancel: () => cancels.add(DateTime.now()),
            onAnimationRepeat: () => repeats.add(DateTime.now()),
          ),
        ),
      ),
    ));

    final ready = await waitFor(tester, () => inited.isCompleted,
        const Duration(seconds: 30));
    expect(ready, isTrue, reason: 'PAGView onInit must fire within 30s');
    // Give the first frame/texture a moment to settle.
    await waitReal(tester, const Duration(milliseconds: 200));
  }

  // Plays once from 0 and returns the measured animation duration in ms.
  Future<int> calibrate(WidgetTester tester) async {
    final state = stateOf();
    final endBefore = ends.length;
    state.setProgress(0);
    final t0 = DateTime.now();
    state.start();
    final ok = await waitFor(
        tester, () => ends.length > endBefore, const Duration(seconds: 30));
    expect(ok, isTrue, reason: 'calibration: animation must end within 30s');
    final d = ends.last.difference(t0).inMilliseconds;
    debugPrint('[pagtest] calibrated duration = ${d}ms');
    expect(d, greaterThan(80),
        reason: 'calibration: animation must actually play (got ${d}ms)');
    // Let things quiesce at the end frame.
    await waitReal(tester, const Duration(milliseconds: 300));
    return d;
  }

  testWidgets('stop mid-play then start after a long wait replays in full',
      (WidgetTester tester) async {
    await mountPag(tester);
    final state = stateOf();
    final d = await calibrate(tester);

    // Start playing, then stop partway through.
    state.setProgress(0);
    state.start();
    await waitReal(tester, Duration(milliseconds: (d * 0.4).round()));

    final endBeforeStop = ends.length;
    final cancelBeforeStop = cancels.length;
    state.stop();
    await waitReal(tester, const Duration(milliseconds: 400));

    // Stopping mid-play emits exactly one End and one Cancel (no duplicate End
    // from the raster/stop race).
    expect(cancels.length, cancelBeforeStop + 1,
        reason: 'stop must emit exactly one Cancel');
    expect(ends.length, endBeforeStop + 1,
        reason: 'stop mid-play must emit exactly one End (no duplicate)');

    // Wait much longer than the animation. With the bug the timeline stayed
    // Playing and was not re-anchored, so the first frame after start() would
    // see elapsed > duration and end instantly.
    await waitReal(tester, Duration(milliseconds: d + 800));
    expect(ends.length, endBeforeStop + 1,
        reason: 'no events should fire while stopped');

    final endBeforeStart = ends.length;
    final tStart = DateTime.now();
    state.start();
    final ok = await waitFor(tester, () => ends.length > endBeforeStart,
        Duration(milliseconds: d * 2 + 6000));
    expect(ok, isTrue, reason: 'start() after stop must eventually end');
    final elapsed = ends.last.difference(tStart).inMilliseconds;
    debugPrint('[pagtest] S1 replay elapsed = ${elapsed}ms (duration ${d}ms)');

    // The fix: it replays the full animation instead of ending immediately.
    expect(elapsed, greaterThan((d * 0.5).round()),
        reason:
            'start() after stop must replay from initProgress (full play), got ${elapsed}ms vs duration ${d}ms');
    expect(ends.length, endBeforeStart + 1,
        reason: 'replay must emit exactly one End');
  });

  testWidgets('a second stop emits no extra End but still emits Cancel',
      (WidgetTester tester) async {
    await mountPag(tester);
    final state = stateOf();
    final d = await calibrate(tester);

    state.setProgress(0);
    state.start();
    await waitReal(tester, Duration(milliseconds: (d * 0.4).round()));

    final endBeforeStop = ends.length;
    final cancelBeforeStop = cancels.length;

    // First stop mid-play: exactly one End and one Cancel.
    state.stop();
    await waitReal(tester, const Duration(milliseconds: 300));
    expect(ends.length, endBeforeStop + 1,
        reason: 'first stop must emit exactly one End');
    expect(cancels.length, cancelBeforeStop + 1,
        reason: 'first stop must emit exactly one Cancel');

    // Second stop with no start() in between: End must not fire again (stop is
    // idempotent for onAnimationEnd), while Cancel is still emitted each time.
    state.stop();
    await waitReal(tester, const Duration(milliseconds: 300));
    expect(ends.length, endBeforeStop + 1,
        reason: 'a repeated stop must not emit a duplicate End');
    expect(cancels.length, cancelBeforeStop + 2,
        reason: 'each stop still emits a Cancel');
  });

  testWidgets('pause then resume continues from the paused position',
      (WidgetTester tester) async {
    await mountPag(tester);
    final state = stateOf();
    final d = await calibrate(tester);

    state.setProgress(0);
    state.start();
    await waitReal(tester, Duration(milliseconds: (d * 0.4).round()));
    state.pause();
    await waitReal(tester, const Duration(milliseconds: 1500));

    final endBefore = ends.length;
    final tResume = DateTime.now();
    state.start();
    final ok = await waitFor(tester, () => ends.length > endBefore,
        Duration(milliseconds: d * 2 + 6000));
    expect(ok, isTrue, reason: 'resume must reach the end');
    final elapsed = ends.last.difference(tResume).inMilliseconds;
    debugPrint('[pagtest] S2 resume elapsed = ${elapsed}ms (expected ~${(d * 0.6).round()}ms)');

    // Remaining time should be roughly 60% of the duration (paused at ~40%),
    // definitely not the full duration and not instant.
    expect(elapsed, greaterThan((d * 0.25).round()),
        reason: 'resume must continue, not restart instantly');
    expect(elapsed, lessThan((d * 1.1).round()),
        reason: 'resume must not replay the already-played portion');
  });

  testWidgets('start after natural end replays from the beginning',
      (WidgetTester tester) async {
    await mountPag(tester);
    final state = stateOf();
    final d = await calibrate(tester);

    // calibrate() already left the animation at its natural end.
    final endBefore = ends.length;
    final tStart = DateTime.now();
    state.start();
    final ok = await waitFor(tester, () => ends.length > endBefore,
        Duration(milliseconds: d * 2 + 6000));
    expect(ok, isTrue, reason: 'start() after natural end must replay');
    final elapsed = ends.last.difference(tStart).inMilliseconds;
    debugPrint('[pagtest] S3 replay-after-end elapsed = ${elapsed}ms (duration ${d}ms)');
    expect(elapsed, greaterThan((d * 0.5).round()),
        reason: 'replay after end must play the full animation, got ${elapsed}ms');
  });
}
