import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../models/note_chunk.dart';
import '../../objectbox.g.dart';

class ObjectBox {
  ObjectBox._(this.store)
      : noteBox = store.box<Note>(),
        chunkBox = store.box<NoteChunk>();

  final Store store;
  final Box<Note> noteBox;
  final Box<NoteChunk> chunkBox;

  static Future<ObjectBox> open() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${docsDir.path}/smart_notes_db');
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final store = await openStore(directory: dbDir.path);
    return ObjectBox._(store);
  }

  void close() => store.close();
}
