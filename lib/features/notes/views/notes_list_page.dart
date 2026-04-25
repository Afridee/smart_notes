import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/note.dart';
import '../../../routes/app_routes.dart';
import '../controllers/notes_controller.dart';

class NotesListPage extends GetView<NotesController> {
  const NotesListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Notes'),
        actions: [
          IconButton(
            tooltip: 'Ask',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Get.toNamed(AppRoutes.chat),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(AppRoutes.noteEditor),
        icon: const Icon(Icons.add),
        label: const Text('New note'),
      ),
      body: Obx(() {
        final items = controller.notes;
        if (items.isEmpty) {
          return const _EmptyState();
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final note = items[i];
            return _NoteTile(
              note: note,
              onTap: () => Get.toNamed(
                AppRoutes.noteEditor,
                arguments: note,
              ),
              onDelete: () => controller.deleteNote(note),
            );
          },
        );
      }),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          note.title.isEmpty ? '(untitled)' : note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          note.body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notes_outlined, size: 56),
            const SizedBox(height: 12),
            Text('No notes yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Tap “New note” to write something. '
              'Then ask the assistant about it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
