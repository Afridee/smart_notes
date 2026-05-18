import 'package:objectbox/objectbox.dart';

@Entity()
class NoteEdge {
  @Id()
  int id;

  /// Canonical ordering: always `noteIdA < noteIdB`.
  int noteIdA;

  int noteIdB;

  double similarityScore;

  NoteEdge({
    this.id = 0,
    this.noteIdA = 0,
    this.noteIdB = 0,
    this.similarityScore = 0,
  });
}
