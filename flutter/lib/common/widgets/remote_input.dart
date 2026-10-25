import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/input_model.dart';

import './gestures.dart';

class RawKeyFocusScope extends StatelessWidget {
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final InputModel inputModel;
  final Widget child;

  RawKeyFocusScope({
    this.focusNode,
    this.onFocusChange,
    required this.inputModel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // https://github.com/flutter/flutter/issues/154053
    final useRawKeyEvents = isLinux && !isWeb;
    // FIXME: On Windows, `AltGr` will generate `Alt` and `Control` key events,
    // while `Alt` and `Control` are separated key events for en-US input method.
    return FocusScope(
        autofocus: true,
        child: Focus(
            autofocus: true,
            canRequestFocus: true,
            focusNode: focusNode,
            onFocusChange: onFocusChange,
            onKey: useRawKeyEvents
                ? (FocusNode data, RawKeyEvent event) =>
                    inputModel.handleRawKeyEvent(event)
                : null,
            onKeyEvent: useRawKeyEvents
                ? null
                : (FocusNode node, KeyEvent event) =>
                    inputModel.handleKeyEvent(event),
            child: child));
  }
}

// For virtual mouse when using the mouse mode on mobile.
// Special hold-drag mode: one finger holds a button (left/right button), another finger pans.
// This flag is to override the scale gesture to a pan gesture.
bool isSpecialHoldDragActive = false;
bool isSpecialHoldDragCanvasMoving = false;
VoidCallback? onSpecialHoldSecondFingerStart;
// Cache the last focal point to calculate deltas in special hold-drag mode.
Offset _lastSpecialHoldDragFocalPoint = Offset.zero;

class RawTouchGestureDetectorRegion extends StatefulWidget {
  final Widget child;
  final FFI ffi;
  final bool isCamera;
  late final InputModel inputModel = ffi.inputModel;
  late final FfiModel ffiModel = ffi.ffiModel;

  RawTouchGestureDetectorRegion({
    required this.child,
    required this.ffi,
    this.isCamera = false,
  });

