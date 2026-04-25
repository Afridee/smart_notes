import 'package:flutter_test/flutter_test.dart';

import 'package:smart_notes/services/chunker_service.dart';

void main() {
  group('ChunkerService', () {
    final chunker = ChunkerService();

    test('returns empty list for blank text', () {
      expect(chunker.split('   '), isEmpty);
    });

    test('returns single chunk for short text', () {
      final out = chunker.split('Hello world.');
      expect(out, hasLength(1));
      expect(out.first, 'Hello world.');
    });

    test('splits long text into multiple chunks', () {
      final long = List.generate(800, (i) => 'word$i').join(' ');
      final out = chunker.split(long, targetTokens: 100);
      expect(out.length, greaterThan(1));
    });
  });
}
