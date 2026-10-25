import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/mobile/widgets/deskin_shortcut_dialog.dart';
import 'package:flutter_hbb/mobile/widgets/floating_mouse.dart';
import 'package:flutter_hbb/mobile/widgets/floating_mouse_widgets.dart';
import 'package:flutter_hbb/mobile/widgets/gesture_help.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/overlay.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/remote_input.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/shortcut_model.dart';
import '../../utils/image.dart';
import '../widgets/dialog.dart';
import '../widgets/custom_scale_widget.dart';

final initText = '1' * 1024;

// Workaround for Android (default input method, Microsoft SwiftKey keyboard) when using physical keyboard.
// When connecting a physical keyboard, `KeyEvent.physicalKey.usbHidUsage` are wrong is using Microsoft SwiftKey keyboard.
// https://github.com/flutter/flutter/issues/159384
// https://github.com/flutter/flutter/issues/159383
void _disableAndroidSoftKeyboard({bool? isKeyboardVisible}) {
  if (isAndroid) {
    if (isKeyboardVisible != true) {
      // `enable_soft_keyboard` will be set to `true` when clicking the keyboard icon, in `openKeyboard()`.
      gFFI.invokeMethod("enable_soft_keyboard", false);
    }
  }
}

bool handleMobileLocalKeyEvent(KeyEvent event,
    {required bool remoteFocused, required InputModel inputModel}) {
  if (event is KeyUpEvent && inputModel.isViewOnly) {
    // View-only skips normal modifier cleanup; stale physical keys would
    // otherwise look like touch selections in the input helper.
    inputModel.handleKeyUpEventModifiers(event);
  }
  if (!remoteFocused &&
      event is KeyUpEvent &&
      const [
        PhysicalKeyboardKey.controlLeft,
        PhysicalKeyboardKey.controlRight,
        PhysicalKeyboardKey.altLeft,
        PhysicalKeyboardKey.altRight,
        PhysicalKeyboardKey.shiftLeft,
        PhysicalKeyboardKey.shiftRight,
        PhysicalKeyboardKey.metaLeft,
        PhysicalKeyboardKey.metaRight,
      ].contains(event.physicalKey)) {
    // Local UI may consume key-ups while the remote input path still owns
    // the modifiers pressed before focus moved.
    inputModel.handleKeyEvent(event);
  }
  return false;
}

class RemotePage extends StatefulWidget {
  RemotePage(
      {Key? key,
      required this.id,
      this.password,
      this.isSharedPassword,
      this.forceRelay})
      : super(key: key);

  final String id;
  final String? password;
  final bool? isSharedPassword;
  final bool? forceRelay;

  @override
  State<RemotePage> createState() => _RemotePageState(id);
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  Timer? _timer;
  bool _showBar = false;
  bool _showGestureHelp = false;
  bool _showMousePanel = false;
  int _mousePanelSubPage = 0; // 0: main, 1: mouse settings
  bool _showOperationGuideOverlay = false;
  bool _operationGuideIsTouchPage = true;
  bool _alwaysShowShortcuts = false;
  double _floatingBarRight = 14.0;
  double _floatingBarBottom = 16.0;
  bool _isDraggingBar = false;
  Offset _lastBarDragGlobalPos = Offset.zero;
  Timer? _capsuleHoldTimer;
  int? _capsuleActivePointer;
  Offset _capsuleDownGlobalPos = Offset.zero;
  bool _capsuleDownIsLeftHalf = false;
  bool _capsuleIsPressing = false;
  String _value = '';
  Orientation? _currentOrientation;
  final _uniqueKey = UniqueKey();
  Timer? _iosKeyboardWorkaroundTimer;

  final _blockableOverlayState = BlockableOverlayState();

  final keyboardVisibilityController = KeyboardVisibilityController();
  late final StreamSubscription<bool> keyboardSubscription;
  final FocusNode _mobileFocusNode = FocusNode();
  final FocusNode _physicalFocusNode = FocusNode();
  var _showEdit = false; // use soft keyboard

  Worker? _waylandKeyboardGateWorker;
  bool _waylandKeyboardGateInitialized = false;

  InputModel get inputModel => gFFI.inputModel;
  SessionID get sessionId => gFFI.sessionId;

  final TextEditingController _textController =
      TextEditingController(text: initText);

  _RemotePageState(String id) {
    initSharedStates(id);
    gFFI.chatModel.voiceCallStatus.value = VoiceCallStatus.notStarted;
    gFFI.dialogManager.loadMobileActionsOverlayVisible();
  }

  @override
  void initState() {
    super.initState();
    gFFI.ffiModel.updateEventListener(sessionId, widget.id);
    gFFI.start(
      widget.id,
      password: widget.password,
      isSharedPassword: widget.isSharedPassword,
      forceRelay: widget.forceRelay,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      gFFI.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });
    WakelockManager.enable(_uniqueKey);
    _physicalFocusNode.requestFocus();
    HardwareKeyboard.instance.addHandler(_handleLocalKeyEvent);
    gFFI.inputModel.listenToMouse(true);
    gFFI.qualityMonitorModel.checkShowQualityMonitor(sessionId);
    keyboardSubscription =
        keyboardVisibilityController.onChange.listen(onSoftKeyboardChanged);
    gFFI.chatModel
        .changeCurrentKey(MessageKey(widget.id, ChatModel.clientModeID));
    _blockableOverlayState.applyFfi(gFFI);
    gFFI.imageModel.addCallbackOnFirstImage((String peerId) {
      gFFI.recordingModel
          .updateStatus(bind.sessionGetIsRecording(sessionId: gFFI.sessionId));
      if (gFFI.recordingModel.start) {
        showToast(translate('Automatically record outgoing sessions'));
      }
      _disableAndroidSoftKeyboard(
          isKeyboardVisible: keyboardVisibilityController.isVisible);
      // Seed shortcut action callbacks once the session is ready, so that
      // global keyboard shortcuts work even if the user never opens the
      // toolbar menu. The returned list is intentionally discarded — the
      // side effect of registering callbacks (inside toolbarControls) is
      // what we want here.
      if (mounted) {
        toolbarControls(context, widget.id, gFFI);
        // Mobile has no DesktopTabController, so tab-switch shortcuts will
        // log a no-handler debug line if a user binds one.
        registerSessionShortcutActions(gFFI);
        _registerMobileChatShortcut();
        registerToolbarShortcuts(context, widget.id, gFFI);
      }
    });
    WidgetsBinding.instance.addObserver(this);

    inputModel.keyboardInputAllowed = true;

