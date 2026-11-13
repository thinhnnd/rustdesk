@TestOn('browser')

import 'dart:async';
import 'dart:js' as js;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/remote_input.dart';
import 'package:flutter_hbb/mobile/widgets/floating_mouse_widgets.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Input extends Fake implements InputModel {
  final events = <(String, MouseButtons)>[];

  @override
  Future<void> tapDown(MouseButtons button) async =>
      events.add(('down', button));

  @override
  Future<void> tapUp(MouseButtons button) async => events.add(('up', button));
}

class _FFI extends Fake implements FFI {}

class _Cursor extends CursorModel {
  _Cursor(FFI ffi) : super(WeakReference(ffi));
  final syncs = <Completer<void>>[];

  @override
  Future<void> syncCursorPosition() {
    final sync = Completer<void>();
    syncs.add(sync);
    return sync.future;
  }
}

void main() {
  setUp(() {
    isSpecialHoldDragActive = false;
    isSpecialHoldDragCanvasMoving = false;
    js.context['isMobile'] = js.allowInterop(() => true);
    js.context['getByName'] =
        js.allowInterop((String name, [String? key]) => '');
    js.context['setByName'] = js.allowInterop((String name, dynamic value) {});
  });
  tearDown(() {
    isSpecialHoldDragActive = false;
    isSpecialHoldDragCanvasMoving = false;
    for (final name in ['isMobile', 'getByName', 'setByName']) {
      js.context.deleteProperty(name);
    }
  });

  testWidgets('holding the button sends no remote down until release',
      (tester) async {
    final ffi = _FFI();
    final input = _Input();
    final cursor = _Cursor(ffi);
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        FloatingLeftRightButton(
            isLeft: true, inputModel: input, cursorModel: cursor),
      ]),
    ));
    await tester.pump();
    final target = find.byType(FloatingLeftRightButton);
    final press = await tester.startGesture(tester.getCenter(target));
    // Holding the button (without a second finger on the canvas) must not
    // speculatively press the remote mouse button.
    await tester.pump(const Duration(milliseconds: 300));
    expect(cursor.syncs, isEmpty);
    expect(input.events, isEmpty);

    await press.up();
    await tester.pump();
    expect(cursor.syncs, hasLength(1));
    // No remote events may be emitted while the cursor sync is pending.
    expect(input.events, isEmpty);
    cursor.syncs.single.complete();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
        input.events, [('down', MouseButtons.left), ('up', MouseButtons.left)]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('pointer cancel sends no remote events', (tester) async {
    final ffi = _FFI();
    final input = _Input();
    final cursor = _Cursor(ffi);
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        FloatingLeftRightButton(
            isLeft: true, inputModel: input, cursorModel: cursor),
      ]),
    ));
    await tester.pump();
    final target = find.byType(FloatingLeftRightButton);
    final press = await tester.startGesture(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 100));
    await press.cancel();
    await tester.pump(const Duration(milliseconds: 100));
    expect(cursor.syncs, isEmpty);
    expect(input.events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
