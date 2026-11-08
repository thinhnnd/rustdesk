import 'dart:convert';

import 'package:flutter_hbb/mobile/widgets/deskin_shortcut_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeskInShortcutRepository.tryParseItems', () {
    test('returns null for non-list JSON so callers use defaults', () {
      expect(DeskInShortcutRepository.tryParseItems(null), isNull);
      expect(DeskInShortcutRepository.tryParseItems('oops'), isNull);
      expect(DeskInShortcutRepository.tryParseItems({'id': 'x'}), isNull);
    });

    test('preserves an intentionally empty shortcut list', () {
      expect(DeskInShortcutRepository.tryParseItems(const []), isEmpty);
      expect(DeskInShortcutRepository.tryParseItems(jsonDecode('[]')), isEmpty);
    });

    test('parses items and drops entries without keys', () {
      final items = DeskInShortcutRepository.tryParseItems([
        {
          'id': 'a',
          'label': 'A',
          'keys': ['A']
        },
        {'id': 'b', 'label': 'Empty', 'keys': <String>[]},
        {
          'id': 'c',
          'label': 'C',
          'keys': ['Ctrl', 'C']
        },
      ]);
      expect(items, isNotNull);
      expect(items!.map((e) => e.id), ['a', 'c']);
    });

    test('deduplicates ids keeping the first occurrence', () {
      final items = DeskInShortcutRepository.tryParseItems([
        {
          'id': 'dup',
          'label': 'First',
          'keys': ['A']
        },
        {
          'id': 'dup',
          'label': 'Second',
          'keys': ['B']
        },
      ]);
      expect(items, hasLength(1));
      expect(items!.single.label, 'First');
    });

    test('skips malformed entries instead of dropping the whole list', () {
      final items = DeskInShortcutRepository.tryParseItems([
        {'id': 'a', 'label': 'A', 'keys': 'Ctrl+C'},
        {'id': 'b', 'label': 'B', 'keys': ['B']},
      ]);
      expect(items, isNotNull);
      expect(items!.single.id, 'b');
    });

    test('returns null when every stored entry is invalid', () {
      expect(DeskInShortcutRepository.tryParseItems([42, 'x']), isNull);
      expect(DeskInShortcutRepository.tryParseItems([{}]), isNull);
    });
  });
}
