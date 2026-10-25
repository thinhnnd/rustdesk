import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart' hide Dialog;
import '../../consts.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

class DeskInShortcutItem {
  final String id;
  final String label;
  final List<String> keys;

  const DeskInShortcutItem({
    required this.id,
    required this.label,
    required this.keys,
  });

  bool get isStickyCtrl => keys.length == 1 && keys[0] == 'Ctrl';
  bool get isStickyAlt =>
      keys.length == 1 && (keys[0] == 'Alt' || keys[0] == 'Option');
  bool get isStickyShift => keys.length == 1 && keys[0] == 'Shift';
  bool get isStickyCommand =>
      keys.length == 1 &&
      (keys[0] == 'Win' || keys[0] == 'Cmd' || keys[0] == 'Super');

  bool get isSingleStickyModifier =>
      isStickyCtrl || isStickyAlt || isStickyShift || isStickyCommand;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'keys': keys,
      };

  factory DeskInShortcutItem.fromJson(Map<String, dynamic> json) {
    final rawKeys = (json['keys'] as List?)?.map((e) => e.toString()).toList() ??
        <String>[];
    return DeskInShortcutItem(
      id: (json['id'] ?? DateTime.now().microsecondsSinceEpoch.toString())
          .toString(),
      label: (json['label'] ?? rawKeys.join('+')).toString(),
      keys: rawKeys,
    );
  }
}

class DeskInShortcutRepository {
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static String osKeyFromPeerPlatform(String platform) {
    if (platform == kPeerPlatformMacOS) return 'macos';
    if (platform == kPeerPlatformLinux) return 'linux';
    return 'windows';
  }

  static String _storageKey(String osKey) => 'deskin-custom-shortcuts-$osKey';