  @override
  State<RawTouchGestureDetectorRegion> createState() =>
      _RawTouchGestureDetectorRegionState();
}

/// touchMode only:
///   LongPress -> right click
///   OneFingerPan -> start/end -> left down start/end
///   onDoubleTapDown -> move to
///   onLongPressDown => move to
///
/// mouseMode only:
///   DoubleFiner -> right click
///   HoldDrag -> left drag
class _RawTouchGestureDetectorRegionState
    extends State<RawTouchGestureDetectorRegion> {
  Offset _cacheLongPressPosition = Offset(0, 0);
  // Timestamp of the last long press event.
  int _cacheLongPressPositionTs = 0;
  double _mouseScrollIntegral = 0; // mouse scroll speed controller
  double _scale = 1;

  // Workaround tap down event when two fingers are used to scale(mobile)
  TapDownDetails? _lastTapDownDetails;

  PointerDeviceKind? lastDeviceKind;

  // For touch mode, onDoubleTap
  // `onDoubleTap()` does not provide the position of the tap event.
  Offset _lastPosOfDoubleTapDown = Offset.zero;
  bool _touchModePanStarted = false;
  bool _touchModePanIsCanvasMove = false;
  int _touchModeDownTimeMs = 0;
  Offset _touchModeDownLocalPos = Offset.zero;
  Timer? _shortPressDragHintTimer;
  bool _longPressTriggeredRightClick = false;
  double _threeFingerAccumDx = 0.0;
  bool _threeFingerSwitchedScreen = false;
  Offset _doubleFinerTapPosition = Offset.zero;

  // For mouse mode, we need to block the events when the cursor is in a blocked area.
  // So we need to cache the last tap down position.
  Offset? _lastTapDownPositionForMouseMode;
  // Cache global position for onTap (which lacks position info).
  Offset? _lastTapDownGlobalPosition;

  FFI get ffi => widget.ffi;
  FfiModel get ffiModel => widget.ffiModel;
  InputModel get inputModel => widget.inputModel;
  bool get handleTouch => (isDesktop || isWebDesktop) || ffiModel.touchMode;
  SessionID get sessionId => ffi.sessionId;
  bool get canvasLocked => isMobile && ffi.canvasModel.locked;

  String? _zoomToastMessage;
  Timer? _zoomToastTimer;
  bool _zoomLimitToastShownInGesture = false;

  void _showZoomToast(String message, {bool force = false}) {
    if (_zoomLimitToastShownInGesture && !force) return;
    _zoomLimitToastShownInGesture = true;
    _zoomToastTimer?.cancel();
    if (mounted) {
      setState(() {
        _zoomToastMessage = message;
      });
    }
    _zoomToastTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) {
        setState(() {
          _zoomToastMessage = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _zoomToastTimer?.cancel();
    _shortPressDragHintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RawGestureDetector(
          child: widget.child,
          gestures: makeGestures(context),
        ),
        if (isMobile)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _zoomToastMessage != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xD93A3D45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12, width: 0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      _zoomToastMessage ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool isNotTouchBasedDevice() {
    return !kTouchBasedDeviceKinds.contains(lastDeviceKind);
  }

  // Mobile, mouse mode.
  // Check if should block the mouse tap event (`_lastTapDownPositionForMouseMode`).
  bool shouldBlockMouseModeEvent() {
    return _lastTapDownPositionForMouseMode != null &&
        ffi.cursorModel.shouldBlock(_lastTapDownPositionForMouseMode!.dx,
            _lastTapDownPositionForMouseMode!.dy);
  }

  onTapDown(TapDownDetails d) async {
    lastDeviceKind = d.kind;
    _lastTapDownGlobalPosition = d.globalPosition;
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (handleTouch) {
      _lastPosOfDoubleTapDown = d.localPosition;
      // Desktop or mobile "Touch mode"
      _lastTapDownDetails = d;
      _touchModeDownTimeMs = DateTime.now().millisecondsSinceEpoch;
      _touchModeDownLocalPos = d.localPosition;
      _longPressTriggeredRightClick = false;
      _shortPressDragHintTimer?.cancel();
      if (isMobile && ffi.cursorModel.isInRemoteRect(d.localPosition)) {
        _shortPressDragHintTimer =
            Timer(const Duration(milliseconds: 155), () {
          if (mounted && !_touchModePanStarted) {
            HapticFeedback.selectionClick();
          }
        });
      }
    } else {
      _lastTapDownPositionForMouseMode = d.localPosition;
    }
  }

  onTapUp(TapUpDetails d) async {
    _shortPressDragHintTimer?.cancel();
    final TapDownDetails? lastTapDownDetails = _lastTapDownDetails;
    _lastTapDownDetails = null;
    if (isNotTouchBasedDevice()) {
      return;
    }
    // Filter duplicate touch tap events on iOS (Magic Mouse issue).
    if (inputModel.shouldIgnoreTouchTap(d.globalPosition)) {
      return;
    }
    if (handleTouch) {
      final isMoved =
          await ffi.cursorModel.move(d.localPosition.dx, d.localPosition.dy);
      if (isMoved) {
        // If pan already handled 'down', don't send it again.
        if (lastTapDownDetails != null && !_touchModePanStarted) {
          await inputModel.tapDown(MouseButtons.left);
        }
        await inputModel.tapUp(MouseButtons.left);
      }
    }
  }

  onTap() async {
    if (isNotTouchBasedDevice()) {
      return;
    }
    // Filter duplicate touch tap events on iOS (Magic Mouse issue).
    final lastPos = _lastTapDownGlobalPosition;
    if (lastPos != null && inputModel.shouldIgnoreTouchTap(lastPos)) {
      return;
    }
    if (!handleTouch) {
      // Cannot use `_lastTapDownDetails` because Flutter calls `onTapUp` before `onTap`, clearing the cached details.
      // Using `_lastTapDownPositionForMouseMode` instead.
      if (shouldBlockMouseModeEvent()) {
        return;
      }
      // Mobile, "Mouse mode"
      await inputModel.tap(MouseButtons.left);
    }
  }

  onDoubleTapDown(TapDownDetails d) async {
    lastDeviceKind = d.kind;
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (handleTouch) {
      _lastPosOfDoubleTapDown = d.localPosition;
      await ffi.cursorModel.move(d.localPosition.dx, d.localPosition.dy);
    } else {
      _lastTapDownPositionForMouseMode = d.localPosition;
    }
  }

  onDoubleTap() async {
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (ffiModel.touchMode && ffi.cursorModel.lastIsBlocked) {
      return;
    }
    if (handleTouch &&
        !ffi.cursorModel.isInRemoteRect(_lastPosOfDoubleTapDown)) {
      return;
    }
    // Check if the position is in a blocked area when using the mouse mode.
    if (!handleTouch) {
      if (shouldBlockMouseModeEvent()) {
        return;
      }
    }
    await inputModel.tap(MouseButtons.left);
    await inputModel.tap(MouseButtons.left);
  }

  onLongPressDown(LongPressDownDetails d) async {
    lastDeviceKind = d.kind;
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (handleTouch) {
      _lastPosOfDoubleTapDown = d.localPosition;
      _cacheLongPressPosition = d.localPosition;
      _touchModeDownTimeMs = DateTime.now().millisecondsSinceEpoch;
      _touchModeDownLocalPos = d.localPosition;
      _longPressTriggeredRightClick = false;
      if (!ffi.cursorModel.isInRemoteRect(d.localPosition)) {
        return;
      }
      _cacheLongPressPositionTs = DateTime.now().millisecondsSinceEpoch;
      if (ffiModel.isPeerMobile) {
        await ffi.cursorModel
            .move(_cacheLongPressPosition.dx, _cacheLongPressPosition.dy);
        await inputModel.tapDown(MouseButtons.left);
      }
    } else {
      _lastTapDownPositionForMouseMode = d.localPosition;
    }
  }

  onLongPressUp() async {
    _shortPressDragHintTimer?.cancel();
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (handleTouch) {
      if (_longPressTriggeredRightClick) {
        _longPressTriggeredRightClick = false;
        return;
      }
      if (ffiModel.isPeerMobile) {
        await inputModel.tapUp(MouseButtons.left);
      }
    }
  }

  // for mobiles
  onLongPress() async {
    _shortPressDragHintTimer?.cancel();
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (!ffi.ffiModel.isPeerMobile) {
      if (handleTouch) {
        if (_touchModePanStarted) return;
        final isMoved = await ffi.cursorModel
            .move(_cacheLongPressPosition.dx, _cacheLongPressPosition.dy);
        if (!isMoved) {
          return;
        }
        _longPressTriggeredRightClick = true;
        HapticFeedback.mediumImpact();
      } else {
        if (shouldBlockMouseModeEvent()) {
          return;
        }
      }
      await inputModel.tap(MouseButtons.right);
    } else {
      // It's better to send a message to tell the controlled device that the long press event is triggered.
      // We're now using a `TimerTask` in `InputService.kt` to decide whether to trigger the long press event.
      // It's not accurate and it's better to use the same detection logic in the controlling side.
    }
  }

  onLongPressMoveUpdate(LongPressMoveUpdateDetails d) async {
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (handleTouch) {
      if (!ffi.cursorModel.isInRemoteRect(d.localPosition)) {
        return;
      }
      await ffi.cursorModel.move(d.localPosition.dx, d.localPosition.dy);
    }
  }

  onDoubleFinerTapDown(TapDownDetails d) async {
    lastDeviceKind = d.kind;
    if (isNotTouchBasedDevice()) {
      return;
    }
    _doubleFinerTapPosition = d.localPosition;
    // ignore for desktop and mobile
  }

  onDoubleFinerTap(TapDownDetails d) async {
    _shortPressDragHintTimer?.cancel();
    lastDeviceKind = d.kind;
    if (isNotTouchBasedDevice()) {
      return;
    }

    // DeskIn style: Hold and click (1 finger holds + 2nd finger taps, or 2-finger tap) = Right click
    if (isMobile && ffiModel.touchMode) {
      if (ffi.cursorModel.isInRemoteRect(_doubleFinerTapPosition)) {
        HapticFeedback.mediumImpact();
        await ffi.cursorModel
            .move(_doubleFinerTapPosition.dx, _doubleFinerTapPosition.dy);
        await inputModel.tap(MouseButtons.right);
      }
      return;
    }

    // mobile mouse mode or desktop touch screen
    final isMobileMouseMode = isMobile && !ffiModel.touchMode;
    // We can't use `d.localPosition` here because it's always (0, 0) on desktop.
    final isDesktopInRemoteRect = (isDesktop || isWebDesktop) &&
        ffi.cursorModel.isInRemoteRect(_doubleFinerTapPosition);
    if (isMobileMouseMode || isDesktopInRemoteRect) {
      await inputModel.tap(MouseButtons.right);
    }
  }

  onHoldDragStart(DragStartDetails d) async {
    lastDeviceKind = d.kind;
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (!handleTouch) {
      if (isSpecialHoldDragActive) return;
      await inputModel.sendMouse('down', MouseButtons.left);
    }
  }

  onHoldDragUpdate(DragUpdateDetails d) async {
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (!handleTouch) {
      if (isSpecialHoldDragActive) return;
      await ffi.cursorModel.updatePan(d.delta, d.localPosition, handleTouch);
    }
  }

  onHoldDragEnd(DragEndDetails d) async {
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (!handleTouch) {
      await inputModel.sendMouse('up', MouseButtons.left);
    }
  }

  bool _oneFingerPanBlocked = false;

  onOneFingerPanStart(BuildContext context, DragStartDetails d) async {
    _shortPressDragHintTimer?.cancel();
    final TapDownDetails? lastTapDownDetails = _lastTapDownDetails;
    _lastTapDownDetails = null;
    lastDeviceKind = d.kind ?? lastDeviceKind;
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (ffi.cursorModel.shouldBlock(d.localPosition.dx, d.localPosition.dy) ||
        shouldBlockMouseModeEvent()) {
      _oneFingerPanBlocked = true;
      return;
    }
    _oneFingerPanBlocked = false;
    if (isSpecialHoldDragActive) {
      isSpecialHoldDragCanvasMoving = true;
      onSpecialHoldSecondFingerStart?.call();
    }
    if (handleTouch) {
      if (ffi.cursorModel.shouldBlock(d.localPosition.dx, d.localPosition.dy)) {
        return;
      }
      if (!ffi.cursorModel.isInRemoteRect(d.localPosition)) {
        return;
      }

      _touchModePanStarted = true;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final heldMs = nowMs - _touchModeDownTimeMs;
      final isZoomedIn =
          ffi.canvasModel.scale > (ffi.imageModel.minScale + 0.01);

      // DeskIn Touch Mode:
      // - Khi đang phóng to (isZoomedIn) và vuốt 1 ngón ngay lập tức (heldMs < 140ms):
      //   Trượt khung hình (Canvas Move) để xem quanh màn hình dễ dàng mà không làm trôi cửa sổ Mac.
      // - Khi nhấn giữ nhẹ rồi kéo ("Short press and drag", heldMs >= 140ms) hoặc khi ở Fit-to-screen:
      //   Giữ chuột trái và kéo ("Drag position" - kéo cửa sổ / bôi đen văn bản).
      if (isMobile && isZoomedIn && heldMs < 140 && !isSpecialHoldDragActive) {
        _touchModePanIsCanvasMove = true;
        return;
      }

      _touchModePanIsCanvasMove = false;
      final startPos =
          lastTapDownDetails?.localPosition ?? _touchModeDownLocalPos;
      await ffi.cursorModel.move(startPos.dx, startPos.dy);

      if (isDesktop || isWebDesktop) {
        ffi.cursorModel.trySetRemoteWindowCoords();
      }

      if (nowMs - _cacheLongPressPositionTs < 500) {
        await ffi.cursorModel
            .move(_cacheLongPressPosition.dx, _cacheLongPressPosition.dy);
      }
      // In relative mouse mode, skip mouse down - only send movement via sendMobileRelativeMouseMove
      if (!inputModel.relativeMouseMode.value) {
        await inputModel.sendMouse('down', MouseButtons.left);
      }
      await ffi.cursorModel.move(d.localPosition.dx, d.localPosition.dy);
    } else {
      final offset = ffi.cursorModel.offset;
      final cursorX = offset.dx;
      final cursorY = offset.dy;
      final visible =
          ffi.cursorModel.getVisibleRect().inflate(1); // extend edges
      final size = MediaQueryData.fromView(View.of(context)).size;
      if (!visible.contains(Offset(cursorX, cursorY))) {
        await ffi.cursorModel.move(size.width / 2, size.height / 2);
      }
    }
  }

  onOneFingerPanUpdate(DragUpdateDetails d) async {
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (_oneFingerPanBlocked ||
        ffi.cursorModel.shouldBlock(d.localPosition.dx, d.localPosition.dy)) {
      return;
    }
    if (isSpecialHoldDragActive) {
      isSpecialHoldDragCanvasMoving = true;
      onSpecialHoldSecondFingerStart?.call();
    }
    if (handleTouch && !_touchModePanStarted) {
      return;
    }
    if (handleTouch && _touchModePanIsCanvasMove) {
      if (!canvasLocked) {
        ffi.canvasModel.panX(d.delta.dx);
        ffi.canvasModel.panY(d.delta.dy);
      }
      return;
    }
    // In relative mouse mode, send delta directly without position tracking.
    if (inputModel.relativeMouseMode.value) {
      await inputModel.sendMobileRelativeMouseMove(d.delta.dx, d.delta.dy);
    } else {
      await ffi.cursorModel.updatePan(d.delta, d.localPosition, handleTouch);
    }
  }

  onOneFingerPanEnd(DragEndDetails d) async {
    _shortPressDragHintTimer?.cancel();
    final wasCanvasMove = _touchModePanIsCanvasMove;
    _oneFingerPanBlocked = false;
    _touchModePanStarted = false;
    _touchModePanIsCanvasMove = false;
    isSpecialHoldDragCanvasMoving = false;
    if (isNotTouchBasedDevice()) {
      return;
    }
    if (isDesktop || isWebDesktop) {
      ffi.cursorModel.clearRemoteWindowCoords();
    }
    if (handleTouch && !wasCanvasMove) {
      // In relative mouse mode, skip mouse up - matches the skipped mouse down in onOneFingerPanStart
      if (!inputModel.relativeMouseMode.value) {
        await inputModel.sendMouse('up', MouseButtons.left);
      }
    }
  }

  // Reset `_touchModePanStarted` if the one-finger pan gesture is cancelled
  // or rejected by the gesture arena. Without this, the flag can remain
  // stuck in the "started" state and cause issues such as the Magic Mouse
  // double-click problem on iPad with magic mouse.
  onOneFingerPanCancel() {
    _shortPressDragHintTimer?.cancel();
    _oneFingerPanBlocked = false;
    _touchModePanStarted = false;
    _touchModePanIsCanvasMove = false;
    isSpecialHoldDragCanvasMoving = false;
  }

  String _twoFingerGestureMode = 'undecided'; // 'undecided' | 'scroll' | 'zoom'
  Offset _twoFingerStartFocalPoint = Offset.zero;

  // scale + pan event
  onTwoFingerScaleStart(ScaleStartDetails d) {
    _shortPressDragHintTimer?.cancel();
    _lastTapDownDetails = null;
    if (isNotTouchBasedDevice()) {
      return;
    }
    _scale = 1.0;
    _zoomLimitToastShownInGesture = false;
    _twoFingerStartFocalPoint = d.focalPoint;
    // DeskIn style: cả Touch mode và Cursor mode đều phân biệt mượt mà giữa
    // Two-finger swipe (Window scrolling) và Pinch with two fingers (Zoom)!
    _twoFingerGestureMode = ffi.ffiModel.isPeerAndroid ? 'zoom' : 'undecided';
    if (isSpecialHoldDragActive) {
      isSpecialHoldDragCanvasMoving = true;
      onSpecialHoldSecondFingerStart?.call();
      // Initialize the last focal point to calculate deltas manually.
      _lastSpecialHoldDragFocalPoint = d.focalPoint;
    }
  }

  onTwoFingerScaleUpdate(ScaleUpdateDetails d) async {
    if (isNotTouchBasedDevice()) {
      return;
    }

    // If holding Left/Right floating button with 1 finger and dragging on screen with 2nd finger:
    // Note: ScaleGestureRecognizer computes focalPoint as the average of both fingers ((p1 + p2) / 2).
    // Because p1 (on the button) is stationary, focalPoint moves at half the delta of p2,
    // OR we can use d.focalPointDelta * 2.0 (which never jumps even on the first frame!).
    if (isSpecialHoldDragActive) {
      isSpecialHoldDragCanvasMoving = true;
      final delta = d.focalPointDelta * 2.0;
      if (inputModel.relativeMouseMode.value) {
        await inputModel.sendMobileRelativeMouseMove(delta.dx, delta.dy);
      } else {
        await ffi.cursorModel.updatePan(delta, d.localFocalPoint, handleTouch);
      }
      return;
    }

    if (canvasLocked) return;

    if ((isDesktop || isWebDesktop)) {
      final scale = ((d.scale - _scale) * 1000).toInt();
      _scale = d.scale;

      if (scale != 0) {
        if (widget.isCamera) return;
        await bind.sessionSendPointer(
            sessionId: sessionId,
            msg: json.encode(
                PointerEventToRust(kPointerEventKindTouch, 'scale', scale)
                    .toJson()));
      }
    } else {
      // Mobile: DeskIn-style mutually-exclusive two-finger gestures
      if (_twoFingerGestureMode == 'undecided') {
        final totalFocalMove = (d.focalPoint - _twoFingerStartFocalPoint).distance;
        final scaleChange = (d.scale - 1.0).abs();
        final isAtMinScale =
            ffi.canvasModel.scale <= (ffi.imageModel.minScale + 0.005);

        if (isAtMinScale && d.scale <= 0.88 && totalFocalMove < 24.0) {
          _twoFingerGestureMode = 'min_zoom_blocked';
          _showZoomToast('Không thể thu nhỏ thêm');
          return;
        }

        // When already at Fit-to-Screen (minScale), pinching inward (d.scale < 1.0)
        // cannot zoom out further, so only spreading outward (d.scale >= 1.10) enters zoom.
        final wantsZoom = isAtMinScale ? (d.scale >= 1.10) : (scaleChange >= 0.12);

        if (totalFocalMove > 7.0 && !wantsZoom) {
          _twoFingerGestureMode = 'scroll';
        } else if (wantsZoom) {
          _twoFingerGestureMode = 'zoom';
          _scale = d.scale;
        }
      }

      if (_twoFingerGestureMode == 'scroll') {
        // Strictly scroll ONLY — never zoom or pan canvas!
        _mouseScrollIntegral += d.focalPointDelta.dy / 6.0;
        while (_mouseScrollIntegral >= 1.0) {
          inputModel.scroll(1);
          _mouseScrollIntegral -= 1.0;
        }
        while (_mouseScrollIntegral <= -1.0) {
          inputModel.scroll(-1);
          _mouseScrollIntegral += 1.0;
        }
      } else if (_twoFingerGestureMode == 'zoom') {
        final prevScale = ffi.canvasModel.scale;
        final minScale = ffi.imageModel.minScale;
        final maxScale = ffi.imageModel.maxScale;
        final scaleFactor = d.scale / _scale;

        if (scaleFactor < 1.0 &&
            d.scale <= 0.88 &&
            prevScale <= (minScale + 0.005)) {
          _showZoomToast('Không thể thu nhỏ thêm');
        } else if (scaleFactor > 1.0 &&
            d.scale >= 1.12 &&
            prevScale >= (maxScale - 0.005)) {
          _showZoomToast('Không thể phóng to thêm');
        }

        // Strictly pinch to zoom + pan canvas ONLY — never scroll!
        ffi.canvasModel.updateScale(scaleFactor, d.focalPoint);
        _scale = d.scale;
        ffi.canvasModel.panX(d.focalPointDelta.dx);
        ffi.canvasModel.panY(d.focalPointDelta.dy);
      }
    }
  }

  onTwoFingerScaleEnd(ScaleEndDetails d) async {
    isSpecialHoldDragCanvasMoving = false;
    if (isNotTouchBasedDevice()) {
      return;
    }
    _twoFingerGestureMode = 'undecided';
    if ((isDesktop || isWebDesktop)) {
      if (widget.isCamera) return;
      await bind.sessionSendPointer(
          sessionId: sessionId,
          msg: json.encode(
              PointerEventToRust(kPointerEventKindTouch, 'scale', 0).toJson()));
    } else {
      // mobile
      _scale = 1;
    }
    if (!isSpecialHoldDragActive &&
        handleTouch &&
        _touchModePanStarted &&
        !_touchModePanIsCanvasMove) {
      _touchModePanStarted = false;
      await inputModel.sendMouse('up', MouseButtons.left);
    }
  }

  get onHoldDragCancel => null;
  get onThreeFingerVerticalDragStart => ffi.ffiModel.isPeerAndroid
      ? null
      : (DragStartDetails d) {
          _threeFingerAccumDx = 0.0;
          _threeFingerSwitchedScreen = false;
        };
  get onThreeFingerVerticalDragUpdate => ffi.ffiModel.isPeerAndroid
      ? null
      : (DragUpdateDetails d) {
          // DeskIn style: Three-finger horizontal swipe = Switch screen
          if (d.delta.dx.abs() > d.delta.dy.abs() * 1.2) {
            _threeFingerAccumDx += d.delta.dx;
            if (!_threeFingerSwitchedScreen &&
                _threeFingerAccumDx.abs() >= 60.0) {
              _threeFingerSwitchedScreen = true;
              HapticFeedback.mediumImpact();
              final pi = ffiModel.pi;
              if (pi.displays.length > 1) {
                final next = _threeFingerAccumDx < 0
                    ? (pi.currentDisplay + 1) % pi.displays.length
                    : (pi.currentDisplay + pi.displays.length - 1) %
                        pi.displays.length;
                openMonitorInTheSameTab(next, ffi, pi);
                _showZoomToast(
                    'Màn hình ${next + 1}/${pi.displays.length}',
                    force: true);
              } else {
                _showZoomToast('Chỉ có 1 màn hình', force: true);
              }
            }
            return;
          }
          _mouseScrollIntegral += d.delta.dy / 4;
          if (_mouseScrollIntegral > 1) {
            inputModel.scroll(1);
            _mouseScrollIntegral = 0;
          } else if (_mouseScrollIntegral < -1) {
            inputModel.scroll(-1);
            _mouseScrollIntegral = 0;
          }
        };

  makeGestures(BuildContext context) {
    return <Type, GestureRecognizerFactory>{
      // Official
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(), (instance) {
        instance
          ..onTapDown = onTapDown
          ..onTapUp = onTapUp
          ..onTap = onTap;
      }),
      DoubleTapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
              () => DoubleTapGestureRecognizer(), (instance) {
        instance
          ..onDoubleTapDown = onDoubleTapDown
          ..onDoubleTap = onDoubleTap;
      }),
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(), (instance) {
        instance
          ..onLongPressDown = onLongPressDown
          ..onLongPressUp = onLongPressUp
          ..onLongPress = onLongPress
          ..onLongPressMoveUpdate = onLongPressMoveUpdate;
      }),
      // Customized
      HoldTapMoveGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<HoldTapMoveGestureRecognizer>(
              () => HoldTapMoveGestureRecognizer(),
              (instance) => instance
                ..onHoldDragStart = onHoldDragStart
                ..onHoldDragUpdate = onHoldDragUpdate
                ..onHoldDragCancel = onHoldDragCancel
                ..onHoldDragEnd = onHoldDragEnd),
      DoubleFinerTapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<DoubleFinerTapGestureRecognizer>(
              () => DoubleFinerTapGestureRecognizer(), (instance) {
        instance
          ..onDoubleFinerTap = onDoubleFinerTap
          ..onDoubleFinerTapDown = onDoubleFinerTapDown;
      }),
      CustomTouchGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<CustomTouchGestureRecognizer>(
              () => CustomTouchGestureRecognizer(), (instance) {
        instance.onOneFingerPanStart =
            (DragStartDetails d) => onOneFingerPanStart(context, d);
        instance
          ..onOneFingerPanUpdate = onOneFingerPanUpdate
          ..onOneFingerPanEnd = onOneFingerPanEnd
          ..onOneFingerPanCancel = onOneFingerPanCancel
          ..onTwoFingerScaleStart = onTwoFingerScaleStart
          ..onTwoFingerScaleUpdate = onTwoFingerScaleUpdate
          ..onTwoFingerScaleEnd = onTwoFingerScaleEnd
          ..onThreeFingerVerticalDragStart = onThreeFingerVerticalDragStart
          ..onThreeFingerVerticalDragUpdate = onThreeFingerVerticalDragUpdate;
      }),
    };
  }
}

class RawPointerMouseRegion extends StatelessWidget {
  final InputModel inputModel;
  final Widget child;
  final MouseCursor? cursor;
  final PointerEnterEventListener? onEnter;
  final PointerExitEventListener? onExit;
  final PointerDownEventListener? onPointerDown;
  final PointerUpEventListener? onPointerUp;

