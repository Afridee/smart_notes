import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/note.dart';
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