  static List<DeskInShortcutItem> defaultForOs(String osKey) {
    if (osKey == 'macos') {
      return const [
        DeskInShortcutItem(id: 'mac_cmd', label: 'Cmd', keys: ['Cmd']),
        DeskInShortcutItem(id: 'mac_opt', label: 'Option', keys: ['Option']),
        DeskInShortcutItem(id: 'mac_shift', label: 'Shift', keys: ['Shift']),
        DeskInShortcutItem(id: 'mac_ctrl', label: 'Ctrl', keys: ['Ctrl']),
        DeskInShortcutItem(
            id: 'mac_spotlight', label: 'Cmd+Space', keys: ['Cmd', 'Space']),
        DeskInShortcutItem(id: 'mac_copy', label: 'Cmd+C', keys: ['Cmd', 'C']),
        DeskInShortcutItem(id: 'mac_paste', label: 'Cmd+V', keys: ['Cmd', 'V']),
        DeskInShortcutItem(id: 'mac_undo', label: 'Cmd+Z', keys: ['Cmd', 'Z']),
        DeskInShortcutItem(id: 'mac_all', label: 'Cmd+A', keys: ['Cmd', 'A']),
        DeskInShortcutItem(
            id: 'mac_shot',
            label: 'Cmd+Shift+4',
            keys: ['Cmd', 'Shift', '4']),
        DeskInShortcutItem(id: 'mac_tab', label: 'Tab', keys: ['Tab']),
        DeskInShortcutItem(id: 'mac_esc', label: 'Esc', keys: ['Esc']),
        DeskInShortcutItem(id: 'mac_home', label: 'Home', keys: ['Home']),
        DeskInShortcutItem(id: 'mac_del', label: 'Delete', keys: ['Delete']),
        DeskInShortcutItem(id: 'mac_end', label: 'End', keys: ['End']),
        DeskInShortcutItem(id: 'mac_pgup', label: 'PageUp', keys: ['PageUp']),
        DeskInShortcutItem(
            id: 'mac_pgdn', label: 'PageDown', keys: ['PageDown']),
        DeskInShortcutItem(id: 'mac_up', label: '↑', keys: ['↑']),
        DeskInShortcutItem(id: 'mac_down', label: '↓', keys: ['↓']),
        DeskInShortcutItem(id: 'mac_left', label: '←', keys: ['←']),
        DeskInShortcutItem(id: 'mac_right', label: '→', keys: ['→']),
      ];
    } else if (osKey == 'linux') {
      return const [
        DeskInShortcutItem(id: 'lin_ctrl', label: 'Ctrl', keys: ['Ctrl']),
        DeskInShortcutItem(id: 'lin_alt', label: 'Alt', keys: ['Alt']),
        DeskInShortcutItem(id: 'lin_shift', label: 'Shift', keys: ['Shift']),
        DeskInShortcutItem(id: 'lin_super', label: 'Super', keys: ['Super']),
        DeskInShortcutItem(
            id: 'lin_copy', label: 'Ctrl+C', keys: ['Ctrl', 'C']),
        DeskInShortcutItem(
            id: 'lin_paste', label: 'Ctrl+V', keys: ['Ctrl', 'V']),
        DeskInShortcutItem(id: 'lin_tab', label: 'Tab', keys: ['Tab']),
        DeskInShortcutItem(id: 'lin_esc', label: 'Esc', keys: ['Esc']),
        DeskInShortcutItem(id: 'lin_home', label: 'Home', keys: ['Home']),
        DeskInShortcutItem(id: 'lin_del', label: 'Delete', keys: ['Delete']),
        DeskInShortcutItem(id: 'lin_end', label: 'End', keys: ['End']),
        DeskInShortcutItem(id: 'lin_pgup', label: 'PageUp', keys: ['PageUp']),
        DeskInShortcutItem(
            id: 'lin_pgdn', label: 'PageDown', keys: ['PageDown']),
        DeskInShortcutItem(id: 'lin_up', label: '↑', keys: ['↑']),
        DeskInShortcutItem(id: 'lin_down', label: '↓', keys: ['↓']),
        DeskInShortcutItem(id: 'lin_left', label: '←', keys: ['←']),
        DeskInShortcutItem(id: 'lin_right', label: '→', keys: ['→']),
      ];
    } else {
      return const [
        DeskInShortcutItem(id: 'win_ctrl', label: 'Ctrl', keys: ['Ctrl']),
        DeskInShortcutItem(id: 'win_alt', label: 'Alt', keys: ['Alt']),
        DeskInShortcutItem(id: 'win_shift', label: 'Shift', keys: ['Shift']),
        DeskInShortcutItem(id: 'win_r', label: 'Win+R', keys: ['Win', 'R']),
        DeskInShortcutItem(
            id: 'win_copy', label: 'Ctrl+C', keys: ['Ctrl', 'C']),
        DeskInShortcutItem(
            id: 'win_paste', label: 'Ctrl+V', keys: ['Ctrl', 'V']),
        DeskInShortcutItem(id: 'win_win', label: 'Win', keys: ['Win']),
        DeskInShortcutItem(id: 'win_tab', label: 'Tab', keys: ['Tab']),
        DeskInShortcutItem(id: 'win_esc', label: 'Esc', keys: ['Esc']),
        DeskInShortcutItem(id: 'win_home', label: 'Home', keys: ['Home']),
        DeskInShortcutItem(id: 'win_del', label: 'Delete', keys: ['Delete']),
        DeskInShortcutItem(id: 'win_end', label: 'End', keys: ['End']),
        DeskInShortcutItem(id: 'win_pgup', label: 'PageUp', keys: ['PageUp']),
        DeskInShortcutItem(
            id: 'win_pgdn', label: 'PageDown', keys: ['PageDown']),
        DeskInShortcutItem(id: 'win_up', label: '↑', keys: ['↑']),
        DeskInShortcutItem(id: 'win_down', label: '↓', keys: ['↓']),
        DeskInShortcutItem(id: 'win_left', label: '←', keys: ['←']),
        DeskInShortcutItem(id: 'win_right', label: '→', keys: ['→']),
      ];
    }
  }

