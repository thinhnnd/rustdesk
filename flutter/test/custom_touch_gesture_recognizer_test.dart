import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common/widgets/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomTouchGestureRecognizer state transitions', () {
    late CustomTouchGestureRecognizer recognizer;
    late List<String> events;

    ScaleUpdateDetails update(int pointerCount, {double scale = 1.0}) =>
        ScaleUpdateDetails(
            focalPoint: const Offset(10, 10),
            pointerCount: pointerCount,
            scale: scale,
            focalPointDelta: const Offset(1, 1));

    setUp(() {
      recognizer = CustomTouchGestureRecognizer();
      events = [];
      recognizer.onOneFingerPanStart = (_) => events.add('panStart');
      recognizer.onOneFingerPanUpdate = (_) => events.add('panUpdate');
      recognizer.onOneFingerPanEnd = (_) => events.add('panEnd');
      recognizer.onTwoFingerScaleStart = (_) => events.add('scaleStart');
      recognizer.onTwoFingerScaleUpdate = (_) => events.add('scaleUpdate');
      recognizer.onTwoFingerScaleEnd = (_) => events.add('scaleEnd');
      recognizer.onThreeFingerVerticalDragStart =
          (_) => events.add('drag3Start');
      recognizer.onThreeFingerVerticalDragUpdate =
          (_) => events.add('drag3Update');
      recognizer.onThreeFingerVerticalDragEnd = (_) => events.add('drag3End');
    });

    tearDown(() => recognizer.dispose());

    test('adding a finger ends the previous state before starting the new one',
        () {
      recognizer.onStart!(
          ScaleStartDetails(focalPoint: Offset.zero, pointerCount: 1));
      recognizer.onUpdate!(update(1));
      recognizer.onUpdate!(update(2));
      expect(events,
          ['panStart', 'panUpdate', 'panEnd', 'scaleStart', 'scaleUpdate']);
    });

    test('lifting a finger keeps state but suppresses updates until end', () {
      recognizer.onStart!(
          ScaleStartDetails(focalPoint: Offset.zero, pointerCount: 2));
      recognizer.onUpdate!(update(2));
      // One finger lifted: the remaining finger must not keep emitting
      // two-finger events, but the state stays so onEnd still pairs.
      recognizer.onUpdate!(update(1));
      recognizer.onUpdate!(update(1));
      recognizer.onEnd!(ScaleEndDetails(pointerCount: 1));
      expect(events, ['scaleStart', 'scaleUpdate', 'scaleEnd']);
      expect(events, isNot(contains('panStart')));
    });

    test('three-finger gesture ends the two-finger state first', () {
      recognizer.onStart!(
          ScaleStartDetails(focalPoint: Offset.zero, pointerCount: 2));
      recognizer.onUpdate!(update(2));
      recognizer.onUpdate!(update(3));
      expect(events, [
        'scaleStart',
        'scaleUpdate',
        'scaleEnd',
        'drag3Start',
        'drag3Update'
      ]);
    });

    test('single-finger pan still starts and ends normally', () {
      recognizer.onStart!(
          ScaleStartDetails(focalPoint: Offset.zero, pointerCount: 1));
      recognizer.onUpdate!(update(1));
      recognizer.onEnd!(ScaleEndDetails(pointerCount: 1));
      expect(events, ['panStart', 'panUpdate', 'panEnd']);
    });
  });
}
