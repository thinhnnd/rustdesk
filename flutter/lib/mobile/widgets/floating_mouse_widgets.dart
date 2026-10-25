import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/remote_input.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// Used for the wheel button and wheel scroll widgets
const double _kSpaceToHorizontalEdge = 12;
const double _wheelWidth = 42;
const double _wheelHeight = 140;
// Used for the DeskIn-style left/right button bar (bottom-left split capsule)
const double _kSpaceToVerticalEdge = 24;
const double _kSpaceBetweenLeftRightButtons = 2;
const double _kLeftRightButtonWidth = 66;
const double _kLeftRightButtonHeight = 50;
const double _kBorderWidth = 1.0;
final Color _kDefaultBorderColor = Colors.white.withOpacity(0.34);
final Color _kDefaultColor = const Color(0xFF141820).withOpacity(0.60);
final Color _kTapDownColor = const Color(0xFF2B6CB0).withOpacity(0.86);
final Color _kWidgetHighlightColor = Colors.white.withOpacity(0.85);
const int _kInputTimerInitialDelayMillis = 260;
const int _kInputTimerIntervalMillis = 155;

class FloatingMouseWidgets extends StatefulWidget {
  final FFI ffi;
  const FloatingMouseWidgets({
    super.key,
    required this.ffi,
  });

  @override
  State<FloatingMouseWidgets> createState() => _FloatingMouseWidgetsState();
}

class _FloatingMouseWidgetsState extends State<FloatingMouseWidgets> {
  InputModel get _inputModel => widget.ffi.inputModel;
  CursorModel get _cursorModel => widget.ffi.cursorModel;
  late final VirtualMouseMode _virtualMouseMode;

  @override
  void initState() {
    super.initState();
    _virtualMouseMode = widget.ffi.ffiModel.virtualMouseMode;
    _virtualMouseMode.addListener(_onVirtualMouseModeChanged);
    _cursorModel.blockEvents = false;
    isSpecialHoldDragActive = false;
  }

  void _onVirtualMouseModeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _virtualMouseMode.removeListener(_onVirtualMouseModeChanged);
    super.dispose();
    _cursorModel.blockEvents = false;
    isSpecialHoldDragActive = false;
  }

  @override
  Widget build(BuildContext context) {
    final virtualMouseMode = _virtualMouseMode;
    if (!virtualMouseMode.showVirtualMouse &&
        !virtualMouseMode.showVirtualScrollWheel) {
      return const Offstage();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (virtualMouseMode.showVirtualScrollWheel)
          FloatingWheel(
            inputModel: _inputModel,
            cursorModel: _cursorModel,
          ),
        if (virtualMouseMode.showVirtualMouse &&
            virtualMouseMode.showVirtualJoystick)
          VirtualJoystick(
            cursorModel: _cursorModel,
            inputModel: _inputModel,
          ),
        if (virtualMouseMode.showVirtualMouse) ...[
          FloatingLeftRightButton(
            isLeft: true,
            inputModel: _inputModel,
            cursorModel: _cursorModel,
          ),
          FloatingLeftRightButton(
            isLeft: false,
            inputModel: _inputModel,
            cursorModel: _cursorModel,
          ),
        ],
      ],
    );
  }
}

class FloatingWheel extends StatefulWidget {
  final InputModel inputModel;
  final CursorModel cursorModel;
  const FloatingWheel(
      {super.key, required this.inputModel, required this.cursorModel});

  @override
  State<FloatingWheel> createState() => _FloatingWheelState();
}

class _FloatingWheelState extends State<FloatingWheel> {
  Offset _position = Offset.zero;
  bool _isInitialized = false;
  Rect? _lastBlockedRect;

  bool _isUpDown = false;
  bool _isMidDown = false;
  bool _isDownDown = false;
  double _swipeScrollAccum = 0.0;

  Orientation? _previousOrientation;

  Timer? _scrollTimer;

