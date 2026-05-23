import 'package:objectbox/objectbox.dart';

@Entity()
class Note {
  @Id()
  int id;

  String title;

  String body;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  /// Mean of all chunk embeddings for this note (768-D, same model as chunks).
  /// Empty means missing / not yet computed.
  @Property(type: PropertyType.floatVector)
  List<double> noteEmbedding;

  /// JSON array of [NoteAttachmentRef] maps (paths relative to app documents dir).
  String attachmentsJson;

  Note({
    this.id = 0,
    this.title = '',
    this.body = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    List<double>? noteEmbedding,
    this.attachmentsJson = '[]',
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        noteEmbedding = noteEmbedding ?? const <double>[];
}
