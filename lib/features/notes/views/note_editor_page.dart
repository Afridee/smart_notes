import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/note.dart';
import '../../../routes/app_routes.dart';
import '../../../services/note_graph_service.dart';
import '../controllers/notes_controller.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final NotesController _notes;
  Note? _editing;

  @override
  void initState() {
    super.initState();
    _notes = Get.find<NotesController>();
    final arg = Get.arguments;
    if (arg is Note) {
      _editing = arg;
      _titleCtrl = TextEditingController(text: arg.title);
      _bodyCtrl = TextEditingController(text: arg.body);
    } else {
      _titleCtrl = TextEditingController();
      _bodyCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await _notes.saveNote(
        id: _editing?.id,
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
      );
      if (!mounted) return;
      Get.back();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing == null ? 'New note' : 'Edit note'),
        actions: [
          Obx(() => _notes.isSaving.value
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.save_outlined),
                  onPressed: _save,
                )),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextFormField(
                  controller: _bodyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note body',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              if (_editing != null && _editing!.id != 0) ...[
                const Divider(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Related Notes',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                _EditorRelatedNotes(noteId: _editing!.id),
              ],
              const SizedBox(height: 12),
              Obx(() => Text(
                    _notes.saveStatus.value,
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorRelatedNotes extends StatelessWidget {
  const _EditorRelatedNotes({required this.noteId});

  final int noteId;

  @override
  Widget build(BuildContext context) {
    final gs = Get.find<NoteGraphService>();
    final pairs = gs.topRelatedNotesWithScores(noteId, limit: 5);
    if (pairs.isEmpty) {
      return Text(
        'No related notes yet. Keep writing!',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in pairs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              row.$1.title.trim().isEmpty ? '(untitled)' : row.$1.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${(row.$2 * 100).round()}% similar'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () =>
                Get.toNamed(AppRoutes.noteEditor, arguments: row.$1),
          ),
      ],
    );
  }
}