  RawPointerMouseRegion({
    this.onEnter,
    this.onExit,
    this.cursor,
    this.onPointerDown,
    this.onPointerUp,
    required this.inputModel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: inputModel.onPointHoverImage,
      onPointerDown: (evt) {
        onPointerDown?.call(evt);
        inputModel.onPointDownImage(evt);
      },
      onPointerUp: (evt) {
        onPointerUp?.call(evt);
        inputModel.onPointUpImage(evt);
      },
      onPointerMove: inputModel.onPointMoveImage,
      onPointerSignal: inputModel.onPointerSignalImage,
      onPointerPanZoomStart: inputModel.onPointerPanZoomStart,
      onPointerPanZoomUpdate: inputModel.onPointerPanZoomUpdate,
      onPointerPanZoomEnd: inputModel.onPointerPanZoomEnd,
      child: MouseRegion(
        cursor: inputModel.isViewOnly
            ? MouseCursor.defer
            : (cursor ?? MouseCursor.defer),
        onEnter: onEnter,
        onExit: onExit,
        child: child,
      ),
    );
  }
}

class CameraRawPointerMouseRegion extends StatelessWidget {
  final InputModel inputModel;
  final Widget child;
  final PointerEnterEventListener? onEnter;
  final PointerExitEventListener? onExit;
  final PointerDownEventListener? onPointerDown;
  final PointerUpEventListener? onPointerUp;

  CameraRawPointerMouseRegion({
    this.onEnter,
    this.onExit,
    this.onPointerDown,
    this.onPointerUp,
    required this.inputModel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: (evt) {
        final offset = evt.position;
        double x = offset.dx;
        double y = max(0.0, offset.dy);
        inputModel.handlePointerDevicePos(
            kPointerEventKindMouse, x, y, true, kMouseEventTypeDefault);
      },
      onPointerDown: (evt) {
        onPointerDown?.call(evt);
      },
      onPointerUp: (evt) {
        onPointerUp?.call(evt);
      },
      child: MouseRegion(
        cursor: MouseCursor.defer,
        onEnter: onEnter,
        onExit: onExit,
        child: child,
      ),
    );
  }
}
