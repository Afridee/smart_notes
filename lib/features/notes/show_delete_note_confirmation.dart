import 'package:flutter/material.dart';

import '../../data/models/note.dart';

Future<bool> showDeleteNoteConfirmation(BuildContext context, Note note) async {
  final name = note.title.trim();
  final described = name.isEmpty ? 'this note' : 'the note "$name"';
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete note?'),
      content: Text('This will permanently delete $described.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result == true;
}