  static List<DeskInShortcutItem> loadForOs(String osKey) {
    try {
      final raw = bind.mainGetLocalOption(key: _storageKey(osKey));
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final items = decoded
              .whereType<Map>()
              .map((m) =>
                  DeskInShortcutItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          if (items.isNotEmpty) {
            return items;
          }
        }
      }
    } catch (_) {}
    return List<DeskInShortcutItem>.from(defaultForOs(osKey));
  }

  static void saveForOs(String osKey, List<DeskInShortcutItem> items) {
    try {
      final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
      bind.mainSetLocalOption(key: _storageKey(osKey), value: encoded);
    } catch (_) {}
    version.value++;
  }

  static void resetForOs(String osKey) {
    saveForOs(osKey, defaultForOs(osKey));
  }
}

void executeDeskInShortcut(
  DeskInShortcutItem item,
  FFI ffi, {
  VoidCallback? onModifierToggled,
}) {
  final inputModel = ffi.inputModel;
  if (item.isStickyCtrl) {
    inputModel.ctrl = !inputModel.ctrl;
    onModifierToggled?.call();
    return;
  }
  if (item.isStickyAlt) {
    inputModel.alt = !inputModel.alt;
    onModifierToggled?.call();
    return;
  }
  if (item.isStickyShift) {
    inputModel.shift = !inputModel.shift;
    onModifierToggled?.call();
    return;
  }
  if (item.isStickyCommand) {
    inputModel.command = !inputModel.command;
    onModifierToggled?.call();
    return;
  }

  // Handle special system actions if present
  if (item.keys.length == 1 && item.keys[0] == 'ACTION_CTRL_ALT_DEL') {
    bind.sessionCtrlAltDel(sessionId: ffi.sessionId);
    return;
  }
  if (item.keys.length == 1 && item.keys[0] == 'ACTION_LOCK_SCREEN') {
    bind.sessionLockScreen(sessionId: ffi.sessionId);
    return;
  }

  bool wantCtrl = false;
  bool wantAlt = false;
  bool wantShift = false;
  bool wantCmd = false;
  final List<String> actionKeys = [];

  for (final k in item.keys) {
    if (k == 'Ctrl') {
      wantCtrl = true;
    } else if (k == 'Alt' || k == 'Option') {
      wantAlt = true;
    } else if (k == 'Shift') {
      wantShift = true;
    } else if (k == 'Win' || k == 'Cmd' || k == 'Super') {
      wantCmd = true;
    } else {
      actionKeys.add(k);
    }
  }

  // Temporarily apply modifiers on inputModel and fire the target key(s)
  final oldCtrl = inputModel.ctrl;
  final oldAlt = inputModel.alt;
  final oldShift = inputModel.shift;
  final oldCmd = inputModel.command;

  inputModel.ctrl = oldCtrl || wantCtrl;
  inputModel.alt = oldAlt || wantAlt;
  inputModel.shift = oldShift || wantShift;
  inputModel.command = oldCmd || wantCmd;

  try {
    if (actionKeys.isEmpty) {
      // Only modifiers were in the combo (e.g. Ctrl+Alt)
      return;
    }
    for (final rawKey in actionKeys) {
      final mapped = _mapShortcutKeyToVkName(rawKey);
      inputModel.inputKey(mapped);
    }
  } finally {
    inputModel.ctrl = oldCtrl;
    inputModel.alt = oldAlt;
    inputModel.shift = oldShift;
    inputModel.command = oldCmd;
  }
}