  InputModel get _inputModel => widget.inputModel;
  CursorModel get _cursorModel => widget.cursorModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetPosition();
    });
  }

  void _resetPosition() {
    final size = MediaQuery.of(context).size;
    setState(() {
      _position = Offset(
        size.width - _wheelWidth - _kSpaceToHorizontalEdge,
        (size.height - _wheelHeight) / 2,
      );
      _isInitialized = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateBlockedRect();
    });
  }

  void _updateBlockedRect() {
    if (_lastBlockedRect != null) {
      _cursorModel.removeBlockedRect(_lastBlockedRect!);
    }
    final newRect =
        Rect.fromLTWH(_position.dx, _position.dy, _wheelWidth, _wheelHeight);
    _cursorModel.addBlockedRect(newRect);
    _lastBlockedRect = newRect;
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    if (_lastBlockedRect != null) {
      _cursorModel.removeBlockedRect(_lastBlockedRect!);
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentOrientation = MediaQuery.of(context).orientation;
    if (_previousOrientation != null &&
        _previousOrientation != currentOrientation) {
      _resetPosition();
    }
    _previousOrientation = currentOrientation;
  }

  Widget _buildUpDownButton(
      void Function(PointerDownEvent) onPointerDown,
      void Function(PointerUpEvent) onPointerUp,
      void Function(PointerCancelEvent) onPointerCancel,
      bool Function() flagGetter,
      BorderRadiusGeometry borderRadius,
      IconData iconData) {
    return Listener(
      onPointerDown: onPointerDown,
      onPointerUp: onPointerUp,
      onPointerCancel: onPointerCancel,
      child: Container(
        width: _wheelWidth,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: flagGetter() ? _kTapDownColor : _kDefaultColor,
          border: Border.all(
              color: flagGetter() ? Colors.blueAccent : _kDefaultBorderColor,
              width: _kBorderWidth),
          borderRadius: borderRadius,
        ),
        child: Icon(iconData, color: _kWidgetHighlightColor, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Positioned(child: Offstage());
    }
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: _buildWidget(context),
    );
  }

  Widget _buildWidget(BuildContext context) {
    return Container(
      width: _wheelWidth,
      height: _wheelHeight,
      child: Column(
        children: [
          _buildUpDownButton(
            (event) {
              HapticFeedback.selectionClick();
              setState(() {
                _isUpDown = true;
              });
              _startScrollTimer(1);
            },
            (event) {
              setState(() {
                _isUpDown = false;
              });
              _stopScrollTimer();
            },
            (event) {
              setState(() {
                _isUpDown = false;
              });
              _stopScrollTimer();
            },
            () => _isUpDown,
            BorderRadius.vertical(top: Radius.circular(_wheelWidth * 0.5)),
            Icons.arrow_drop_up_rounded,
          ),
          // Middle wheel: tap to middle-click, vertical drag to smooth scroll!
          Listener(
            onPointerDown: (event) {
              _swipeScrollAccum = 0.0;
              setState(() {
                _isMidDown = true;
              });
            },
            onPointerMove: (event) {
              _swipeScrollAccum += event.delta.dy;
              while (_swipeScrollAccum <= -16.0) {
                _inputModel.scroll(1);
                _swipeScrollAccum += 16.0;
              }
              while (_swipeScrollAccum >= 16.0) {
                _inputModel.scroll(-1);
                _swipeScrollAccum -= 16.0;
              }
            },
            onPointerUp: (event) {
              if (_swipeScrollAccum.abs() < 4.0) {
                HapticFeedback.lightImpact();
                _inputModel.tap(MouseButtons.wheel);
              }
              setState(() {
                _isMidDown = false;
              });
            },
            onPointerCancel: (event) {
              setState(() {
                _isMidDown = false;
              });
            },
            child: Container(
              width: _wheelWidth,
              height: 48,
              decoration: BoxDecoration(
                color: _isMidDown ? _kTapDownColor : _kDefaultColor,
                border: Border.symmetric(
                    vertical: BorderSide(
                        color: _isMidDown
                            ? Colors.blueAccent
                            : _kDefaultBorderColor,
                        width: _kBorderWidth)),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 1.8,
                      decoration: BoxDecoration(
                        color: _kDefaultBorderColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 12,
                      height: 1.8,
                      decoration: BoxDecoration(
                        color: _kDefaultBorderColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 18,
                      height: 1.8,
                      decoration: BoxDecoration(
                        color: _kDefaultBorderColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildUpDownButton(
            (event) {
              HapticFeedback.selectionClick();
              setState(() {
                _isDownDown = true;
              });
              _startScrollTimer(-1);
            },
            (event) {
              setState(() {
                _isDownDown = false;
              });
              _stopScrollTimer();
            },
            (event) {
              setState(() {
                _isDownDown = false;
              });
              _stopScrollTimer();
            },
            () => _isDownDown,
            BorderRadius.vertical(bottom: Radius.circular(_wheelWidth * 0.5)),
            Icons.arrow_drop_down_rounded,
          ),
        ],
      ),
    );
  }

  void _startScrollTimer(int direction) {
    _scrollTimer?.cancel();
    _inputModel.scroll(direction);
    _scrollTimer = Timer(
      const Duration(milliseconds: _kInputTimerInitialDelayMillis),
      () {
        if (!mounted || (!_isUpDown && !_isDownDown)) return;
        _inputModel.scroll(direction);
        _scrollTimer = Timer.periodic(
          const Duration(milliseconds: _kInputTimerIntervalMillis),
          (timer) {
            if (!mounted || (!_isUpDown && !_isDownDown)) {
              timer.cancel();
              return;
            }
            _inputModel.scroll(direction);
          },
        );
      },
    );
  }

  void _stopScrollTimer() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }
}

class FloatingLeftRightButton extends StatefulWidget {
  final bool isLeft;
  final InputModel inputModel;
  final CursorModel cursorModel;
  const FloatingLeftRightButton({
    super.key,
    required this.isLeft,
    required this.inputModel,
    required this.cursorModel,
  });

  @override
  State<FloatingLeftRightButton> createState() =>
      _FloatingLeftRightButtonState();
}

class _FloatingLeftRightButtonState extends State<FloatingLeftRightButton> {
  Offset _position = Offset.zero;
  bool _isInitialized = false;
  bool _isPressed = false;
  bool _remoteButtonDown = false;
  Rect? _lastBlockedRect;

  Orientation? _previousOrientation;
  Offset _preSavedPos = Offset.zero;

  Offset _pointerDownGlobalPos = Offset.zero;
  Timer? _holdClickTimer;
  Timer? _longPressHintTimer;
  bool _isMoveReady = false;
  bool _isDragging = false;
  bool _isSecondFingerDragging = false;

  bool get _isLeft => widget.isLeft;
  InputModel get _inputModel => widget.inputModel;
  CursorModel get _cursorModel => widget.cursorModel;
  MouseButtons get _mouseBtn =>
      _isLeft ? MouseButtons.left : MouseButtons.right;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentOrientation = MediaQuery.of(context).orientation;
      _previousOrientation = currentOrientation;
      _resetPosition(currentOrientation);
    });
  }

  @override
  void dispose() {
    _holdClickTimer?.cancel();
    _longPressHintTimer?.cancel();
    if (identical(
        onSpecialHoldSecondFingerStart, _onSecondFingerStartedOnCanvas)) {
      onSpecialHoldSecondFingerStart = null;
    }
    if (_remoteButtonDown) {
      _remoteButtonDown = false;
      _inputModel.tapUp(_mouseBtn);
    }
    if (_isPressed) {
      isSpecialHoldDragActive = false;
      isSpecialHoldDragCanvasMoving = false;
      _cursorModel.blockEvents = false;
    }
    if (_lastBlockedRect != null) {
      _cursorModel.removeBlockedRect(_lastBlockedRect!);
    }
    _trySavePosition();
    super.dispose();
  }

  void _onSecondFingerStartedOnCanvas() {
    if (!mounted || !_isPressed || _isDragging) return;
    _holdClickTimer?.cancel();
    _longPressHintTimer?.cancel();
    _isSecondFingerDragging = true;
    if (_isMoveReady) {
      setState(() {
        _isMoveReady = false;
      });
    }
    if (!_remoteButtonDown) {
      _remoteButtonDown = true;
      () async {
        await _cursorModel.syncCursorPosition();
        await _inputModel.tapDown(_mouseBtn);
      }();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentOrientation = MediaQuery.of(context).orientation;
    if (_previousOrientation == null ||
        _previousOrientation != currentOrientation) {
      _resetPosition(currentOrientation);
    }
    _previousOrientation = currentOrientation;
  }

  double _getOffsetX(double w) {
    if (_isLeft) {
      return 14.0;
    } else {
      return 14.0 + _kLeftRightButtonWidth + _kSpaceBetweenLeftRightButtons;
    }
  }

  String _getPositionKey(Orientation ori) {
    final strLeftRight = _isLeft ? 'l' : 'r';
    final strOri = ori == Orientation.landscape ? 'l' : 'p';
    return '$strLeftRight$strOri-deskin-mouse-btn-pos-v2';
  }

  static Offset? _loadPositionFromString(String s) {
    if (s.isEmpty) {
      return null;
    }
    try {
      final m = jsonDecode(s);
      return Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
    } catch (e) {
      debugPrintStack(label: 'Failed to load position "$s" $e');
      return null;
    }
  }

  void _trySavePosition() {
    if (_previousOrientation == null) return;
    if ((_position - _preSavedPos).distanceSquared < 0.1) return;
    final pos = jsonEncode({
      'x': _position.dx,
      'y': _position.dy,
    });
    bind.setLocalFlutterOption(
        k: _getPositionKey(_previousOrientation!), v: pos);
    _preSavedPos = _position;
  }

  void _restorePosition(Orientation ori) {
    final ps = bind.getLocalFlutterOption(k: _getPositionKey(ori));
    final pos = _loadPositionFromString(ps);
    final size = MediaQuery.of(context).size;
    if (pos == null) {
      _position = Offset(_getOffsetX(size.width),
          size.height - _kSpaceToVerticalEdge - _kLeftRightButtonHeight);
    } else {
      _position = Offset(
        pos.dx
            .clamp(8.0, max(8.0, size.width - _kLeftRightButtonWidth - 8.0))
            .toDouble(),
        pos.dy
            .clamp(8.0, max(8.0, size.height - _kLeftRightButtonHeight - 8.0))
            .toDouble(),
      );
      _preSavedPos = _position;
    }
  }

  void _resetPosition(Orientation ori) {
    setState(() {
      _restorePosition(ori);
      _isInitialized = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateBlockedRect();
    });
  }

  void _updateBlockedRect() {
    if (_lastBlockedRect != null) {
      _cursorModel.removeBlockedRect(_lastBlockedRect!);
    }
    final newRect = Rect.fromLTWH(_position.dx - 8, _position.dy - 8,
        _kLeftRightButtonWidth + 16, _kLeftRightButtonHeight + 16);
    _cursorModel.addBlockedRect(newRect);
    _lastBlockedRect = newRect;
  }

  void _onMoveUpdateDelta(Offset delta) {
    final size = MediaQuery.of(context).size;
    Offset newPosition = _position + delta;
    const double minX = 8.0;
    const double minY = 8.0;
    final double maxX = max(8.0, size.width - _kLeftRightButtonWidth - 8.0);
    final double maxY = max(8.0, size.height - _kLeftRightButtonHeight - 8.0);
    newPosition = Offset(
      newPosition.dx.clamp(minX, maxX).toDouble(),
      newPosition.dy.clamp(minY, maxY).toDouble(),
    );
    final isPositionChanged = !(isDoubleEqual(newPosition.dx, _position.dx) &&
        isDoubleEqual(newPosition.dy, _position.dy));
    setState(() {
      _position = newPosition;
    });
    if (isPositionChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateBlockedRect();
      });
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    HapticFeedback.lightImpact();
    _holdClickTimer?.cancel();
    _longPressHintTimer?.cancel();
    _pointerDownGlobalPos = event.position;
    _isDragging = false;
    _isMoveReady = false;
    _isSecondFingerDragging = false;
    _remoteButtonDown = false;
    isSpecialHoldDragActive = true;
    isSpecialHoldDragCanvasMoving = false;
    onSpecialHoldSecondFingerStart = _onSecondFingerStartedOnCanvas;
    setState(() {
      _isPressed = true;
    });

    // Khi giữ nút L (chuột trái), tự động gửi tapDown sau 90ms để sẵn sàng
    // cho thao tác tay phải di trên màn hình bôi đen văn bản / kéo thả (DeskIn style).
    if (_isLeft) {
      _holdClickTimer = Timer(const Duration(milliseconds: 90), () async {
        if (!mounted || !_isPressed || _isDragging || _remoteButtonDown) {
          return;
        }
        _remoteButtonDown = true;
        await _cursorModel.syncCursorPosition();
        await _inputModel.tapDown(_mouseBtn);
      });
    }

    // Sau 240ms nhấn giữ bằng 1 ngón (nếu chưa dùng ngón thứ 2 kéo trên canvas),
    // rung nhẹ báo hiệu có thể kéo di chuyển nút L hoặc R độc lập.
    _longPressHintTimer = Timer(const Duration(milliseconds: 240), () {
      if (!mounted ||
          !_isPressed ||
          _isDragging ||
          _isSecondFingerDragging ||
          isSpecialHoldDragCanvasMoving) {
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() {
        _isMoveReady = true;
      });
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isPressed) return;
    if (_isSecondFingerDragging || isSpecialHoldDragCanvasMoving) {
      return;
    }
    final dist = (event.position - _pointerDownGlobalPos).distance;
    // Chỉ chuyển sang chế độ kéo di chuyển vị trí nút L/R khi ngón tay đặt trên nút
    // thực sự dịch chuyển > 8px (tránh micro-move 0px của iOS khi đang giữ yên nút L).
    if (_isDragging || dist > 8.0) {
      if (!_isDragging) {
        _isDragging = true;
        _holdClickTimer?.cancel();
        _longPressHintTimer?.cancel();
        _cursorModel.blockEvents = true;
        isSpecialHoldDragActive = false;
        if (_remoteButtonDown) {
          _remoteButtonDown = false;
          _inputModel.tapUp(_mouseBtn);
        }
        if (!_isMoveReady) {
          HapticFeedback.selectionClick();
        }
        setState(() {
          _isMoveReady = true;
        });
      }
      _onMoveUpdateDelta(event.delta);
    }
  }

  Future<void> _handlePointerUpOrCancel({required bool isCancel}) async {
    _holdClickTimer?.cancel();
    _longPressHintTimer?.cancel();
    if (identical(
        onSpecialHoldSecondFingerStart, _onSecondFingerStartedOnCanvas)) {
      onSpecialHoldSecondFingerStart = null;
    }
    if (!mounted) return;
    final wasPressed = _isPressed;
    final wasDragging = _isDragging;
    final wasRemoteDown = _remoteButtonDown;

    _isPressed = false;
    _isDragging = false;
    _isMoveReady = false;
    _isSecondFingerDragging = false;
    _remoteButtonDown = false;
    isSpecialHoldDragActive = false;
    isSpecialHoldDragCanvasMoving = false;
    _cursorModel.blockEvents = false;

    setState(() {});

    if (wasDragging) {
      _trySavePosition();
      return;
    }
    if (!wasPressed) return;

    if (wasRemoteDown) {
      await _inputModel.tapUp(_mouseBtn);
    } else if (!isCancel) {
      await _cursorModel.syncCursorPosition();
      await _inputModel.tapDown(_mouseBtn);
      await Future.delayed(const Duration(milliseconds: 45));
      await _inputModel.tapUp(_mouseBtn);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Positioned(child: Offstage());
    }
    final isDown = _isPressed && !_isDragging;
    final highlightBorder = _isDragging || _isMoveReady || isDown;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: AnimatedScale(
        scale: (_isDragging || _isMoveReady) ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: (_) => _handlePointerUpOrCancel(isCancel: false),
          onPointerCancel: (_) => _handlePointerUpOrCancel(isCancel: true),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: _kLeftRightButtonWidth,
            height: _kLeftRightButtonHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDown ? _kTapDownColor : _kDefaultColor,
              border: Border.all(
                color: highlightBorder
                    ? Colors.lightBlueAccent
                    : _kDefaultBorderColor,
                width: highlightBorder ? 1.8 : _kBorderWidth,
              ),
              borderRadius: _isLeft
                  ? const BorderRadius.horizontal(
                      left: Radius.circular(25),
                      right: Radius.circular(4),
                    )
                  : const BorderRadius.horizontal(
                      left: Radius.circular(4),
                      right: Radius.circular(25),
                    ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isDragging ? 0.45 : 0.24),
                  blurRadius: _isDragging ? 12 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CustomPaint(
              size: const Size(22, 30),
              painter: _DeskInMouseButtonPainter(isLeft: _isLeft),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeskInMouseButtonPainter extends CustomPainter {
  final bool isLeft;
  const _DeskInMouseButtonPainter({required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bodyPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Draw the solid white rounded mouse silhouette
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.48),
    );
    canvas.drawRRect(rrect, bodyPaint);

    // Cut out / shade the active button (top-left for Left click, top-right for Right click)
    final cutoutPaint = Paint()
      ..color = const Color(0xFF1F242D)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final btnTop = h * 0.11;
    final btnHeight = h * 0.34;
    final btnWidth = w * 0.34;
    final btnLeft = isLeft ? (w * 0.14) : (w - w * 0.14 - btnWidth);

    final btnRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(btnLeft, btnTop, btnWidth, btnHeight),
      topLeft: Radius.circular(isLeft ? w * 0.34 : 2.5),
      topRight: Radius.circular(isLeft ? 2.5 : w * 0.34),
      bottomLeft: const Radius.circular(2.5),
      bottomRight: const Radius.circular(2.5),
    );
    canvas.drawRRect(btnRRect, cutoutPaint);
  }

  @override
  bool shouldRepaint(covariant _DeskInMouseButtonPainter oldDelegate) =>
      oldDelegate.isLeft != isLeft;
}

// Virtual joystick can send either absolute movement (via updatePan)
// or relative movement (via sendMobileRelativeMouseMove) depending on the
// InputModel.relativeMouseMode setting.
class VirtualJoystick extends StatefulWidget {
  final CursorModel cursorModel;
  final InputModel inputModel;

  const VirtualJoystick({
    super.key,
    required this.cursorModel,
    required this.inputModel,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _position = Offset.zero;
  bool _isInitialized = false;
  Offset _offset = Offset.zero;
  final double _joystickRadius = 50.0;
  final double _thumbRadius = 20.0;
  final double _moveStep = 3.0;
  final double _speed = 1.0;

  /// Scale factor for relative mouse movement sensitivity.
  /// Higher values result in faster cursor movement on the remote machine.
  static const double _kRelativeMouseScale = 3.0;

  // One-shot timer to detect a drag gesture
  Timer? _dragStartTimer;
  // Periodic timer for continuous movement
  Timer? _continuousMoveTimer;
  Size? _lastScreenSize;
  bool _isPressed = false;

  /// Check if relative mouse mode is enabled.
  bool get _useRelativeMouse => widget.inputModel.relativeMouseMode.value;

  @override
  void initState() {
    super.initState();
    widget.cursorModel.blockEvents = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastScreenSize = MediaQuery.of(context).size;
      _resetPosition();
    });
  }

  @override
  void dispose() {
    _stopSendEventTimer();
    widget.cursorModel.blockEvents = false;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentScreenSize = MediaQuery.of(context).size;
    if (_lastScreenSize != null && _lastScreenSize != currentScreenSize) {
      _resetPosition();
    }
    _lastScreenSize = currentScreenSize;
  }

  void _resetPosition() {
    final size = MediaQuery.of(context).size;
    setState(() {
      _position = Offset(
        _kSpaceToHorizontalEdge + _joystickRadius,
        size.height * 0.5 + _joystickRadius * 1.5,
      );
      _isInitialized = true;
    });
  }

  Offset _offsetToPanDelta(Offset offset) {
    return Offset(
      offset.dx / _joystickRadius,
      offset.dy / _joystickRadius,
    );
  }

  /// Send movement delta to remote machine.
  /// Uses relative mouse mode if enabled, otherwise uses absolute updatePan.
  void _sendMovement(Offset delta) {
    if (_useRelativeMouse) {
      widget.inputModel.sendMobileRelativeMouseMove(
          delta.dx * _kRelativeMouseScale, delta.dy * _kRelativeMouseScale);
    } else {
      // In absolute mode, use cursorModel.updatePan which tracks position.
      widget.cursorModel.updatePan(delta, Offset.zero, false);
    }
  }

  void _stopSendEventTimer() {
    _dragStartTimer?.cancel();
    _continuousMoveTimer?.cancel();
    _dragStartTimer = null;
    _continuousMoveTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Positioned(child: Offstage());
    }
    return Positioned(
      left: _position.dx - _joystickRadius,
      top: _position.dy - _joystickRadius,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isPressed = true;
          });
          widget.cursorModel.blockEvents = true;
          _updateOffset(details.localPosition);

          // 1. Send a single, small pan event immediately for responsiveness.
          //    The movement is small for a gentle start.
          final initialDelta = _offsetToPanDelta(_offset);
          if (initialDelta.distance > 0) {
            _sendMovement(initialDelta);
          }

          // 2. Start a one-shot timer to check if the user is holding for a drag.
          _dragStartTimer?.cancel();
          _dragStartTimer = Timer(const Duration(milliseconds: 120), () {
            // 3. If the timer fires, it's a drag. Start the continuous movement timer.
            _continuousMoveTimer?.cancel();
            _continuousMoveTimer =
                periodic_immediate(const Duration(milliseconds: 20), () async {
              if (_offset != Offset.zero) {
                _sendMovement(_offsetToPanDelta(_offset) * _moveStep * _speed);
              }
            });
          });
        },
        onPanUpdate: (details) {
          _updateOffset(details.localPosition);
        },
        onPanEnd: (details) {
          setState(() {
            _offset = Offset.zero;
            _isPressed = false;
          });
          widget.cursorModel.blockEvents = false;

          // 4. Critical step: On pan end, cancel all timers.
          //    If it was a flick, this cancels the drag detection before it fires.
          //    If it was a drag, this stops the continuous movement.
          _stopSendEventTimer();
        },
        child: CustomPaint(
          size: Size(_joystickRadius * 2, _joystickRadius * 2),
          painter: _JoystickPainter(
              _offset, _joystickRadius, _thumbRadius, _isPressed),
        ),
      ),
    );
  }

  void _updateOffset(Offset localPosition) {
    final center = Offset(_joystickRadius, _joystickRadius);
    final offset = localPosition - center;
    final distance = offset.distance;

    if (distance <= _joystickRadius) {
      setState(() {
        _offset = offset;
      });
    } else {
      final clampedOffset = offset / distance * _joystickRadius;
      setState(() {
        _offset = clampedOffset;
      });
    }
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset _offset;
  final double _joystickRadius;
  final double _thumbRadius;
  final bool _isPressed;

  _JoystickPainter(
      this._offset, this._joystickRadius, this._thumbRadius, this._isPressed);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final joystickColor = _kDefaultColor;
    final borderColor = _isPressed ? _kTapDownColor : _kDefaultBorderColor;
    final thumbColor = _kWidgetHighlightColor;

    final joystickPaint = Paint()
      ..color = joystickColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;

    // Draw joystick base and border
    canvas.drawCircle(center, _joystickRadius, joystickPaint);
    canvas.drawCircle(center, _joystickRadius, borderPaint);

    // Draw thumb
    final thumbCenter = center + _offset;
    canvas.drawCircle(thumbCenter, _thumbRadius, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate._offset != _offset ||
        oldDelegate._isPressed != _isPressed;
  }
}
