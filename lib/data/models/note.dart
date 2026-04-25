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

  Note({
    this.id = 0,
    this.title = '',
    this.body = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
}