String _mapShortcutKeyToVkName(String key) {
  switch (key) {
    case 'Esc':
      return 'VK_ESCAPE';
    case 'Tab':
      return 'VK_TAB';
    case 'Enter':
      return 'VK_ENTER';
    case 'Space':
      return 'VK_SPACE';
    case 'Back Space':
    case 'BackSpace':
      return 'VK_BACK';
    case 'Delete':
    case 'Del':
      return 'VK_DELETE';
    case 'Insert':
      return 'VK_INSERT';
    case 'Home':
      return 'VK_HOME';
    case 'End':
      return 'VK_END';
    case 'PageUp':
    case 'PgUp':
      return 'VK_PRIOR';
    case 'PageDown':
    case 'PgDn':
      return 'VK_NEXT';
    case 'Caps Lock':
    case 'CapsLock':
      return 'VK_CAPITAL';
    case '↑':
      return 'VK_UP';
    case '↓':
      return 'VK_DOWN';
    case '←':
      return 'VK_LEFT';
    case '→':
      return 'VK_RIGHT';
    case 'F1':
    case 'F2':
    case 'F3':
    case 'F4':
    case 'F5':
    case 'F6':
    case 'F7':
    case 'F8':
    case 'F9':
    case 'F10':
    case 'F11':
    case 'F12':
      return 'VK_$key';
    default:
      if (key.length == 1) {
        return key.toLowerCase();
      }
      return key;
  }
}

void showDeskInShortcutModal(BuildContext context, FFI ffi) {
  HapticFeedback.selectionClick();
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (ctx) => DeskInShortcutDialog(ffi: ffi),
  );
}

class DeskInShortcutDialog extends StatefulWidget {
  final FFI ffi;

  const DeskInShortcutDialog({Key? key, required this.ffi}) : super(key: key);

  @override
  State<DeskInShortcutDialog> createState() => _DeskInShortcutDialogState();
}

class _DeskInShortcutDialogState extends State<DeskInShortcutDialog> {
  static const Color _bgPage = Color(0xFFF4F6F9);
  static const Color _bgSegment = Color(0xFFE4E7ED);
  static const Color _activeBlue = Color(0xFF2F80ED);
  static const Color _disabledBlue = Color(0xFF8AB8F6);
  static const Color _textDark = Color(0xFF1F2329);
  static const Color _textMuted = Color(0xFF646A73);
  static const Color _deleteRed = Color(0xFFF53F3F);

  late String _selectedOs; // 'windows' | 'macos' | 'linux'
  late Map<String, List<DeskInShortcutItem>> _osItems;
  String? _swipedItemId;

  // Sub-page state: false = Shortcut List, true = Add Page
  bool _isAddPage = false;
  int _addTabIndex = 0; // 0 = Keyboard keys, 1 = System operation
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _customCharController = TextEditingController();
  final List<String> _selectedKeys = [];
  int? _selectedSysOpIndex;

