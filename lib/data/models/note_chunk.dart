import 'package:objectbox/objectbox.dart';

import 'note.dart';

@Entity()
class NoteChunk {
  @Id()
  int id;

  final note = ToOne<Note>();

  int chunkIndex;

  String text;

  /// Per-chunk context (e.g. "Title: ...\nCreated: ...\nUpdated: ...") that is
  /// embedded together with [text] and rendered above it in the RAG prompt.
  /// Empty for chunks created before this field was introduced.
  String contextHeader;

  // EmbeddingGemma & Gecko output 768D L2-normalized vectors,
  // so we can use cosine distance directly via dot product.
  @HnswIndex(
    dimensions: 768,
    distanceType: VectorDistanceType.cosine,
  )
  @Property(type: PropertyType.floatVector)
  List<double> embedding;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  NoteChunk({
    this.id = 0,
    this.chunkIndex = 0,
    this.text = '',
    this.contextHeader = '',
    List<double>? embedding,
    DateTime? createdAt,
  })  : embedding = embedding ?? const <double>[],
        createdAt = createdAt ?? DateTime.now();
}
