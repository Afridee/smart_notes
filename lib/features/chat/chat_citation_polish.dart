/// Normalizes messy chunk citation markup from small on-device LLMs after a
/// RAG reply. Context labels use `[#1]`, `[#2]`, …; models often duplicate
/// that with superscripts (^1) or footnote refs ([^1]).
String polishAssistantCitations(String input) {
  var s = input;

  // Merge duplicate chunk markers (#n/#^n paired with [#n]/[^n]); \s* allows no space.
  for (final re in [
    RegExp(r'#(\d+)\s*\[#\1\]'),
    RegExp(r'#(\d+)\s*\[\^\1\]'),
    RegExp(r'\^(\d+)\s*\[\^\1\]'),
    RegExp(r'\^(\d+)\s*\[#\1\]'),
  ]) {
    s = s.replaceAllMapped(re, (m) => '[#${m[1]}]');
  }

  // Collapse doubled identical chunk markers sometimes emitted as [#1][#1].
  for (var i = 0; i < 4; i++) {
    final before = s;
    s = s.replaceAllMapped(
      RegExp(r'\[#(\d+)\]\s*\[#\1\]'),
      (m) => '[#${m[1]}]',
    );
    if (s == before) break;
  }

  // Remove footnote refs that duplicate chunk markers (#n / [#n] / [^n]).
  // e.g. "[#1][^1]" or "[#1] [^1]" → "[#1]"
  for (var i = 0; i < 4; i++) {
    final before = s;
    s = s.replaceAllMapped(
      RegExp(r'\[#(\d+)\]\s*\[\^\1\]'),
      (m) => '[#${m[1]}]',
    );
    if (s == before) break;
  }

  return s;
}