  @override
  void initState() {
    super.initState();
    _selectedOs = DeskInShortcutRepository.osKeyFromPeerPlatform(
        widget.ffi.ffiModel.pi.platform);
    _osItems = {
      'windows': DeskInShortcutRepository.loadForOs('windows'),
      'macos': DeskInShortcutRepository.loadForOs('macos'),
      'linux': DeskInShortcutRepository.loadForOs('linux'),
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customCharController.dispose();
    super.dispose();
  }

  List<DeskInShortcutItem> get _currentList =>
      _osItems[_selectedOs] ?? <DeskInShortcutItem>[];

  void _saveCurrentOs() {
    DeskInShortcutRepository.saveForOs(_selectedOs, _currentList);
  }

  void _toggleKeyInCombo(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  String _buildAutoComboName() {
    final List<String> all = List<String>.from(_selectedKeys);
    final customText = _customCharController.text.trim();
    if (customText.isNotEmpty) {
      for (int i = 0; i < customText.length; i++) {
        final ch = customText[i].toUpperCase();
        if (!all.contains(ch)) {
          all.add(ch);
        }
      }
    }
    return all.join('+');
  }

  List<String> _buildFinalKeysList() {
    final List<String> all = List<String>.from(_selectedKeys);
    final customText = _customCharController.text.trim();
    if (customText.isNotEmpty) {
      for (int i = 0; i < customText.length; i++) {
        final ch = customText[i].toUpperCase();
        if (!all.contains(ch)) {
          all.add(ch);
        }
      }
    }
    return all;
  }

  List<DeskInShortcutItem> _getSystemOperationsForOs(String osKey) {
    if (osKey == 'macos') {
      return const [
        DeskInShortcutItem(
            id: 'sys_mac_spot',
            label: 'Spotlight (Cmd+Space)',
            keys: ['Cmd', 'Space']),
        DeskInShortcutItem(
            id: 'sys_mac_shot4',
            label: 'Screenshot Area (Cmd+Shift+4)',
            keys: ['Cmd', 'Shift', '4']),
        DeskInShortcutItem(
            id: 'sys_mac_shot3',
            label: 'Full Screenshot (Cmd+Shift+3)',
            keys: ['Cmd', 'Shift', '3']),
        DeskInShortcutItem(
            id: 'sys_mac_forcequit',
            label: 'Force Quit (Cmd+Opt+Esc)',
            keys: ['Cmd', 'Option', 'Esc']),
        DeskInShortcutItem(
            id: 'sys_mac_switch',
            label: 'Switch App (Cmd+Tab)',
            keys: ['Cmd', 'Tab']),
        DeskInShortcutItem(
            id: 'sys_mac_mission',
            label: 'Mission Control (Ctrl+↑)',
            keys: ['Ctrl', '↑']),
        DeskInShortcutItem(
            id: 'sys_mac_lock',
            label: 'Lock Screen',
            keys: ['ACTION_LOCK_SCREEN']),
        DeskInShortcutItem(
            id: 'sys_mac_copy', label: 'Copy (Cmd+C)', keys: ['Cmd', 'C']),
        DeskInShortcutItem(
            id: 'sys_mac_paste', label: 'Paste (Cmd+V)', keys: ['Cmd', 'V']),
        DeskInShortcutItem(
            id: 'sys_mac_cut', label: 'Cut (Cmd+X)', keys: ['Cmd', 'X']),
        DeskInShortcutItem(
            id: 'sys_mac_undo', label: 'Undo (Cmd+Z)', keys: ['Cmd', 'Z']),
        DeskInShortcutItem(
            id: 'sys_mac_redo',
            label: 'Redo (Cmd+Shift+Z)',
            keys: ['Cmd', 'Shift', 'Z']),
        DeskInShortcutItem(
            id: 'sys_mac_all', label: 'Select All (Cmd+A)', keys: ['Cmd', 'A']),
        DeskInShortcutItem(
            id: 'sys_mac_save', label: 'Save (Cmd+S)', keys: ['Cmd', 'S']),
        DeskInShortcutItem(
            id: 'sys_mac_find', label: 'Find (Cmd+F)', keys: ['Cmd', 'F']),
      ];
    } else if (osKey == 'linux') {
      return const [
        DeskInShortcutItem(
            id: 'sys_lin_term',
            label: 'Terminal (Ctrl+Alt+T)',
            keys: ['Ctrl', 'Alt', 'T']),
        DeskInShortcutItem(
            id: 'sys_lin_lock',
            label: 'Lock Screen',
            keys: ['ACTION_LOCK_SCREEN']),
        DeskInShortcutItem(
            id: 'sys_lin_switch',
            label: 'Switch Window (Alt+Tab)',
            keys: ['Alt', 'Tab']),
        DeskInShortcutItem(
            id: 'sys_lin_close',
            label: 'Close Window (Alt+F4)',
            keys: ['Alt', 'F4']),
        DeskInShortcutItem(
            id: 'sys_lin_copy', label: 'Copy (Ctrl+C)', keys: ['Ctrl', 'C']),
        DeskInShortcutItem(
            id: 'sys_lin_paste', label: 'Paste (Ctrl+V)', keys: ['Ctrl', 'V']),
      ];
    } else {
      return const [
        DeskInShortcutItem(
            id: 'sys_win_run', label: 'Run (Win+R)', keys: ['Win', 'R']),
        DeskInShortcutItem(
            id: 'sys_win_taskmgr',
            label: 'Task Manager (Ctrl+Shift+Esc)',
            keys: ['Ctrl', 'Shift', 'Esc']),
        DeskInShortcutItem(
            id: 'sys_win_cad',
            label: 'Ctrl+Alt+Del',
            keys: ['ACTION_CTRL_ALT_DEL']),
        DeskInShortcutItem(
            id: 'sys_win_lock',
            label: 'Lock Screen (Win+L)',
            keys: ['ACTION_LOCK_SCREEN']),
        DeskInShortcutItem(
            id: 'sys_win_desk',
            label: 'Show Desktop (Win+D)',
            keys: ['Win', 'D']),
        DeskInShortcutItem(
            id: 'sys_win_exp',
            label: 'File Explorer (Win+E)',
            keys: ['Win', 'E']),
        DeskInShortcutItem(
            id: 'sys_win_snip',
            label: 'Snipping Tool (Win+Shift+S)',
            keys: ['Win', 'Shift', 'S']),
        DeskInShortcutItem(
            id: 'sys_win_switch',
            label: 'Switch Window (Alt+Tab)',
            keys: ['Alt', 'Tab']),
        DeskInShortcutItem(
            id: 'sys_win_close',
            label: 'Close Window (Alt+F4)',
            keys: ['Alt', 'F4']),
      ];
    }
  }

  void _handleConfirmAdd() {
    if (_addTabIndex == 0) {
      final finalKeys = _buildFinalKeysList();
      if (finalKeys.isEmpty) return;
      final customName = _nameController.text.trim();
      final label = customName.isNotEmpty ? customName : finalKeys.join('+');
      final newItem = DeskInShortcutItem(
        id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
        label: label,
        keys: finalKeys,
      );
      HapticFeedback.mediumImpact();
      setState(() {
        _currentList.insert(0, newItem);
        _saveCurrentOs();
        _isAddPage = false;
        _selectedKeys.clear();
        _nameController.clear();
        _customCharController.clear();
      });
    } else {
      final sysOps = _getSystemOperationsForOs(_selectedOs);
      if (_selectedSysOpIndex == null ||
          _selectedSysOpIndex! < 0 ||
          _selectedSysOpIndex! >= sysOps.length) {
        return;
      }
      final chosen = sysOps[_selectedSysOpIndex!];
      final customName = _nameController.text.trim();
      final newItem = DeskInShortcutItem(
        id: 'sys_${DateTime.now().microsecondsSinceEpoch}',
        label: customName.isNotEmpty ? customName : chosen.label,
        keys: chosen.keys,
      );
      HapticFeedback.mediumImpact();
      setState(() {
        _currentList.insert(0, newItem);
        _saveCurrentOs();
        _isAddPage = false;
        _selectedSysOpIndex = null;
        _nameController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogWidth = (media.size.width * 0.72).clamp(340.0, 570.0);
    final dialogHeight = (media.size.height * 0.76).clamp(320.0, 470.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: _bgPage,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: _isAddPage ? _buildAddView() : _buildShortcutListView(),
        ),
      ),
    );
  }

  Widget _buildShortcutListView() {
    final list = _currentList;
    return Column(
      children: [
        // Top Header: Title "Shortcut" & Close "X"
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
          child: Row(
            children: [
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    DeskInShortcutRepository.resetForOs(_selectedOs);
                    _osItems[_selectedOs] =
                        DeskInShortcutRepository.loadForOs(_selectedOs);
                    _swipedItemId = null;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: _textMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 32),
                ),
                child: const Text(
                  'Reset',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const Expanded(
                child: Text(
                  'Shortcut',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF4E5969), size: 23),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
        // Segmented Control: Windows | macOS | Linux
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 6),
          child: Container(
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _bgSegment,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                _buildSegmentTab(
                  label: 'Windows',
                  selected: _selectedOs == 'windows',
                  onTap: () => setState(() {
                    _selectedOs = 'windows';
                    _swipedItemId = null;
                  }),
                ),
                _buildSegmentTab(
                  label: 'macOS',
                  selected: _selectedOs == 'macos',
                  onTap: () => setState(() {
                    _selectedOs = 'macos';
                    _swipedItemId = null;
                  }),
                ),
                _buildSegmentTab(
                  label: 'Linux',
                  selected: _selectedOs == 'linux',
                  onTap: () => setState(() {
                    _selectedOs = 'linux';
                    _swipedItemId = null;
                  }),
                ),
              ],
            ),
          ),
        ),
        // "+ Add" button row
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 8, 26, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _isAddPage = true;
                  _addTabIndex = 0;
                  _selectedKeys.clear();
                  _selectedSysOpIndex = null;
                  _nameController.clear();
                  _customCharController.clear();
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_circle_rounded,
                        color: _activeBlue, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Add',
                      style: TextStyle(
                        color: _activeBlue,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // White Rounded Reorderable + Swipe-to-Delete List
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: list.length,
                  onReorder: (oldIndex, newIndex) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = list.removeAt(oldIndex);
                      list.insert(newIndex, item);
                      _saveCurrentOs();
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = list[index];
                    final isSwiped = _swipedItemId == item.id;
                    return _buildSwipeableShortcutRow(
                      key: ValueKey(item.id),
                      item: item,
                      index: index,
                      isLast: index == list.length - 1,
                      isSwiped: isSwiped,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwipeableShortcutRow({
    required Key key,
    required DeskInShortcutItem item,
    required int index,
    required bool isLast,
    required bool isSwiped,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx < -6 && _swipedItemId != item.id) {
          HapticFeedback.selectionClick();
          setState(() => _swipedItemId = item.id);
        } else if (d.delta.dx > 6 && _swipedItemId == item.id) {
          setState(() => _swipedItemId = null);
        }
      },
      onTap: () {
        if (isSwiped) {
          setState(() => _swipedItemId = null);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 46,
            child: Stack(
              children: [
                // Background Delete Action (DeskIn Red Delete Button)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 82,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _currentList.removeAt(index);
                        _swipedItemId = null;
                        _saveCurrentOs();
                      });
                    },
                    child: Container(
                      color: _deleteRed,
                      alignment: Alignment.center,
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                // Foreground Sliding Row
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: isSwiped ? -82 : 0,
                  right: isSwiped ? 82 : 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 8),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: Color(0xFFB8BFC8),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!isLast)
            const Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFFF0F2F5),
            ),
        ],
      ),
    );
  }

  Widget _buildAddView() {
    final isMacTab = _selectedOs == 'macos';
    final hasValidSelection = _addTabIndex == 0
        ? _buildFinalKeysList().isNotEmpty
        : _selectedSysOpIndex != null;
    final autoPlaceholder = _addTabIndex == 0 && _buildAutoComboName().isNotEmpty
        ? _buildAutoComboName()
        : 'Please enter name';

    final row1Keys = [
      'Ctrl',
      isMacTab ? 'Option' : 'Alt',
      isMacTab ? 'Cmd' : 'Win',
      'Shift',
      'Tab',
      'Esc',
      'Home',
      'Enter',
    ];
    const row2Keys = [
      'Caps Lock',
      'Space',
      'Back Space',
      'Insert',
      'PageUp',
      'PageDown',
      '-',
      '↑',
      '+',
    ];
    const row3Keys = [
      'Delete',
      'End',
      'F1',
      'F2',
      'F3',
      'F4',
      'F5',
      'F6',
      '←',
      '↓',
      '→',
    ];
    const row4Keys = ['F7', 'F8', 'F9', 'F10', 'F11', 'F12'];

    return Column(
      children: [
        // Top Header: "<" Back, "Add" Title, "X" Close
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 12, 6),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chevron_left_rounded,
                      color: Color(0xFF4E5969), size: 28),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isAddPage = false);
                  },
                ),
              ),
              const Expanded(
                child: Text(
                  'Add',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                height: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF4E5969), size: 23),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
        // Segmented Control: Keyboard keys | System operation
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 100, vertical: 6),
          child: Container(
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _bgSegment,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                _buildSegmentTab(
                  label: 'Keyboard keys',
                  selected: _addTabIndex == 0,
                  onTap: () => setState(() => _addTabIndex = 0),
                ),
                _buildSegmentTab(
                  label: 'System operation',
                  selected: _addTabIndex == 1,
                  onTap: () => setState(() => _addTabIndex = 1),
                ),
              ],
            ),
          ),
        ),
        // Name Input + Add Button Row (Matching Screenshot 2)
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 10, 26, 10),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Name',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: autoPlaceholder,
                            hintStyle: const TextStyle(
                              color: Color(0xFFC0C6CF),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: hasValidSelection ? _handleConfirmAdd : null,
                child: Container(
                  width: 118,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hasValidSelection ? _activeBlue : _disabledBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Body: Either Keyboard Key Grid or System Operation Presets
        Expanded(
          child: _addTabIndex == 0
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 2, 26, 14),
                  child: Column(
                    children: [
                      _buildKeyCapRow(row1Keys),
                      const SizedBox(height: 8),
                      _buildKeyCapRow(row2Keys),
                      const SizedBox(height: 8),
                      _buildKeyCapRow(row3Keys),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final k in row4Keys) ...[
                            Expanded(
                              flex: 10,
                              child: _buildKeyCap(k),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            flex: 42,
                            child: Container(
                              height: 40,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: TextField(
                                controller: _customCharController,
                                textAlign: TextAlign.center,
                                onChanged: (_) => setState(() {}),
                                style: const TextStyle(
                                  color: _textDark,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'Enter letters/numbers/symbols',
                                  hintStyle: TextStyle(
                                    color: Color(0xFFC0C6CF),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : _buildSystemOperationList(),
        ),
      ],
    );
  }

  Widget _buildKeyCapRow(List<String> keys) {
    return Row(
      children: [
        for (int i = 0; i < keys.length; i++) ...[
          Expanded(
            flex: (keys[i].length > 5) ? 14 : (keys[i].length == 1 ? 9 : 11),
            child: _buildKeyCap(keys[i]),
          ),
          if (i < keys.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _buildKeyCap(String keyLabel) {
    final selected = _selectedKeys.contains(keyLabel);
    final displayLabel = keyLabel == 'Caps Lock'
        ? 'Caps\nLock'
        : (keyLabel == 'Back Space' ? 'Back\nSpace' : keyLabel);
    return GestureDetector(
      onTap: () => _toggleKeyInCombo(keyLabel),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _activeBlue : Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? _activeBlue : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          displayLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : _textDark,
            fontSize: keyLabel.length > 5 ? 11.0 : 12.5,
            height: 1.15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSystemOperationList() {
    final ops = _getSystemOperationsForOs(_selectedOs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 2, 26, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: ops.length,
          separatorBuilder: (_, __) => const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFFF0F2F5),
          ),
          itemBuilder: (ctx, idx) {
            final op = ops[idx];
            final selected = _selectedSysOpIndex == idx;
            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedSysOpIndex = idx);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      op.label,
                      style: TextStyle(
                        color: selected ? _activeBlue : _textDark,
                        fontSize: 14.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? _activeBlue : const Color(0xFFC9CDD4),
                      size: 20,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSegmentTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _textDark : _textMuted,
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