    // Wayland sessions may use clipboard-based text input on the controlled side.
    // Require explicit user confirmation before allowing soft-keyboard and
    // clipboard-assisted text input. Physical keyboard events are not gated here.
    _waylandKeyboardGateWorker = ever(gFFI.ffiModel.pi.isSet, (bool isSet) {
      if (isSet) {
        _initWaylandKeyboardGateIfNeeded();
      }
    });
    if (gFFI.ffiModel.pi.isSet.value) {
      _initWaylandKeyboardGateIfNeeded();
    }
  }

  @override
  Future<void> dispose() async {
    HardwareKeyboard.instance.removeHandler(_handleLocalKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    // Close the session up-front. `gFFI.close()` below only calls `sessionClose`
    // after several awaits (canvas save, image update, the `enable_soft_keyboard`
    // platform call), so if the app is backgrounded while this page is disposing,
    // dispose can be suspended before reaching it and the connection is never torn
    // down. The reconnect then re-attaches to the leaked session and is stuck on
    // "Connecting...". Dispatching it here makes teardown happen synchronously on
    // pop; the `sessionClose` in `gFFI.close()` becomes a no-op once removed.
    unawaited(bind.sessionClose(sessionId: sessionId));
    // https://github.com/flutter/flutter/issues/64935
    super.dispose();
    gFFI.dialogManager.hideMobileActionsOverlay(store: false);
    gFFI.inputModel.listenToMouse(false);
    gFFI.imageModel.disposeImage();
    gFFI.cursorModel.disposeImages();
    await gFFI.invokeMethod("enable_soft_keyboard", true);
    _mobileFocusNode.dispose();
    _physicalFocusNode.dispose();
    clearWaylandKeyboardPromptSuppressedForConnection(sessionId.toString());
    _waylandKeyboardGateWorker?.dispose();
    inputModel.keyboardInputAllowed = true;
    await gFFI.close();
    _timer?.cancel();
    _capsuleHoldTimer?.cancel();
    _iosKeyboardWorkaroundTimer?.cancel();
    gFFI.dialogManager.dismissAll();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    WakelockManager.disable(_uniqueKey);
    await keyboardSubscription.cancel();
    removeSharedStates(widget.id);
    // `on_voice_call_closed` should be called when the connection is ended.
    // The inner logic of `on_voice_call_closed` will check if the voice call is active.
    // Only one client is considered here for now.
    gFFI.chatModel.onVoiceCallClosed("End connection");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      trySyncClipboard();
    } else if (state == AppLifecycleState.paused) {
      // Nếu bật "Auto Lock Screen", tự động khóa màn hình máy từ xa khi tắt màn hình iPad / ẩn app
      if (!gFFI.ffiModel.viewOnly &&
          gFFI.ffiModel.keyboard &&
          !gFFI.ffiModel.isPeerAndroid &&
          bind.sessionGetToggleOptionSync(
              sessionId: sessionId, arg: 'lock-after-session-end')) {
        bind.sessionLockScreen(sessionId: sessionId);
      }
    }
  }

  // For client side
  // When swithing from other app to this app, try to sync clipboard.
  void trySyncClipboard() {
    gFFI.invokeMethod("try_sync_clipboard");
  }

  bool _shouldGateKeyboardForWayland() {
    if (!(isAndroid || isIOS)) return false;
    final pi = gFFI.ffiModel.pi;
    return pi.platform == kPeerPlatformLinux && pi.isWayland;
  }

  void _initWaylandKeyboardGateIfNeeded() {
    if (!mounted) return;
    if (_waylandKeyboardGateInitialized) return;
    if (!_shouldGateKeyboardForWayland()) return;

    _waylandKeyboardGateInitialized = true;

    final allowWaylandKeyboard =
        mainGetPeerBoolOptionSync(widget.id, kPeerOptionAllowWaylandKeyboard);
    if (!shouldShowWaylandKeyboardPrompt(
      connectionId: sessionId.toString(),
      isWaylandPeer: _shouldGateKeyboardForWayland(),
      allowWaylandKeyboardRemembered: allowWaylandKeyboard,
    )) {
      inputModel.keyboardInputAllowed = true;
      return;
    }

    inputModel.keyboardInputAllowed = false;

    // Ensure soft keyboard is not active before user confirms.
    _showEdit = false;
    gFFI.invokeMethod("enable_soft_keyboard", false);
    _mobileFocusNode.unfocus();
    _physicalFocusNode.requestFocus();
    setState(() {});
  }

  // to-do: It should be better to use transparent color instead of the bgColor.
  // But for now, the transparent color will cause the canvas to be white.
  // I'm sure that the white color is caused by the Overlay widget in BlockableOverlay.
  // But I don't know why and how to fix it.
  Widget emptyOverlay(Color bgColor) => BlockableOverlay(
        /// the Overlay key will be set with _blockableOverlayState in BlockableOverlay
        /// see override build() in [BlockableOverlay]
        state: _blockableOverlayState,
        underlying: Container(
          color: bgColor,
        ),
      );

  void onSoftKeyboardChanged(bool visible) {
    if (!visible) {
      _showEdit = false;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      // [pi.version.isNotEmpty] -> check ready or not, avoid login without soft-keyboard
      if (gFFI.chatModel.chatWindowOverlayEntry == null &&
          gFFI.ffiModel.pi.version.isNotEmpty) {
        gFFI.invokeMethod("enable_soft_keyboard", false);
      }

      // Workaround for iOS: physical keyboard input fails after virtual keyboard is hidden
      // https://github.com/flutter/flutter/issues/39900
      // https://github.com/rustdesk/rustdesk/discussions/11843#discussioncomment-13499698 - Virtual keyboard issue
      if (isIOS) {
        _iosKeyboardWorkaroundTimer?.cancel();
        _iosKeyboardWorkaroundTimer = Timer(Duration(milliseconds: 100), () {
          if (!mounted || gFFI.chatModel.inputNode.hasFocus) return;
          _physicalFocusNode.unfocus();
          _iosKeyboardWorkaroundTimer = Timer(Duration(milliseconds: 50), () {
            if (!mounted || gFFI.chatModel.inputNode.hasFocus) return;
            _physicalFocusNode.requestFocus();
          });
        });
      }
    } else {
      _showBar = false;
      _showGestureHelp = false;
      _iosKeyboardWorkaroundTimer?.cancel();
      _iosKeyboardWorkaroundTimer = null;
      _timer?.cancel();
      _timer = Timer(kMobileDelaySoftKeyboardFocus, () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
        _mobileFocusNode.requestFocus();
      });
    }
    // update for Scaffold
    setState(() {});
  }

  void _handleIOSSoftKeyboardInput(String newValue) {
    var oldValue = _value;
    _value = newValue;
    var i = newValue.length - 1;
    for (; i >= 0 && newValue[i] != '1'; --i) {}
    var j = oldValue.length - 1;
    for (; j >= 0 && oldValue[j] != '1'; --j) {}
    if (i < j) j = i;
    var subNewValue = newValue.substring(j + 1);
    var subOldValue = oldValue.substring(j + 1);

    // get common prefix of subNewValue and subOldValue
    var common = 0;
    for (;
        common < subOldValue.length &&
            common < subNewValue.length &&
            subNewValue[common] == subOldValue[common];
        ++common) {}

    // get newStr from subNewValue
    var newStr = "";
    if (subNewValue.length > common) {
      newStr = subNewValue.substring(common);
    }

    // Set the value to the old value and early return if is still composing. (1 && 2)
    // 1. The composing range is valid
    // 2. The new string is shorter than the composing range.
    // Lưu ý: Không chặn khi đang gõ ký tự ASCII thuần (bàn phím tiếng Anh trên iPad gõ Telex/VNI cho Mac)
    final isPureAscii = newStr.isNotEmpty &&
        newStr.codeUnits.every((u) => u < 128) &&
        subOldValue.codeUnits.every((u) => u < 128);
    if (!isPureAscii && _textController.value.isComposingRangeValid) {
      final composingLength = _textController.value.composing.end -
          _textController.value.composing.start;
      if (composingLength > newStr.length) {
        _value = oldValue;
        return;
      }
    }

    // Delete the different part in the old value.
    for (i = 0; i < subOldValue.length - common; ++i) {
      _sendSoftKeyBackspace();
    }

    // Input the new string.
    if (newStr.isEmpty) {
      return;
    }
    if (newStr.codeUnits.every((u) => u < 128)) {
      for (int k = 0; k < newStr.length; ++k) {
        inputChar(newStr[k]);
      }
    } else if (newStr.length > 1) {
      bind.sessionInputString(sessionId: sessionId, value: newStr);
    } else {
      inputChar(newStr);
    }
  }

  void _handleNonIOSSoftKeyboardInput(String newValue) {
    var oldValue = _value;
    _value = newValue;
    if (oldValue.isNotEmpty &&
        newValue.isNotEmpty &&
        oldValue[0] == '1' &&
        newValue[0] != '1') {
      // clipboard
      oldValue = '';
    }
    // This length-only diff assumes the IME appends at the end. If an IME
    // leaves the caret inside paired punctuation, later insertions can replay
    // the closing symbol: "()" -> "(a)" sends ")" instead of "a". This is a
    // client text-diff issue, independent of the host keyboard layout.
    if (newValue.length == oldValue.length) {
      // ?
    } else if (newValue.length < oldValue.length) {
      final char = 'VK_BACK';
      inputModel.inputKey(char);
    } else {
      final content = newValue.substring(oldValue.length);
      if (content.length > 1) {
        if (oldValue != '' &&
            content.length == 2 &&
            (content == '""' ||
                content == '()' ||
                content == '[]' ||
                content == '<>' ||
                content == "{}" ||
                content == '”“' ||
                content == '《》' ||
                content == '（）' ||
                content == '【】')) {
          // can not only input content[0], because when input ], [ are also auo insert, which cause ] never be input
          bind.sessionInputString(sessionId: sessionId, value: content);
          _openKeyboardUnlocked();
          return;
        }
        bind.sessionInputString(sessionId: sessionId, value: content);
      } else {
        inputChar(content);
      }
    }
  }

  // handle mobile virtual keyboard
  void handleSoftKeyboardInput(String newValue) {
    if (!inputModel.keyboardInputAllowed) {
      return;
    }
    if (isIOS) {
      _handleIOSSoftKeyboardInput(newValue);
    } else {
      _handleNonIOSSoftKeyboardInput(newValue);
    }
  }

  bool get _hasStickyMobileModifier =>
      inputModel.alt ||
      inputModel.ctrl ||
      inputModel.shift ||
      inputModel.command;

  void _sendSoftKeyBackspace() {
    if (!inputModel.keyboardInputAllowed) return;
    if (!_hasStickyMobileModifier && !gFFI.ffiModel.isPeerAndroid) {
      // Gửi mã phím phần cứng USB HID Backspace (0x002a -> kVK_Delete trên macOS)
      // để bộ gõ tiếng Việt trên Mac xử lý xóa dấu/chữ chuẩn xác như bàn phím cứng
      inputModel.newKeyboardMode('', 0x002a, true, false);
      inputModel.newKeyboardMode('', 0x002a, false, false);
      return;
    }
    inputModel.inputKey('VK_BACK');
  }

  bool _trySendAsciiUsbHidKey(String char) {
    if (char.length != 1 || _hasStickyMobileModifier || gFFI.ffiModel.isPeerAndroid) {
      return false;
    }
    final int code = char.codeUnitAt(0);
    int? usbHid;
    bool needsShift = false;

    if (code >= 97 && code <= 122) {
      // 'a'..'z' -> 0x0004..0x001d
      usbHid = 0x0004 + (code - 97);
    } else if (code >= 65 && code <= 90) {
      // 'A'..'Z' -> 0x0004..0x001d + Shift
      usbHid = 0x0004 + (code - 65);
      needsShift = true;
    } else if (code >= 49 && code <= 57) {
      // '1'..'9' -> 0x001e..0x0026
      usbHid = 0x001e + (code - 49);
    } else if (code == 48) {
      // '0' -> 0x0027
      usbHid = 0x0027;
    } else {
      switch (char) {
        case '\n':
          usbHid = 0x0028; // Enter
          break;
        case '\t':
          usbHid = 0x002b; // Tab
          break;
        case ' ':
          usbHid = 0x002c; // Space
          break;
        case '-':
          usbHid = 0x002d;
          break;
        case '_':
          usbHid = 0x002d;
          needsShift = true;
          break;
        case '=':
          usbHid = 0x002e;
          break;
        case '+':
          usbHid = 0x002e;
          needsShift = true;
          break;
        case '[':
          usbHid = 0x002f;
          break;
        case '{':
          usbHid = 0x002f;
          needsShift = true;
          break;
        case ']':
          usbHid = 0x0030;
          break;
        case '}':
          usbHid = 0x0030;
          needsShift = true;
          break;
        case '\\':
          usbHid = 0x0031;
          break;
        case '|':
          usbHid = 0x0031;
          needsShift = true;
          break;
        case ';':
          usbHid = 0x0033;
          break;
        case ':':
          usbHid = 0x0033;
          needsShift = true;
          break;
        case '\'':
          usbHid = 0x0034;
          break;
        case '"':
          usbHid = 0x0034;
          needsShift = true;
          break;
        case '`':
          usbHid = 0x0035;
          break;
        case '~':
          usbHid = 0x0035;
          needsShift = true;
          break;
        case ',':
          usbHid = 0x0036;
          break;
        case '<':
          usbHid = 0x0036;
          needsShift = true;
          break;
        case '.':
          usbHid = 0x0037;
          break;
        case '>':
          usbHid = 0x0037;
          needsShift = true;
          break;
        case '/':
          usbHid = 0x0038;
          break;
        case '?':
          usbHid = 0x0038;
          needsShift = true;
          break;
        case '!':
          usbHid = 0x001e;
          needsShift = true;
          break;
        case '@':
          usbHid = 0x001f;
          needsShift = true;
          break;
        case '#':
          usbHid = 0x0020;
          needsShift = true;
          break;
        case '\$':
          usbHid = 0x0021;
          needsShift = true;
          break;
        case '%':
          usbHid = 0x0022;
          needsShift = true;
          break;
        case '^':
          usbHid = 0x0023;
          needsShift = true;
          break;
        case '&':
          usbHid = 0x0024;
          needsShift = true;
          break;
        case '*':
          usbHid = 0x0025;
          needsShift = true;
          break;
        case '(':
          usbHid = 0x0026;
          needsShift = true;
          break;
        case ')':
          usbHid = 0x0027;
          needsShift = true;
          break;
      }
    }

    if (usbHid == null) return false;

    if (needsShift) {
      inputModel.newKeyboardMode('', 0x00e1, true, false);
    }
    inputModel.newKeyboardMode(char, usbHid, true, false);
    inputModel.newKeyboardMode(char, usbHid, false, false);
    if (needsShift) {
      inputModel.newKeyboardMode('', 0x00e1, false, false);
    }
    return true;
  }

  void inputChar(String char) {
    if (!inputModel.keyboardInputAllowed || char.isEmpty) {
      return;
    }
    if (_trySendAsciiUsbHidKey(char)) {
      return;
    }
    if (char == '\n') {
      char = 'VK_RETURN';
    } else if (char == ' ') {
      char = 'VK_SPACE';
    }
    inputModel.inputKey(char);
  }

  void openKeyboard() {
    final allowWaylandKeyboard =
        mainGetPeerBoolOptionSync(widget.id, kPeerOptionAllowWaylandKeyboard);
    if (shouldShowWaylandKeyboardPrompt(
      connectionId: sessionId.toString(),
      isWaylandPeer: _shouldGateKeyboardForWayland(),
      allowWaylandKeyboardRemembered: allowWaylandKeyboard,
    )) {
      inputModel.keyboardInputAllowed = false;
      showWaylandKeyboardInputWarningDialog(
        id: widget.id,
        connectionId: sessionId.toString(),
        ffi: gFFI,
        onEnable: () async {
          _openKeyboardUnlocked();
        },
      );
      return;
    }
    _openKeyboardUnlocked();
  }

  void _openKeyboardUnlocked() {
    inputModel.keyboardInputAllowed = true;
    gFFI.invokeMethod("enable_soft_keyboard", true);
    // destroy first, so that our _value trick can work
    _value = initText;
    _textController.text = _value;
    setState(() {
      _showEdit = false;
      _showBar = false;
      _showGestureHelp = false;
      _showMousePanel = false;
      _mousePanelSubPage = 0;
    });
    _timer?.cancel();
    _timer = Timer(kMobileDelaySoftKeyboard, () {
      // show now, and sleep a while to requestFocus to
      // make sure edit ready, so that keyboard won't show/hide/show/hide happen
      setState(() {
        _showEdit = true;
        _showBar = false;
        _showGestureHelp = false;
        _showMousePanel = false;
        _mousePanelSubPage = 0;
      });
      _timer?.cancel();
      _timer = Timer(kMobileDelaySoftKeyboardFocus, () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
        _mobileFocusNode.requestFocus();
      });
    });
  }

  Widget _bottomWidget() => const Offstage();

  void _hideSoftKeyboard() {
    _timer?.cancel();
    _iosKeyboardWorkaroundTimer?.cancel();
    setState(() {
      _showEdit = false;
      _showBar = false;
      _showGestureHelp = false;
      _showMousePanel = false;
      _mousePanelSubPage = 0;
    });
    gFFI.chatModel.softKeyboardRequested.value = false;
    gFFI.invokeMethod("enable_soft_keyboard", false);
    _mobileFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    _physicalFocusNode.requestFocus();
  }

  /// 1. Viên thuốc nổi (Capsule Pill):
  /// - Mặc định nằm ở góc dưới bên phải, ấn giữ (long-press) để di chuyển tự do.
  /// - Nửa trái mở bàn phím ảo, nửa phải mở thanh công cụ ở giữa.
  /// - Tự động ẩn khi bàn phím ảo đang mở hoặc khi thanh công cụ đang mở.
  Widget _buildDeskInCapsulePill(bool keyboardIsVisible) {
    final ffiModel = Provider.of<FfiModel>(context);
    if (isWebDesktop ||
        ffiModel.pi.displays.isEmpty ||
        keyboardIsVisible ||
        _showBar) {
      return const Offstage();
    }
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight =
        media.size.height - media.padding.top - media.viewInsets.bottom;

    final double maxRight = (screenWidth - 96.0).clamp(12.0, 2000.0).toDouble();
    final double maxBottom =
        (screenHeight - 56.0).clamp(12.0, 2000.0).toDouble();
    const double minBottom = 12.0;
    final double effectiveRight =
        _floatingBarRight.clamp(12.0, maxRight).toDouble();
    final double effectiveBottom = _floatingBarBottom
        .clamp(minBottom, max(minBottom, maxBottom))
        .toDouble();

    return Positioned(
      right: effectiveRight,
      bottom: effectiveBottom,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (_capsuleActivePointer != null) return;
          _capsuleActivePointer = event.pointer;
          _capsuleDownGlobalPos = event.position;
          _lastBarDragGlobalPos = event.position;
          // Nửa trái (~44px đầu) là nút mở bàn phím, nửa phải là nút mở thanh công cụ
          _capsuleDownIsLeftHalf = event.localPosition.dx < 44.0;
          setState(() {
            _capsuleIsPressing = true;
            _floatingBarRight = effectiveRight;
            _floatingBarBottom = effectiveBottom;
          });
          _capsuleHoldTimer?.cancel();
          _capsuleHoldTimer = Timer(const Duration(milliseconds: 240), () {
            if (!mounted || _capsuleActivePointer != event.pointer) return;
            HapticFeedback.mediumImpact();
            setState(() {
              _isDraggingBar = true;
            });
          });
        },
        onPointerMove: (event) {
          if (event.pointer != _capsuleActivePointer) return;
          if (!_isDraggingBar) {
            final movedDist = (event.position - _capsuleDownGlobalPos).distance;
            if (movedDist > 8.0) {
              _capsuleHoldTimer?.cancel();
              HapticFeedback.mediumImpact();
              setState(() {
                _isDraggingBar = true;
              });
            } else {
              return;
            }
          }
          final delta = event.position - _lastBarDragGlobalPos;
          _lastBarDragGlobalPos = event.position;
          setState(() {
            _floatingBarRight =
                (_floatingBarRight - delta.dx).clamp(12.0, maxRight).toDouble();
            _floatingBarBottom = (_floatingBarBottom - delta.dy)
                .clamp(minBottom, max(minBottom, maxBottom))
                .toDouble();
          });
        },
        onPointerUp: (event) {
          if (event.pointer != _capsuleActivePointer) return;
          _capsuleHoldTimer?.cancel();
          final wasDragging = _isDraggingBar;
          final tapLeft = _capsuleDownIsLeftHalf;
          _capsuleActivePointer = null;
          setState(() {
            _isDraggingBar = false;
            _capsuleIsPressing = false;
          });
          HapticFeedback.selectionClick();
          if (!wasDragging) {
            if (tapLeft) {
              openKeyboard();
            } else {
              setState(() => _showBar = true);
            }
          }
        },
        onPointerCancel: (event) {
          if (event.pointer != _capsuleActivePointer) return;
          _capsuleHoldTimer?.cancel();
          _capsuleActivePointer = null;
          setState(() {
            _isDraggingBar = false;
            _capsuleIsPressing = false;
          });
        },
        child: AnimatedScale(
          scale: _isDraggingBar ? 1.10 : (_capsuleIsPressing ? 0.96 : 1.0),
          duration: const Duration(milliseconds: 130),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _isDraggingBar
                    ? const Color(0xFF2F80ED)
                    : const Color(0xFFCBD5E1),
                width: _isDraggingBar ? 2.0 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isDraggingBar ? 0.45 : 0.34),
                  blurRadius: _isDraggingBar ? 16 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nửa trái: Mở bàn phím (Nền trắng đồng nhất, chỉ nháy nhẹ khi đang bấm)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_capsuleIsPressing &&
                            !_isDraggingBar &&
                            _capsuleDownIsLeftHalf)
                        ? const Color(0xFFE2E8F0)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(20),
                    ),
                  ),
                  child: const Icon(
                    Icons.keyboard_alt_outlined,
                    color: Color(0xFF1E293B),
                    size: 18,
                  ),
                ),
                // Vách ngăn mảnh ở giữa viên thuốc
                Container(
                  width: 1,
                  height: 18,
                  color: const Color(0xFFCBD5E1),
                ),
                // Nửa phải: Mở thanh công cụ ở giữa
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_capsuleIsPressing &&
                            !_isDraggingBar &&
                            !_capsuleDownIsLeftHalf)
                        ? const Color(0xFFE2E8F0)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.apps_rounded,
                          color: Color(0xFF1E293B), size: 17),
                      SizedBox(width: 2),
                      Icon(Icons.expand_more_rounded,
                          color: Color(0xFF475569), size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 2. Thanh công cụ riêng biệt (Centered Toolbar - Tông Trắng Sáng & Xanh DeskIn nổi bật):
  /// - Luôn nằm ở chính giữa màn hình thay vì góc màn hình.
  /// - Nền trắng mờ sắc nét (Frosted White) kèm viền và đổ bóng sâu giúp nổi bật hoàn toàn trên nền tối của IDE/Mac.
  /// - Khi mở bàn phím ảo (keyboardIsVisible == true) thì tự động ẩn và không cho mở.
  Widget _buildDeskInCenteredToolbar(bool keyboardIsVisible, double topInset) {
    final ffiModel = Provider.of<FfiModel>(context);
    if (isWebDesktop ||
        ffiModel.pi.displays.isEmpty ||
        !_showBar ||
        keyboardIsVisible) {
      return const Offstage();
    }
    final pi = ffiModel.pi;
    final hasMultiDisplays = pi.displays.length > 1;
    final screenWidth = MediaQuery.of(context).size.width;
    const activeBlue = Color(0xFF2F80ED);
    const defaultIconColor = Color(0xFF1E293B);

    Widget buildToolBtn({
      required IconData icon,
      String? label,
      bool active = false,
      Color? iconColor,
      Color? bgColor,
      required VoidCallback onTap,
    }) {
      final effectiveFg =
          active ? Colors.white : (iconColor ?? defaultIconColor);
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: active ? activeBlue : (bgColor ?? Colors.transparent),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effectiveFg, size: 19),
              if (label != null) ...[
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: effectiveFg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Positioned(
      top: topInset + 10,
      left: 12,
      right: 12,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max(200.0, screenWidth - 24.0)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.96),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.36),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Ô duy nhất chọn & cài đặt Chuột / Cảm ứng (DeskIn Mouse/Touch Panel)
                  if (!ffiModel.viewOnly &&
                      ffiModel.keyboard &&
                      !ffiModel.isPeerAndroid)
                    buildToolBtn(
                      icon: ffiModel.touchMode
                          ? Icons.touch_app_rounded
                          : Icons.mouse_rounded,
                      label: ffiModel.touchMode ? 'Touch' : 'Mouse',
                      active: _showMousePanel,
                      onTap: () {
                        setState(() {
                          _showMousePanel = !_showMousePanel;
                          _mousePanelSubPage = 0;
                        });
                      },
                    ),
                  const SizedBox(width: 2),
                  // 2. Open Soft Keyboard (automatically closes toolbar)
                  if (!ffiModel.viewOnly && ffiModel.keyboard)
                    buildToolBtn(
                      icon: Icons.keyboard_alt_outlined,
                      label: 'Keyboard',
                      onTap: () {
                        openKeyboard();
                      },
                    ),
                  // 3. Switch Monitor quickly if multi-display
                  if (hasMultiDisplays)
                    buildToolBtn(
                      icon: Icons.desktop_windows_rounded,
                      label: '${pi.currentDisplay + 1}/${pi.displays.length}',
                      onTap: () {
                        final next =
                            (pi.currentDisplay + 1) % pi.displays.length;
                        openMonitorInTheSameTab(next, gFFI, pi);
                        setState(() {});
                      },
                    ),
                  // 4. Display & Quality Options
                  buildToolBtn(
                    icon: Icons.tv_rounded,
                    label: 'Screen',
                    onTap: () {
                      setState(() {
                        _showEdit = false;
                        _showMousePanel = false;
                      });
                      showOptions(context, widget.id, gFFI.dialogManager);
                    },
                  ),
                  // 5. More Actions (Ctrl+Alt+Del, Lock, Transfer, etc.)
                  buildToolBtn(
                    icon: Icons.layers_outlined,
                    label: 'Action',
                    onTap: () {
                      setState(() {
                        _showEdit = false;
                        _showMousePanel = false;
                      });
                      showActions(widget.id);
                    },
                  ),
                  const SizedBox(width: 2),
                  // 6. Disconnect (Nút đỏ End nổi bật giống DeskIn)
                  buildToolBtn(
                    icon: Icons.power_settings_new_rounded,
                    label: 'End',
                    iconColor: const Color(0xFFDC2626),
                    bgColor: const Color(0xFFFEE2E2),
                    onTap: () => clientClose(sessionId, gFFI),
                  ),
                  const SizedBox(width: 2),
                  // 7. Collapse toolbar
                  buildToolBtn(
                    icon: Icons.expand_less_rounded,
                    iconColor: const Color(0xFF64748B),
                    onTap: () => setState(() {
                      _showBar = false;
                      _showGestureHelp = false;
                      _showMousePanel = false;
                      _mousePanelSubPage = 0;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 3. Panel cài đặt Chuột & Cảm ứng chuẩn DeskIn (DeskIn Mouse / Touch Popover Panel):
  /// - Bấm vào nút Mouse/Touch trên thanh công cụ sẽ xổ ra panel chọn giữa Touch và Cursor.
  /// - Ở Touch mode: Show Virtual Mouse (+ cỡ chuột ảo), Show Remote Cursor, Operation Guide, Show Shortcuts.
  /// - Ở Cursor mode: Mouse Settings, Show Virtual Mouse (2 nút L/R), Show Virtual Scroll Wheel, Show Remote Cursor, Operation Guide, Show Shortcuts.
  Widget _buildDeskInMousePanel(bool keyboardIsVisible, double topInset) {
    final ffiModel = Provider.of<FfiModel>(context);
    if (isWebDesktop ||
        ffiModel.pi.displays.isEmpty ||
        !_showBar ||
        !_showMousePanel ||
        keyboardIsVisible) {
      return const Offstage();
    }

    final isTouch = ffiModel.touchMode;
    final virtualMouseMode = ffiModel.virtualMouseMode;
    final remoteCursorState = ShowRemoteCursorState.find(widget.id);
    final showRemoteCursor = remoteCursorState.value;
    const activeBlue = Color(0xFF2F80ED);
    const textDark = Color(0xFF1F2329);
    const textMuted = Color(0xFF646A73);
    const dividerThin = Color(0xFFEBEEF5);
    const dividerSection = Color(0xFFF2F4F7);

    void selectMode(bool wantTouch) {
      if (ffiModel.touchMode == wantTouch) return;
      HapticFeedback.selectionClick();
      setState(() {
        gFFI.ffiModel.toggleTouchMode();
        final v = gFFI.ffiModel.touchMode ? 'Y' : 'N';
        bind.mainSetLocalOption(key: kOptionTouchMode, value: v);
        if (gFFI.ffiModel.touchMode) {
          inputModel.setRelativeMouseMode(false);
          if (remoteCursorState.value) {
            bind.sessionToggleOption(
                sessionId: sessionId, value: 'show-remote-cursor');
            remoteCursorState.value = false;
          }
        }
      });
    }

    Widget buildRadioDot(bool selected) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? activeBlue : const Color(0xFFC9CDD4),
            width: selected ? 2.0 : 1.6,
          ),
        ),
        alignment: Alignment.center,
        child: selected
            ? Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeBlue,
                ),
              )
            : null,
      );
    }

    Widget buildSwitchRow({
      required String title,
      IconData? leadingIcon,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 19, color: const Color(0xFF4E5969)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.86,
                child: CupertinoSwitch(
                  value: value,
                  activeColor: activeBlue,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    onChanged(v);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildNavRow({
      required String title,
      IconData? leadingIcon,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 19, color: const Color(0xFF4E5969)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF8F959E),
                size: 22,
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSubPageHeader(String title) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: dividerThin, width: 1)),
        ),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _mousePanelSubPage = 0);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.arrow_back_ios_new_rounded,
                        size: 16, color: activeBlue),
                    SizedBox(width: 4),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: activeBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 58),
          ],
        ),
      );
    }

    Widget buildMainPage() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Touch vs Cursor Radio Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => selectMode(true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          buildRadioDot(isTouch),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.touch_app_rounded,
                            size: 26,
                            color: isTouch
                                ? activeBlue
                                : const Color(0xFF8F959E),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Touch',
                            style: TextStyle(
                              color: isTouch ? textDark : textMuted,
                              fontSize: 16,
                              fontWeight:
                                  isTouch ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => selectMode(false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          buildRadioDot(!isTouch),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.near_me_rounded,
                            size: 26,
                            color: !isTouch
                                ? activeBlue
                                : const Color(0xFF8F959E),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Cursor',
                            style: TextStyle(
                              color: !isTouch ? textDark : textMuted,
                              fontSize: 16,
                              fontWeight:
                                  !isTouch ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: dividerThin),
          if (!isTouch) ...[
            // Cursor Mode Options (giống hệt ảnh DeskIn)
            buildNavRow(
              title: 'Mouse Settings',
              onTap: () => setState(() => _mousePanelSubPage = 1),
            ),
            const Divider(
                height: 1, thickness: 1, indent: 18, endIndent: 18, color: dividerThin),
            buildSwitchRow(
              title: 'Show Virtual Mouse',
              value: virtualMouseMode.showVirtualMouse,
              onChanged: (_) async {
                await virtualMouseMode.toggleVirtualMouse();
                if (!virtualMouseMode.showVirtualMouse) {
                  inputModel.setRelativeMouseMode(false);
                }
                setState(() {});
              },
            ),
            const Divider(
                height: 1, thickness: 1, indent: 18, endIndent: 18, color: dividerThin),
            buildSwitchRow(
              title: 'Show Virtual Scroll Wheel',
              value: virtualMouseMode.showVirtualScrollWheel,
              onChanged: (_) async {
                await virtualMouseMode.toggleVirtualScrollWheel();
                setState(() {});
              },
            ),
            const Divider(
                height: 1, thickness: 1, indent: 18, endIndent: 18, color: dividerThin),
            buildSwitchRow(
              title: 'Show Remote Cursor',
              value: showRemoteCursor,
              onChanged: (_) async {
                await bind.sessionToggleOption(
                    sessionId: sessionId, value: 'show-remote-cursor');
                remoteCursorState.value = bind.sessionGetToggleOptionSync(
                    sessionId: sessionId, arg: 'show-remote-cursor');
                setState(() {});
              },
            ),
            const Divider(
                height: 1, thickness: 1, indent: 18, endIndent: 18, color: dividerThin),
            buildNavRow(
              title: 'Operation Guide',
              onTap: () => setState(() {
                _operationGuideIsTouchPage = false;
                _showOperationGuideOverlay = true;
              }),
            ),
          ] else ...[
            // Touch Mode Options (mặc định tắt Show Virtual Mouse như DeskIn)
            buildSwitchRow(
              title: 'Show Virtual Mouse',
              value: virtualMouseMode.showTouchVirtualMouse,
              onChanged: (_) async {
                await virtualMouseMode.toggleTouchVirtualMouse();
                setState(() {});
              },
            ),
            if (virtualMouseMode.showTouchVirtualMouse)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Row(
                  children: [
                    const Text(
                      'Size',
                      style: TextStyle(color: textMuted, fontSize: 13),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: activeBlue,
                          thumbColor: activeBlue,
                          inactiveTrackColor: const Color(0xFFDDE2E9),
                        ),
                        child: Slider(
                          value: virtualMouseMode.virtualMouseScale,
                          min: 0.8,
                          max: 1.8,
                          divisions: 10,
                          onChanged: (v) {
                            virtualMouseMode.setVirtualMouseScale(v);
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    Text(
                      '${(virtualMouseMode.virtualMouseScale * 100).round()}%',
                      style: const TextStyle(
                        color: textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(
                height: 1, thickness: 1, indent: 18, endIndent: 18, color: dividerThin),
            buildNavRow(
              title: 'Operation Guide',
              onTap: () => setState(() {
                _operationGuideIsTouchPage = true;
                _showOperationGuideOverlay = true;
              }),
            ),
          ],
          Container(height: 7, color: dividerSection),
          buildSwitchRow(
            title: 'Show Shortcuts',
            leadingIcon: Icons.shortcut_rounded,
            value: _alwaysShowShortcuts,
            onChanged: (v) {
              setState(() => _alwaysShowShortcuts = v);
            },
          ),
          const Divider(
              height: 1,
              thickness: 1,
              indent: 18,
              endIndent: 18,
              color: dividerThin),
          buildNavRow(
            title: 'Customize Shortcuts',
            leadingIcon: Icons.tune_rounded,
            onTap: () {
              setState(() {
                _showMousePanel = false;
              });
              showDeskInShortcutModal(context, gFFI);
            },
          ),
          if (!ffiModel.viewOnly &&
              ffiModel.keyboard &&
              !ffiModel.isPeerAndroid) ...[
            const Divider(
                height: 1,
                thickness: 1,
                indent: 18,
                endIndent: 18,
                color: dividerThin),
            buildSwitchRow(
              title: 'Auto Lock Screen',
              leadingIcon: Icons.lock_outline_rounded,
              value: bind.sessionGetToggleOptionSync(
                  sessionId: sessionId, arg: 'lock-after-session-end'),
              onChanged: (_) async {
                await bind.sessionToggleOption(
                    sessionId: sessionId, value: 'lock-after-session-end');
                setState(() {});
              },
            ),
          ],
        ],
      );
    }

    Widget buildMouseSettingsPage() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildSubPageHeader('Mouse Settings'),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cursor Speed',
                      style: TextStyle(
                        color: textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${virtualMouseMode.cursorSpeed.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: activeBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Slow',
                        style: TextStyle(color: textMuted, fontSize: 12)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: activeBlue,
                          thumbColor: activeBlue,
                          inactiveTrackColor: const Color(0xFFDDE2E9),
                        ),
                        child: Slider(
                          value: virtualMouseMode.cursorSpeed,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          onChanged: (v) {
                            virtualMouseMode.setCursorSpeed(v);
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    const Text('Fast',
                        style: TextStyle(color: textMuted, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(
              height: 1, thickness: 1, indent: 18, endIndent: 18, color: dividerThin),
          buildSwitchRow(
            title: 'Show Virtual Joystick',
            value: virtualMouseMode.showVirtualJoystick,
            onChanged: (_) async {
              await virtualMouseMode.toggleVirtualJoystick();
              if (!virtualMouseMode.showVirtualJoystick) {
                inputModel.setRelativeMouseMode(false);
              }
              setState(() {});
            },
          ),
          if (virtualMouseMode.showVirtualJoystick) ...[
            const Divider(
                height: 1, thickness: 1, indent: 18, endIndent: 18, color: dividerThin),
            buildSwitchRow(
              title: 'Relative Mouse Mode',
              value: inputModel.relativeMouseMode.value,
              onChanged: (v) {
                inputModel.setRelativeMouseMode(v);
                setState(() {});
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
      );
    }

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Bấm ra ngoài panel để đóng
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              setState(() {
                _showMousePanel = false;
                _mousePanelSubPage = 0;
              });
            },
            child: const SizedBox.expand(),
          ),
          Positioned(
            top: topInset + 56,
            left: 16,
            right: 16,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 345,
                    maxHeight: max(
                        220.0, MediaQuery.of(context).size.height - topInset - 72),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.28),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: _mousePanelSubPage == 1
                          ? buildMouseSettingsPage()
                          : buildMainPage(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 4. Màn hình hướng dẫn cử chỉ toàn màn hình chuẩn DeskIn (Tip – Touch Mode / Cursor Mode Gestures):
  /// - Hiển thị 6 thẻ trắng lớn (3 cột x 2 hàng) với biểu tượng trực quan "[ Cử chỉ ] = [ Tác vụ ]".
  /// - Có nút chuyển trang giữa Touch Mode và Cursor Mode + nút Close màu xanh DeskIn.
  Widget _buildDeskInOperationGuideOverlay(double topInset) {
    if (!_showOperationGuideOverlay) {
      return const Offstage();
    }
    const activeBlue = Color(0xFF2F80ED);
    const textDark = Color(0xFF1F2329);
    final isTouchPage = _operationGuideIsTouchPage;

    final cards = isTouchPage
        ? <Map<String, dynamic>>[
            {
              'leftLabel': 'Click',
              'rightLabel': 'Left click',
              'leftIcon': GestureIcons.iconGestureTap,
              'rightIcon': Icons.mouse_outlined,
            },
            {
              'leftLabel': 'Hold and click',
              'rightLabel': 'Right click',
              'leftIcon': GestureIcons.iconGesturePressHold,
              'rightIcon': Icons.mouse_outlined,
            },
            {
              'leftLabel': 'Short press and drag',
              'rightLabel': 'Drag position',
              'leftIcon': GestureIcons.iconGestureFSwipeRight,
              'rightIcon': Icons.file_copy_outlined,
            },
            {
              'leftLabel': 'Two-finger swipe',
              'rightLabel': 'Window scrolling',
              'leftIcon': GestureIcons.iconGestureFDrag,
              'rightIcon': Icons.swap_vert_rounded,
            },
            {
              'leftLabel': 'Pinch with two fingers',
              'rightLabel': 'Zoom',
              'leftIcon': GestureIcons.iconGesturePinch,
              'rightIcon': Icons.open_in_full_rounded,
            },
            {
              'leftLabel': 'Three-finger swipe',
              'rightLabel': 'Switch screen',
              'leftIcon': GestureIcons.iconGestureFThreeFingers,
              'rightIcon': Icons.view_column_outlined,
            },
          ]
        : <Map<String, dynamic>>[
            {
              'leftLabel': 'One-finger move',
              'rightLabel': 'Move cursor',
              'leftIcon': GestureIcons.iconGestureFSwipeRight,
              'rightIcon': Icons.near_me_rounded,
            },
            {
              'leftLabel': 'Click / L button',
              'rightLabel': 'Left click',
              'leftIcon': GestureIcons.iconGestureTap,
              'rightIcon': Icons.mouse_outlined,
            },
            {
              'leftLabel': 'Hold L + Move finger',
              'rightLabel': 'Select text / Drag',
              'leftIcon': GestureIcons.iconGesturePressHold,
              'rightIcon': Icons.text_fields_rounded,
            },
            {
              'leftLabel': 'Two-finger swipe',
              'rightLabel': 'Window scrolling',
              'leftIcon': GestureIcons.iconGestureFDrag,
              'rightIcon': Icons.swap_vert_rounded,
            },
            {
              'leftLabel': 'Pinch with two fingers',
              'rightLabel': 'Zoom',
              'leftIcon': GestureIcons.iconGesturePinch,
              'rightIcon': Icons.open_in_full_rounded,
            },
            {
              'leftLabel': 'Three-finger swipe',
              'rightLabel': 'Switch screen',
              'leftIcon': GestureIcons.iconGestureFThreeFingers,
              'rightIcon': Icons.view_column_outlined,
            },
          ];

    Widget buildGestureCard(Map<String, dynamic> card, double cardWidth) {
      final isSwitchScreen = card['rightLabel'] == 'Switch screen';
      return Container(
        width: cardWidth,
        height: 126,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    card['leftLabel'] as String,
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  card['rightLabel'] as String,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      card['leftIcon'] as IconData,
                      size: 32,
                      color: activeBlue,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      '=',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    alignment: Alignment.center,
                    child: isSwitchScreen
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: textDark, width: 1.4),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '1',
                                  style: TextStyle(
                                    color: textDark,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: textDark,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '2',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Icon(
                            card['rightIcon'] as IconData,
                            size: 28,
                            color: textDark,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = max(320.0, screenWidth - 48.0);
    final cols = screenWidth >= 640 ? 3 : 2;
    final cardWidth =
        ((availableWidth - (cols - 1) * 16.0) / cols).clamp(150.0, 290.0).toDouble();

    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.76),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar: Close X + Title
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _showOperationGuideOverlay = false);
                      },
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 28),
                    ),
                    Expanded(
                      child: Text(
                        isTouchPage
                            ? 'Tip – Touch Mode Gestures'
                            : 'Tip – Cursor Mode Gestures',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Center 6 gesture cards
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: cards
                          .map((c) => buildGestureCard(c, cardWidth))
                          .toList(),
                    ),
                  ),
                ),
              ),
              // Page dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isTouchPage ? Colors.white : Colors.white38,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !isTouchPage ? Colors.white : Colors.white38,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Bottom buttons: Previous/Next page + Close
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70, width: 1),
                        minimumSize: const Size(124, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _operationGuideIsTouchPage =
                              !_operationGuideIsTouchPage;
                        });
                      },
                      child: Text(
                        isTouchPage ? 'Cursor page' : 'Previous page',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(124, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _showOperationGuideOverlay = false);
                      },
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final keyboardIsVisible =
        (keyboardVisibilityController.isVisible || viewInsetsBottom > 80) &&
            (_showEdit || gFFI.chatModel.softKeyboardRequested.value);

    return WillPopScope(
      onWillPop: () async {
        clientClose(sessionId, gFFI);
        return false;
      },
      child: Scaffold(
          extendBody: true,
          bottomNavigationBar: Obx(() => Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  gFFI.ffiModel.pi.isSet.isTrue &&
                          gFFI.ffiModel.waitForFirstImage.isTrue
                      ? emptyOverlay(MyTheme.canvasColor)
                      : () {
                          gFFI.ffiModel.tryShowAndroidActionsOverlay();
                          return Offstage();
                        }(),
                  _bottomWidget(),
                  gFFI.ffiModel.pi.isSet.isFalse
                      ? emptyOverlay(MyTheme.canvasColor)
                      : Offstage(),
                ],
              )),
          body: Obx(
            () => getRawPointerAndKeyBody(
              Container(
                color: kColorCanvas,
                child: isWebDesktop
                    ? getBodyForDesktopWithListener()
                    : OrientationBuilder(builder: (ctx, orientation) {
                        if (_currentOrientation != orientation) {
                          Timer(const Duration(milliseconds: 200), () {
                            gFFI.dialogManager
                                .resetMobileActionsOverlay(ffi: gFFI);
                            _currentOrientation = orientation;
                            gFFI.canvasModel.updateViewStyle();
                          });
                        }
                        final chatKeyboardRequested =
                            gFFI.chatModel.softKeyboardRequested.value;
                        final kbActive =
                            (keyboardVisibilityController.isVisible ||
                                    viewInsetsBottom > 80) &&
                                (_showEdit || chatKeyboardRequested);
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              color: MyTheme.canvasColor,
                              child: inputModel.isPhysicalMouse.value
                                  ? getBodyForMobile()
                                  : RawTouchGestureDetectorRegion(
                                      child: getBodyForMobile(),
                                      ffi: gFFI,
                                    ),
                            ),
                            if (gFFI.ffiModel.touchMode)
                              FloatingMouse(
                                ffi: gFFI,
                              )
                            else
                              FloatingMouseWidgets(
                                ffi: gFFI,
                              ),
                            // Thanh phím tắt (Cmd, Alt, Ctrl,...) + Nút mới chuyên ẩn bàn phím nằm trên RawTouchGestureDetectorRegion
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: KeyHelpTools(
                                keyboardIsVisible: kbActive,
                                showGestureHelp: _alwaysShowShortcuts,
                                onHideKeyboard: _hideSoftKeyboard,
                              ),
                            ),
                            _buildDeskInCapsulePill(kbActive),
                            _buildDeskInCenteredToolbar(kbActive, topInset),
                            _buildDeskInMousePanel(kbActive, topInset),
                            _buildDeskInOperationGuideOverlay(topInset),
                          ],
                        );
                      }),
              ),
            ),
          )),
    );
  }

  bool _handleLocalKeyEvent(KeyEvent event) => handleMobileLocalKeyEvent(event,
      remoteFocused: _physicalFocusNode.hasPrimaryFocus, inputModel: inputModel);

  Widget getRawPointerAndKeyBody(Widget child) {
    final ffiModel = Provider.of<FfiModel>(context);
    return RawPointerMouseRegion(
      cursor: ffiModel.keyboard ? SystemMouseCursors.none : MouseCursor.defer,
      inputModel: inputModel,
      // Disable RawKeyFocusScope before the connecting is established.
      // The "Delete" key on the soft keyboard may be grabbed when inputting the password dialog.
      child: gFFI.ffiModel.pi.isSet.isTrue
          ? RawKeyFocusScope(
              focusNode: _physicalFocusNode,
              inputModel: inputModel,
              child: child)
          : child,
    );
  }

  Widget getBottomAppBar() {
    final ffiModel = Provider.of<FfiModel>(context);
    return BottomAppBar(
      elevation: 10,
      color: MyTheme.accent,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
              children: <Widget>[
                    IconButton(
                      color: Colors.white,
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        clientClose(sessionId, gFFI);
                      },
                    ),
                    IconButton(
                      color: Colors.white,
                      icon: Icon(Icons.tv),
                      onPressed: () {
                        setState(() => _showEdit = false);
                        showOptions(context, widget.id, gFFI.dialogManager);
                      },
                    )
                  ] +
                  (isWebDesktop || ffiModel.viewOnly || !ffiModel.keyboard
                      ? []
                      : gFFI.ffiModel.isPeerAndroid
                          ? [
                              IconButton(
                                  color: Colors.white,
                                  icon: Icon(Icons.keyboard),
                                  onPressed: openKeyboard),
                              IconButton(
                                color: Colors.white,
                                icon: const Icon(Icons.build),
                                onPressed: () => gFFI.dialogManager
                                    .toggleMobileActionsOverlay(ffi: gFFI),
                              )
                            ]
                          : [
                              IconButton(
                                  color: Colors.white,
                                  icon: Icon(Icons.keyboard),
                                  onPressed: openKeyboard),
                              IconButton(
                                color: Colors.white,
                                icon: Icon(gFFI.ffiModel.touchMode
                                    ? Icons.touch_app
                                    : Icons.mouse),
                                onPressed: () => setState(
                                    () => _showGestureHelp = !_showGestureHelp),
                              ),
                            ]) +
                  (isWeb
                      ? []
                      : <Widget>[
                          futureBuilder(
                              future: gFFI.invokeMethod(
                                  "get_value", "KEY_IS_SUPPORT_VOICE_CALL"),
                              hasData: (isSupportVoiceCall) => IconButton(
                                    color: Colors.white,
                                    icon: isAndroid && isSupportVoiceCall
                                        ? SvgPicture.asset('assets/chat.svg',
                                            colorFilter: ColorFilter.mode(
                                                Colors.white, BlendMode.srcIn))
                                        : Icon(Icons.message),
                                    onPressed: () =>
                                        isAndroid && isSupportVoiceCall
                                            ? showChatOptions(widget.id)
                                            : onPressedTextChat(widget.id),
                                  ))
                        ]) +
                  [
                    IconButton(
                      color: Colors.white,
                      icon: Icon(Icons.more_vert),
                      onPressed: () {
                        setState(() => _showEdit = false);
                        showActions(widget.id);
                      },
                    ),
                  ]),
          Obx(() => IconButton(
                color: Colors.white,
                icon: Icon(Icons.expand_more),
                onPressed: gFFI.ffiModel.waitForFirstImage.isTrue
                    ? null
                    : () {
                        setState(() => _showBar = !_showBar);
                      },
              )),
        ],
      ),
    );
  }

  bool get showCursorPaint =>
      !gFFI.ffiModel.isPeerAndroid &&
      !gFFI.ffiModel.touchMode &&
      !gFFI.canvasModel.cursorEmbedded &&
      !gFFI.inputModel.relativeMouseMode.value;

  Widget getBodyForMobile() {
    Provider.of<FfiModel>(context);
    return Container(
        width: double.infinity,
        height: double.infinity,
        color: MyTheme.canvasColor,
        child: Stack(children: () {
          final paints = <Widget>[
            const SizedBox.expand(),
            ImagePaint(ffiModel: gFFI.ffiModel),
            Positioned(
              top: 10,
              right: 10,
              child: QualityMonitor(gFFI.qualityMonitorModel),
            ),
            SizedBox(
              width: 0,
              height: 0,
              child: !_showEdit
                  ? Container()
                  : TextFormField(
                      textInputAction: TextInputAction.newline,
                      autocorrect: false,
                      // Flutter 3.16.9 Android.
                      // `enableSuggestions` causes secure keyboard to be shown.
                      // https://github.com/flutter/flutter/issues/139143
                      // https://github.com/flutter/flutter/issues/146540
                      enableSuggestions: !isIOS,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      textCapitalization: TextCapitalization.none,
                      spellCheckConfiguration:
                          const SpellCheckConfiguration.disabled(),
                      autofocus: true,
                      focusNode: _mobileFocusNode,
                      maxLines: null,
                      controller: _textController,
                      // trick way to make backspace work always
                      keyboardType: TextInputType.multiline,
                      // `onChanged` may be called depending on the input method if this widget is wrapped in
                      // `Focus(onKeyEvent: ..., child: ...)`
                      // For `Backspace` button in the soft keyboard:
                      // en/fr input method:
                      //      1. The button will not trigger `onKeyEvent` if the text field is not empty.
                      //      2. The button will trigger `onKeyEvent` if the text field is empty.
                      // ko/zh/ja input method: the button will trigger `onKeyEvent`
                      //                     and the event will not popup if `KeyEventResult.handled` is returned.
                      onChanged: handleSoftKeyboardInput,
                    ).workaroundFreezeLinuxMint(),
            ),
          ];
          if (showCursorPaint) {
            paints.add(CursorPaint(widget.id));
          }
          return paints;
        }()));
  }

  Widget getBodyForDesktopWithListener() {
    final ffiModel = Provider.of<FfiModel>(context);
    var paints = <Widget>[ImagePaint(ffiModel: ffiModel)];
    if (showCursorPaint) {
      final cursor = bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: 'show-remote-cursor');
      if (ffiModel.keyboard || cursor) {
        paints.add(CursorPaint(widget.id));
      }
    }
    return Container(
        color: MyTheme.canvasColor, child: Stack(children: paints));
  }

  List<TTextMenu> _getMobileActionMenus() {
    if (gFFI.ffiModel.pi.platform != kPeerPlatformAndroid ||
        !gFFI.ffiModel.keyboard) {
      return [];
    }
    final enabled = versionCmp(gFFI.ffiModel.pi.version, '1.2.7') >= 0;
    if (!enabled) return [];
    return [
      TTextMenu(
        child: Text(translate('Back')),
        onPressed: () => gFFI.inputModel.onMobileBack(),
      ),
      TTextMenu(
        child: Text(translate('Home')),
        onPressed: () => gFFI.inputModel.onMobileHome(),
      ),
      TTextMenu(
        child: Text(translate('Apps')),
        onPressed: () => gFFI.inputModel.onMobileApps(),
      ),
      TTextMenu(
        child: Text(translate('Volume up')),
        onPressed: () => gFFI.inputModel.onMobileVolumeUp(),
      ),
      TTextMenu(
        child: Text(translate('Volume down')),
        onPressed: () => gFFI.inputModel.onMobileVolumeDown(),
      ),
      TTextMenu(
        child: Text(translate('Power')),
        onPressed: () => gFFI.inputModel.onMobilePower(),
      ),
    ];
  }

  void showActions(String id) async {
    final size = MediaQuery.of(context).size;
    final x = 120.0;
    final y = size.height;
    final mobileActionMenus = _getMobileActionMenus();
    final menus = toolbarControls(context, id, gFFI);

    final List<PopupMenuEntry<int>> more = [
      ...mobileActionMenus
          .asMap()
          .entries
          .map((e) =>
              PopupMenuItem<int>(child: e.value.getChild(), value: e.key))
          .toList(),
      if (mobileActionMenus.isNotEmpty) PopupMenuDivider(),
      ...menus
          .asMap()
          .entries
          .map((e) => PopupMenuItem<int>(
              child: e.value.getChild(),
              value: e.key + mobileActionMenus.length))
          .toList(),
    ];
    () async {
      var index = await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(x, y, x, y),
        items: more,
        elevation: 8,
      );
      if (index != null) {
        if (index < mobileActionMenus.length) {
          mobileActionMenus[index].onPressed?.call();
        } else if (index < mobileActionMenus.length + more.length) {
          menus[index - mobileActionMenus.length].onPressed?.call();
        }
      }
    }();
  }

  void _registerMobileChatShortcut() {
    if (!isMobile) return;
    gFFI.shortcutModel.register(kShortcutActionToggleChat,
        () => onPressedTextChat(widget.id, requestSoftKeyboard: false));
  }

  onPressedTextChat(String id, {bool requestSoftKeyboard = true}) {
    if (gFFI.chatModel.chatWindowOverlayEntry == null) {
      setState(() => _showEdit = false);
    }
    gFFI.chatModel.changeCurrentKey(MessageKey(id, ChatModel.clientModeID));
    gFFI.chatModel.toggleChatOverlay(requestSoftKeyboard: requestSoftKeyboard);
  }

  showChatOptions(String id) async {
    onPressVoiceCall() => bind.sessionRequestVoiceCall(sessionId: sessionId);
    onPressEndVoiceCall() => bind.sessionCloseVoiceCall(sessionId: sessionId);

    makeTextMenu(String label, Widget icon, VoidCallback onPressed,
            {TextStyle? labelStyle}) =>
        TTextMenu(
          child: Text(translate(label), style: labelStyle),
          trailingIcon: Transform.scale(
            scale: (isDesktop || isWebDesktop) ? 0.8 : 1,
            child: IgnorePointer(
              child: IconButton(
                onPressed: null,
                icon: icon,
              ),
            ),
          ),
          onPressed: onPressed,
        );

    final isInVoice = [
      VoiceCallStatus.waitingForResponse,
      VoiceCallStatus.connected
    ].contains(gFFI.chatModel.voiceCallStatus.value);
    final menus = [
      makeTextMenu('Text chat', Icon(Icons.message, color: MyTheme.accent),
          () => onPressedTextChat(widget.id)),
      isInVoice
          ? makeTextMenu(
              'End voice call',
              SvgPicture.asset(
                'assets/call_wait.svg',
                colorFilter:
                    ColorFilter.mode(Colors.redAccent, BlendMode.srcIn),
              ),
              onPressEndVoiceCall,
              labelStyle: TextStyle(color: Colors.redAccent))
          : makeTextMenu(
              'Voice call',
              SvgPicture.asset(
                'assets/call_wait.svg',
                colorFilter: ColorFilter.mode(MyTheme.accent, BlendMode.srcIn),
              ),
              onPressVoiceCall),
    ];

    final menuItems = menus
        .asMap()
        .entries
        .map((e) => PopupMenuItem<int>(child: e.value.getChild(), value: e.key))
        .toList();
    Future.delayed(Duration.zero, () async {
      final size = MediaQuery.of(context).size;
      final x = 120.0;
      final y = size.height;
      var index = await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(x, y, x, y),
        items: menuItems,
        elevation: 8,
      );
      if (index != null && index < menus.length) {
        menus[index].onPressed?.call();
      }
    });
  }

  /// aka changeTouchMode
  BottomAppBar getGestureHelp() {
    return BottomAppBar(
        child: SingleChildScrollView(
            controller: ScrollController(),
            padding: EdgeInsets.symmetric(vertical: 10),
            child: GestureHelp(
              touchMode: gFFI.ffiModel.touchMode,
              onTouchModeChange: (t) {
                gFFI.ffiModel.toggleTouchMode();
                final v = gFFI.ffiModel.touchMode ? 'Y' : 'N';
                bind.mainSetLocalOption(key: kOptionTouchMode, value: v);
              },
              virtualMouseMode: gFFI.ffiModel.virtualMouseMode,
              inputModel: gFFI.inputModel,
            )));
  }
}

