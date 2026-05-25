/// Inclusive local-time window for filtering [NoteChunk] rows by `createdAt`.
class ChunkCreatedAtRange {
  const ChunkCreatedAtRange({
    required this.startInclusive,
    required this.endInclusive,
  });

  final DateTime startInclusive;
  final DateTime endInclusive;

  bool contains(DateTime d) =>
      !d.isBefore(startInclusive) && !d.isAfter(endInclusive);
}

/// Default retrieval window: from start of calendar day (~6 months ago) through
/// end of today (local timezone).
ChunkCreatedAtRange defaultChunkRetrievalRangeLocal() {
  final now = DateTime.now();
  final endInclusive =
      DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  final approxStart = DateTime(now.year, now.month - 6, now.day);
  final startInclusive =
      DateTime(approxStart.year, approxStart.month, approxStart.day);
  return ChunkCreatedAtRange(
    startInclusive: startInclusive,
    endInclusive: endInclusive,
  );
}

/// Normalize two picked calendar anchors to inclusive local day range [start … end].
ChunkCreatedAtRange normalizeChunkRange(DateTime anchorA, DateTime anchorB) {
  var dLo = DateTime(anchorA.year, anchorA.month, anchorA.day);
  var dHi = DateTime(anchorB.year, anchorB.month, anchorB.day);
  if (dLo.isAfter(dHi)) {
    final swap = dLo;
    dLo = dHi;
    dHi = swap;
  }
  return ChunkCreatedAtRange(
    startInclusive: dLo,
    endInclusive: DateTime(dHi.year, dHi.month, dHi.day, 23, 59, 59, 999),
  );
}
