import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pag/pag.dart';

const _channel = MethodChannel('flutter_pag_plugin');
const _codec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int viewId;
  final methodCalls = <MethodCall>[];

  setUp(() {
    PAG.enableCheckAvailable(true);
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      methodCalls.add(call);
      if (call.method == 'initPag') {
        viewId = call.arguments['viewId'] as int;
        return <String, Object>{
          'textureId': 42,
          'width': 200.0,
          'height': 120.0,
        };
      }
      return '';
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('Android warms Texture behind fallback before revealing it', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(_buildPagView());
    await tester.pump();

    expect(find.byKey(const Key('fallback')), findsOneWidget);
    expect(find.byType(Texture), findsOneWidget);

    await _sendFrameState(viewId, 'onFrameReady');
    await tester.pump();

    expect(find.byKey(const Key('fallback')), findsOneWidget);
    expect(find.byType(Texture), findsOneWidget);

    await tester.pump();

    expect(find.byKey(const Key('fallback')), findsNothing);
    expect(find.byType(Texture), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android restores fallback while Surface is unavailable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(_buildPagView());
    await tester.pump();
    await _sendFrameState(viewId, 'onFrameReady');
    await tester.pump();
    await tester.pump();

    await _sendFrameState(viewId, 'onFrameUnavailable');
    await tester.pump();

    expect(find.byKey(const Key('fallback')), findsOneWidget);
    expect(find.byType(Texture), findsOneWidget);

    await _sendFrameState(viewId, 'onFrameReady');
    await tester.pump();

    expect(find.byKey(const Key('fallback')), findsOneWidget);
    expect(find.byType(Texture), findsOneWidget);

    await tester.pump();

    expect(find.byKey(const Key('fallback')), findsNothing);
    expect(find.byType(Texture), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'non-Android platforms keep the existing immediate Texture behavior',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await tester.pumpWidget(_buildPagView());
      await tester.pump();

      expect(find.byKey(const Key('fallback')), findsNothing);
      expect(find.byType(Texture), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('late native frame callbacks are ignored after dispose', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(_buildPagView());
    await tester.pump();
    final disposedViewId = viewId;

    await tester.pumpWidget(const SizedBox());
    await _sendFrameState(disposedViewId, 'onFrameReady');
    await tester.pump();

    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Surface loss cancels a pending Texture reveal', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(_buildPagView());
    await tester.pump();

    await _sendFrameState(viewId, 'onFrameReady');
    await _sendFrameState(viewId, 'onFrameUnavailable');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('fallback')), findsOneWidget);
    expect(find.byType(Texture), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Android lifecycle pause restores fallback until a fresh frame is ready',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pagKey = GlobalKey<PAGViewState>();

      await tester.pumpWidget(_buildPagView(key: pagKey));
      await tester.pump();
      await _sendFrameState(viewId, 'onFrameReady');
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('fallback')), findsNothing);

      pagKey.currentState!.pauseForLifecycle();
      await tester.pump();

      expect(find.byKey(const Key('fallback')), findsOneWidget);
      expect(find.byType(Texture), findsOneWidget);
      expect(
        methodCalls.where((call) => call.method == 'pauseForLifecycle'),
        hasLength(1),
      );

      pagKey.currentState!.start();
      await _sendFrameState(viewId, 'onFrameReady');
      await tester.pump();

      expect(find.byKey(const Key('fallback')), findsOneWidget);

      await tester.pump();

      expect(find.byKey(const Key('fallback')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

Widget _buildPagView({Key? key}) {
  return MaterialApp(
    home: PAGView.bytes(
      Uint8List.fromList(const [1, 2, 3]),
      key: key,
      width: 100,
      height: 60,
      defaultBuilder: (_) =>
          const SizedBox(key: Key('fallback'), width: 100, height: 60),
    ),
  );
}

Future<void> _sendFrameState(int viewId, String event) async {
  final completer = Completer<void>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _channel.name,
    _codec.encodeMethodCall(
      MethodCall('PAGCallback', <String, Object>{
        'textureId': 42,
        'viewId': viewId,
        'PAGEvent': event,
      }),
    ),
    (_) => completer.complete(),
  );
  await completer.future;
}