class KeyHelpTools extends StatefulWidget {
  final bool keyboardIsVisible;
  final bool showGestureHelp;
  final VoidCallback? onHideKeyboard;

  bool get requestShow => keyboardIsVisible || showGestureHelp;

  KeyHelpTools({
    required this.keyboardIsVisible,
    required this.showGestureHelp,
    this.onHideKeyboard,
  });

  @override
  State<KeyHelpTools> createState() => _KeyHelpToolsState();
}

class _KeyHelpToolsState extends State<KeyHelpTools> {
  var _fn = false;
  var _pin = false;
  final _key = GlobalKey();

  InputModel get inputModel => gFFI.inputModel;

  @override
  void initState() {
    super.initState();
    DeskInShortcutRepository.version.addListener(_onShortcutsChanged);
  }

  @override
  void dispose() {
    DeskInShortcutRepository.version.removeListener(_onShortcutsChanged);
    super.dispose();
  }

  void _onShortcutsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openCustomizeShortcutSheet() {
    showDeskInShortcutModal(context, gFFI);
  }

  Widget wrap(String text, void Function() onPressed,
      {bool? active, IconData? icon, Color? iconColor}) {
    final isActive = active == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: Material(
        color: isActive
            ? const Color(0xFF2B6CB0)
            : const Color(0xFF2C313C),
        borderRadius: BorderRadius.circular(7.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(7.0),
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7.0),
              border: Border.all(
                color: isActive ? Colors.lightBlueAccent : Colors.white24,
                width: 0.8,
              ),
            ),
            child: icon != null
                ? Icon(icon, size: 16, color: iconColor ?? Colors.white)
                : Text(
                    translate(text.trim()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  _updateRect() {
    RenderObject? renderObject = _key.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      Offset pos = renderObject.localToGlobal(Offset.zero);
      gFFI.cursorModel.keyHelpToolsVisibilityChanged(
          Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height),
          widget.keyboardIsVisible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = HardwareKeyboard.instance;
    final hasTouchModifier = (inputModel.ctrl && !keyboard.isControlPressed) ||
        (inputModel.alt && !keyboard.isAltPressed) ||
        (inputModel.shift && !keyboard.isShiftPressed) ||
        (inputModel.command && !keyboard.isMetaPressed);
    if (!_pin && !hasTouchModifier && !widget.requestShow) {
      gFFI.cursorModel
          .keyHelpToolsVisibilityChanged(null, widget.keyboardIsVisible);
      return Offstage();
    }

    final pi = gFFI.ffiModel.pi;
    final osKey = DeskInShortcutRepository.osKeyFromPeerPlatform(pi.platform);
    final customShortcuts = DeskInShortcutRepository.loadForOs(osKey);

    Widget buildShortcutButton(DeskInShortcutItem item) {
      bool isActive = false;
      if (item.isStickyCtrl) {
        isActive = inputModel.ctrl;
      } else if (item.isStickyAlt) {
        isActive = inputModel.alt;
      } else if (item.isStickyShift) {
        isActive = inputModel.shift;
      } else if (item.isStickyCommand) {
        isActive = inputModel.command;
      }

      IconData? arrowIcon;
      if (item.label == '←') {
        arrowIcon = Icons.keyboard_arrow_left;
      } else if (item.label == '↑') {
        arrowIcon = Icons.keyboard_arrow_up;
      } else if (item.label == '↓') {
        arrowIcon = Icons.keyboard_arrow_down;
      } else if (item.label == '→') {
        arrowIcon = Icons.keyboard_arrow_right;
      }

      return wrap(
        arrowIcon != null ? '' : item.label,
        () => executeDeskInShortcut(
          item,
          gFFI,
          onModifierToggled: () => setState(() {}),
        ),
        active: isActive,
        icon: arrowIcon,
      );
    }

    final row1 = <Widget>[
      for (final item in customShortcuts) buildShortcutButton(item),
      wrap('Fn', () => setState(() => _fn = !_fn), active: _fn),
      wrap('', () => setState(() => _pin = !_pin),
          active: _pin, icon: Icons.push_pin),
    ];

    final fnRow = <Widget>[
      for (var i = 1; i <= 12; ++i)
        wrap('F$i', () => inputModel.inputKey('VK_F$i')),
    ];

    Future.delayed(const Duration(milliseconds: 200), () {
      _updateRect();
    });

    return SafeArea(
      top: false,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          Container(
            key: _key,
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D26).withOpacity(0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_fn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.only(
                          right: widget.keyboardIsVisible ? 54 : 0),
                      child: Row(children: fnRow),
                    ),
                  ),
                Row(
                  children: [
                    wrap(
                      '',
                      _openCustomizeShortcutSheet,
                      icon: Icons.tune_rounded,
                      iconColor: Colors.lightBlueAccent,
                    ),
                    Container(
                      width: 1,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      color: Colors.white24,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.only(
                            right: widget.keyboardIsVisible ? 54 : 0),
                        child: Row(children: row1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.keyboardIsVisible)
            Positioned(
              right: 14,
              bottom: 10,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (widget.onHideKeyboard != null) {
                    widget.onHideKeyboard!();
                  } else {
                    FocusManager.instance.primaryFocus?.unfocus();
                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                  }
                },
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252A36).withOpacity(0.96),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                      width: 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.55),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(-2, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.keyboard_hide_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ImagePaint extends StatelessWidget {
  final FfiModel ffiModel;
  ImagePaint({Key? key, required this.ffiModel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<ImageModel>(context);
    final c = Provider.of<CanvasModel>(context);
    var s = c.scale;
    if (ffiModel.isPeerLinux) {
      final displays = ffiModel.pi.getCurDisplays();
      if (displays.isNotEmpty) {
        s = s / displays[0].scale;
      }
    }
    final adjust = c.getAdjustY();
    return CustomPaint(
      painter: ImagePainter(
          image: m.image, x: c.x / s, y: (c.y + adjust) / s, scale: s),
    );
  }
}

class CursorPaint extends StatelessWidget {
  late final String id;
  CursorPaint(this.id);

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<CursorModel>(context);
    final c = Provider.of<CanvasModel>(context);
    final ffiModel = Provider.of<FfiModel>(context);
    final showRemoteCursor = ShowRemoteCursorState.find(id).value;
    // Ở chế độ Touch (touchMode == true), ẩn hoàn toàn lớp vẽ con trỏ chuột trên iPad
    if (ffiModel.touchMode) {
      return const Offstage();
    }
    final s = c.scale;
    double hotx = m.hotx;
    double hoty = m.hoty;
    var image = m.image;

    if (preForbiddenCursor.image != null &&
        !ffiModel.viewOnly &&
        !ffiModel.keyboard &&
        !showRemoteCursor) {
      image = preForbiddenCursor.image;
      hotx = preForbiddenCursor.image!.width / 2;
      hoty = preForbiddenCursor.image!.height / 2;
    }

    final adjust = c.getAdjustY();
    // If no custom remote cursor image is loaded, draw crisp macOS-style vector cursor!
    if (image == null) {
      final screenX = m.x * s + c.x;
      final screenY = m.y * s + c.y + adjust;
      return CustomPaint(
        painter: _MacOSVectorCursorPainter(Offset(screenX, screenY)),
      );
    }

    final minSize = 12.0;
    double mins =
        minSize / (image.width > image.height ? image.width : image.height);
    double factor = 1.0;
    if (s < mins) {
      factor = s / mins;
    }
    final s2 = s < mins ? mins : s;
    return CustomPaint(
      painter: ImagePainter(
          image: image,
          x: (m.x - hotx) * factor + c.x / s2,
          y: (m.y - hoty) * factor + (c.y + adjust) / s2,
          scale: s2),
    );
  }
}

class _MacOSVectorCursorPainter extends CustomPainter {
  final Offset tip;
  _MacOSVectorCursorPainter(this.tip);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    // Authentic macOS pointer geometry (black arrow with crisp white outline & drop shadow)
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 21.5)
      ..lineTo(4.8, 16.8)
      ..lineTo(8.3, 24.5)
      ..lineTo(11.2, 23.1)
      ..lineTo(7.7, 15.3)
      ..lineTo(14.2, 15.3)
      ..close();

    canvas.drawShadow(path, Colors.black.withOpacity(0.55), 3.0, false);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MacOSVectorCursorPainter oldDelegate) =>
      oldDelegate.tip != tip;
}

void showOptions(
    BuildContext context, String id, OverlayDialogManager dialogManager) async {
  var displays = <Widget>[];
  final pi = gFFI.ffiModel.pi;
  final image = gFFI.ffiModel.getConnectionImageText();
  if (image != null) {
    displays.add(Padding(padding: const EdgeInsets.only(top: 8), child: image));
  }
  final privacyModeState = PrivacyModeState.find(id);
  if (pi.displays.length > 1 &&
      pi.currentDisplay != kAllDisplayValue &&
      (privacyModeState.isEmpty ||
          allowDisplaySwitchInPrivacyMode(pi, privacyModeState.value))) {
    final cur = pi.currentDisplay;
    final children = <Widget>[];
    final isDarkTheme = MyTheme.currentThemeMode() == ThemeMode.dark;
    final numColorSelected = Colors.white;
    final numColorUnselected = isDarkTheme ? Colors.grey : Colors.black87;
    // We can't use `Theme.of(context).primaryColor` here, the color is:
    // - light theme: 0xff2196f3 (Colors.blue)
    // - dark theme: 0xff212121 (the canvas color?)
    final numBgSelected =
        Theme.of(context).colorScheme.primary.withOpacity(0.6);
    for (var i = 0; i < pi.displays.length; ++i) {
      children.add(InkWell(
          onTap: () {
            if (i == cur) return;
            openMonitorInTheSameTab(i, gFFI, pi);
            gFFI.dialogManager.dismissAll();
          },
          child: Ink(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).hintColor),
                  borderRadius: BorderRadius.circular(2),
                  color: i == cur ? numBgSelected : null),
              child: Center(
                  child: Text((i + 1).toString(),
                      style: TextStyle(
                          color:
                              i == cur ? numColorSelected : numColorUnselected,
                          fontWeight: FontWeight.bold))))));
    }
    displays.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: children,
        )));
  }
  if (displays.isNotEmpty) {
    displays.add(const Divider(color: MyTheme.border));
  }

  List<TRadioMenu<String>> viewStyleRadios =
      await toolbarViewStyle(context, id, gFFI);
  List<TRadioMenu<String>> imageQualityRadios =
      await toolbarImageQuality(context, id, gFFI);
  List<TRadioMenu<String>> codecRadios = await toolbarCodec(context, id, gFFI);
  List<TToggleMenu> cursorToggles = await toolbarCursor(context, id, gFFI);
  List<TToggleMenu> displayToggles =
      await toolbarDisplayToggle(context, id, gFFI);
  if (isMobile) {
    displayToggles.insert(
        0,
        TToggleMenu(
            child: Text(translate('Lock canvas')),
            value: gFFI.canvasModel.locked,
            onChanged: (value) => gFFI.canvasModel.setLocked(value == true)));
  }

  List<TToggleMenu> privacyModeList = [];
  if ((gFFI.ffiModel.pi.features.privacyMode && gFFI.ffiModel.keyboard) ||
      privacyModeState.isNotEmpty) {
    privacyModeList = toolbarPrivacyMode(privacyModeState, context, id, gFFI);
    if (privacyModeList.length == 1) {
      displayToggles.add(privacyModeList[0]);
    }
  }

  dialogManager.show((setState, close, context) {
    var viewStyle =
        (viewStyleRadios.isNotEmpty ? viewStyleRadios[0].groupValue : '').obs;
    var imageQuality =
        (imageQualityRadios.isNotEmpty ? imageQualityRadios[0].groupValue : '')
            .obs;
    var codec = (codecRadios.isNotEmpty ? codecRadios[0].groupValue : '').obs;
    final radios = [
      for (var e in viewStyleRadios)
        Obx(() => getRadio<String>(
            e.child,
            e.value,
            viewStyle.value,
            e.onChanged != null
                ? (v) {
                    e.onChanged?.call(v);
                    if (v != null) viewStyle.value = v;
                  }
                : null)),
      // Show custom scale controls when custom view style is selected
      Obx(() => viewStyle.value == kRemoteViewStyleCustom
          ? MobileCustomScaleControls(ffi: gFFI)
          : const SizedBox.shrink()),
      const Divider(color: MyTheme.border),
      for (var e in imageQualityRadios)
        Obx(() => getRadio<String>(
            e.child,
            e.value,
            imageQuality.value,
            e.onChanged != null
                ? (v) {
                    e.onChanged?.call(v);
                    if (v != null) imageQuality.value = v;
                  }
                : null)),
      const Divider(color: MyTheme.border),
      for (var e in codecRadios)
        Obx(() => getRadio<String>(
            e.child,
            e.value,
            codec.value,
            e.onChanged != null
                ? (v) {
                    e.onChanged?.call(v);
                    if (v != null) codec.value = v;
                  }
                : null)),
      if (codecRadios.isNotEmpty) const Divider(color: MyTheme.border),
    ];
    final rxCursorToggleValues = cursorToggles.map((e) => e.value.obs).toList();
    final cursorTogglesList = cursorToggles
        .asMap()
        .entries
        .map((e) => Obx(() => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            value: rxCursorToggleValues[e.key].value,
            onChanged: e.value.onChanged != null
                ? (v) {
                    e.value.onChanged?.call(v);
                    if (v != null) rxCursorToggleValues[e.key].value = v;
                  }
                : null,
            title: e.value.child)))
        .toList();

    final rxToggleValues = displayToggles.map((e) => e.value.obs).toList();
    final displayTogglesList = displayToggles
        .asMap()
        .entries
        .map((e) => Obx(() => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            value: rxToggleValues[e.key].value,
            onChanged: e.value.onChanged != null
                ? (v) {
                    e.value.onChanged?.call(v);
                    if (v != null) rxToggleValues[e.key].value = v;
                  }
                : null,
            title: e.value.child)))
        .toList();
    final toggles = [
      ...cursorTogglesList,
      if (cursorToggles.isNotEmpty) const Divider(color: MyTheme.border),
      ...displayTogglesList,
    ];

    Widget privacyModeWidget = Offstage();
    if (privacyModeList.length > 1) {
      privacyModeWidget = ListTile(
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        title: Text(translate('Privacy mode')),
        onTap: () => setPrivacyModeDialog(
            dialogManager, privacyModeList, privacyModeState),
      );
    }

    var popupDialogMenus = List<Widget>.empty(growable: true);
    final resolution = getResolutionMenu(gFFI, id);
    if (resolution != null) {
      popupDialogMenus.add(ListTile(
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        title: resolution.child,
        onTap: () {
          close();
          resolution.onPressed?.call();
        },
      ));
    }
    final virtualDisplayMenu = getVirtualDisplayMenu(gFFI, id);
    if (virtualDisplayMenu != null) {
      popupDialogMenus.add(ListTile(
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        title: virtualDisplayMenu.child,
        onTap: () {
          close();
          virtualDisplayMenu.onPressed?.call();
        },
      ));
    }
    if (popupDialogMenus.isNotEmpty) {
      popupDialogMenus.add(const Divider(color: MyTheme.border));
    }

    return CustomAlertDialog(
      content: Column(
          mainAxisSize: MainAxisSize.min,
          children: displays +
              radios +
              popupDialogMenus +
              toggles +
              [privacyModeWidget]),
    );
  }, clickMaskDismiss: true, backDismiss: true).then((value) {
    _disableAndroidSoftKeyboard();
  });
}

