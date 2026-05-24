import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';

import '../../../data/models/note.dart';
import '../../../routes/app_routes.dart';
import '../../../services/note_graph_service.dart';
import '../controllers/notes_controller.dart';
import '../show_delete_note_confirmation.dart';

class NotesListPage extends GetView<NotesController> {
  const NotesListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Afridee's notes"),
        actions: [
          IconButton(
            tooltip: 'Semantic graph',
            icon: const Icon(Icons.hub_outlined),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Get.toNamed(AppRoutes.graph);
            },
          ),
          IconButton(
            tooltip: 'Ask',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Get.toNamed(AppRoutes.chat);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Get.toNamed(AppRoutes.noteEditor);
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: ListenableBuilder(
              listenable: controller.searchFieldController,
              builder: (context, _) {
                final hasText =
                    controller.searchFieldController.text.isNotEmpty;
                final scheme = Theme.of(context).colorScheme;
                return TextField(
                  controller: controller.searchFieldController,
                  textInputAction: TextInputAction.search,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: InputDecoration(
                    hintText: 'Search notes',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: hasText
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: controller.clearSearch,
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Obx(() {
              final all = controller.notes;
              final q = controller.searchQuery.value;
              final items = _filterNotesForQuery(all, q);
              if (all.isEmpty) {
                return GestureDetector(
                  onTap: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  behavior: HitTestBehavior.opaque,
                  child: const _EmptyState(),
                );
              }
              if (items.isEmpty) {
                return GestureDetector(
                  onTap: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  behavior: HitTestBehavior.opaque,
                  child: _NoSearchResultsState(query: q.trim()),
                );
              }
              final crossAxis = _gridCrossAxisCount(context);
              return MasonryGridView.count(
                crossAxisCount: crossAxis,
                padding: const EdgeInsets.all(12),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final note = items[i];
                  return _NoteTile(
                    note: note,
                    bodyMaxLines: _gridBodyMaxLines(note, i),
                    onTap: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Get.toNamed(
                        AppRoutes.noteEditor,
                        arguments: note,
                      );
                    },
                    onDelete: () async {
                      final ok = await showDeleteNoteConfirmation(
                        context,
                        note,
                      );
                      if (ok) await controller.deleteNote(note);
                    },
                  );
                },
              );
            }),
          ),
          Obx(() {
            final gs = Get.find<NoteGraphService>();
            if (!gs.isIndexing.value) return const SizedBox.shrink();
            return const LinearProgressIndicator(minHeight: 2);
          }),
        ],
      ),
    );
  }
}

int _gridCrossAxisCount(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 1100) return 4;
  if (w >= 720) return 3;
  return 2;
}

List<Note> _filterNotesForQuery(List<Note> notes, String rawQuery) {
  final q = rawQuery.trim().toLowerCase();
  if (q.isEmpty) return notes.toList();
  return notes
      .where((n) {
        return n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q);
      })
      .toList();
}

/// Varies preview height so masonry tiles read as different-sized boxes.
int _gridBodyMaxLines(Note note, int index) {
  final x = (note.id.hashCode ^ index * 31).abs();
  return 2 + (x % 7);
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.bodyMaxLines,
    required this.onTap,
    required this.onDelete,
  });

  final Note note;
  final int bodyMaxLines;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = note.title.isEmpty ? '(untitled)' : note.title;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // IconButton(
                  //   tooltip: 'Delete',
                  //   icon: const Icon(Icons.delete_outline, size: 22),
                  //   visualDensity: VisualDensity.compact,
                  //   onPressed: onDelete,
                  // ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                note.body,
                maxLines: bodyMaxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoSearchResultsState extends StatelessWidget {
  const _NoSearchResultsState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No notes match your search',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              query.isEmpty ? '' : '“$query”',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
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