TTextMenu? getVirtualDisplayMenu(FFI ffi, String id) {
  if (!showVirtualDisplayMenu(ffi)) {
    return null;
  }
  return TTextMenu(
    child: Text(translate("Virtual display")),
    onPressed: () {
      ffi.dialogManager.show((setState, close, context) {
        final children = getVirtualDisplayMenuChildren(ffi, id, close);
        return CustomAlertDialog(
          title: Text(translate('Virtual display')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );
      }, clickMaskDismiss: true, backDismiss: true).then((value) {
        _disableAndroidSoftKeyboard();
      });
    },
  );
}

TTextMenu? getResolutionMenu(FFI ffi, String id) {
  final ffiModel = ffi.ffiModel;
  final pi = ffiModel.pi;
  final resolutions = pi.resolutions;
  final display = pi.tryGetDisplayIfNotAllDisplay(display: pi.currentDisplay);

  final visible =
      ffiModel.keyboard && (resolutions.length > 1) && display != null;
  if (!visible) return null;

  return TTextMenu(
    child: Text(translate("Resolution")),
    onPressed: () {
      ffi.dialogManager.show((setState, close, context) {
        final children = resolutions
            .map((e) => getRadio<String>(
                  Text('${e.width}x${e.height}'),
                  '${e.width}x${e.height}',
                  '${display.width}x${display.height}',
                  (value) {
                    close();
                    bind.sessionChangeResolution(
                      sessionId: ffi.sessionId,
                      display: pi.currentDisplay,
                      width: e.width,
                      height: e.height,
                    );
                  },
                ))
            .toList();
        return CustomAlertDialog(
          title: Text(translate('Resolution')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );
      }, clickMaskDismiss: true, backDismiss: true).then((value) {
        _disableAndroidSoftKeyboard();
      });
    },
  );
}

void sendPrompt(bool isMac, String key) {
  final old = isMac ? gFFI.inputModel.command : gFFI.inputModel.ctrl;
  if (isMac) {
    gFFI.inputModel.command = true;
  } else {
    gFFI.inputModel.ctrl = true;
  }
  gFFI.inputModel.inputKey(key);
  if (isMac) {
    gFFI.inputModel.command = old;
  } else {
    gFFI.inputModel.ctrl = old;
  }
}

class FABLocation extends FloatingActionButtonLocation {
  FloatingActionButtonLocation location;
  double offsetX;
  double offsetY;
  FABLocation(this.location, this.offsetX, this.offsetY);

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final offset = location.getOffset(scaffoldGeometry);
    return Offset(offset.dx + offsetX, offset.dy + offsetY);
  }
}
