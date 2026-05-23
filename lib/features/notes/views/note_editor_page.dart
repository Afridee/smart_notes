import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/note.dart';
import '../../../data/models/note_attachment.dart';
import '../../../routes/app_routes.dart';
import '../../../services/attachment_service.dart';
import '../../../services/note_graph_service.dart';
import '../controllers/notes_controller.dart';
import '../show_delete_note_confirmation.dart';

enum _EditorMenuAction { openGraph, duplicate, delete }

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
  late final String _draftAttachmentSessionId;
  final List<NoteAttachmentRef> _attachments = [];

  @override
  void initState() {
    super.initState();
    _notes = Get.find<NotesController>();
    _draftAttachmentSessionId =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
    final arg = Get.arguments;
    if (arg is Note) {
      _editing = arg;
      _titleCtrl = TextEditingController(text: arg.title);
      _bodyCtrl = TextEditingController(text: arg.body);
      _attachments.addAll(decodeAttachmentsJson(arg.attachmentsJson));
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

  Future<void> _pickPdf() async {
    final pick = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: false,
    );
    final picked = pick?.files.single;
    final path = picked?.path;
    if (picked == null || path == null) return;

    await _importPath(
      absolutePath: path,
      displayName:
          picked.name.trim().isNotEmpty ? picked.name : p.basename(path),
      mimeType: 'application/pdf',
    );
  }

  Future<void> _pickPhotos() async {
    final pick = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: false,
    );
    final files = pick?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final svc = Get.find<AttachmentService>();
    try {
      for (final f in files) {
        final path = f.path;
        if (path == null) continue;
        final mime = AttachmentService.mimeFromBasename(path);
        final ref = await svc.importFile(
          sourceAbsolutePath: path,
          displayName: f.name,
          mimeType: mime,
          draftId: _draftAttachmentSessionId,
          persistedNoteId:
              (_editing != null && _editing!.id != 0) ? _editing!.id : null,
        );
        _attachments.add(ref);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach image(s): $e')),
      );
    }
  }

  Future<void> _capturePhoto() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.camera);
    if (xFile == null) return;
    final mime = AttachmentService.mimeFromBasename(xFile.name);

    await _importPath(
      absolutePath: xFile.path,
      displayName: xFile.name,
      mimeType:
          xFile.mimeType != null && xFile.mimeType!.isNotEmpty ? xFile.mimeType! : mime,
    );
  }

  Future<void> _importPath({
    required String absolutePath,
    required String displayName,
    required String mimeType,
  }) async {
    try {
      final svc = Get.find<AttachmentService>();
      final ref = await svc.importFile(
        sourceAbsolutePath: absolutePath,
        displayName: displayName,
        mimeType: mimeType,
        draftId: _draftAttachmentSessionId,
        persistedNoteId:
            (_editing != null && _editing!.id != 0) ? _editing!.id : null,
      );
      _attachments.add(ref);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach file: $e')),
      );
    }
  }

  Future<void> _removeAttachment(int index) async {
    if (index < 0 || index >= _attachments.length) return;
    final ref = _attachments.removeAt(index);
    await Get.find<AttachmentService>().deleteFiles([ref]);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await _notes.saveNote(
        id: _editing?.id,
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        attachments: List<NoteAttachmentRef>.from(_attachments),
        draftAttachmentSessionId: _draftAttachmentSessionId,
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

  bool get _hasPersistedNote => _editing != null && _editing!.id != 0;

  Future<void> _deleteCurrentNote() async {
    if (!_hasPersistedNote) return;
    final ok = await showDeleteNoteConfirmation(context, _editing!);
    if (!ok || !mounted) return;
    try {
      await _notes.deleteNote(_editing!);
      if (!mounted) return;
      Get.back();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _duplicateNote() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final copyTitle =
        '${title.isEmpty ? 'Untitled note' : title} (copy)';

    Note result;
    try {
      if (_hasPersistedNote && _attachments.isNotEmpty) {
        final first = await _notes.saveNote(
          id: null,
          title: copyTitle,
          body: body,
          attachments: const <NoteAttachmentRef>[],
          draftAttachmentSessionId: '',
        );

        final duped = await Get.find<AttachmentService>()
            .duplicateAttachmentsForNote(
          refs: List<NoteAttachmentRef>.from(_attachments),
          destinationNoteId: first.id,
        );

        result = await _notes.saveNote(
          id: first.id,
          title: copyTitle,
          body: body,
          attachments: duped,
          draftAttachmentSessionId: '',
        );
      } else {
        result = await _notes.saveNote(
          id: null,
          title: copyTitle,
          body: body,
          attachments: List<NoteAttachmentRef>.from(_attachments),
          draftAttachmentSessionId: _draftAttachmentSessionId,
        );
      }
      if (!mounted) return;
      Get.offNamed(AppRoutes.noteEditor, arguments: result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copy failed: $e')),
      );
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Add PDF'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Add images'),
              subtitle: const Text('Photo library'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhotos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(ctx);
                _capturePhoto();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(_editing == null ? 'New note' : 'Edit note'),
          actions: [
            IconButton(
              tooltip: 'Add file',
              icon: const Icon(Icons.attach_file),
              onPressed: _showAttachmentMenu,
            ),
            Obx(() {
              if (_notes.isSaving.value) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final persisted = _hasPersistedNote;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Save',
                    icon: const Icon(Icons.save_outlined),
                    onPressed: _save,
                  ),
                  PopupMenuButton<_EditorMenuAction>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Note actions',
                    onSelected: (action) async {
                      switch (action) {
                        case _EditorMenuAction.openGraph:
                          Get.toNamed(AppRoutes.graph, arguments: _editing!);
                        case _EditorMenuAction.duplicate:
                          await _duplicateNote();
                        case _EditorMenuAction.delete:
                          await _deleteCurrentNote();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _EditorMenuAction.openGraph,
                        enabled: persisted,
                        child: const Row(
                          children: [
                            Icon(Icons.hub_outlined),
                            SizedBox(width: 12),
                            Text('Open in graph'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: _EditorMenuAction.duplicate,
                        child: const Row(
                          children: [
                            Icon(Icons.copy_outlined),
                            SizedBox(width: 12),
                            Text('Make a copy'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: _EditorMenuAction.delete,
                        enabled: persisted,
                        child: const Row(
                          children: [
                            Icon(Icons.delete_outline),
                            SizedBox(width: 12),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Attachments',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_attachments.isEmpty)
                  Text(
                    'PDFs or images saved in Documents. Tap the clip icon to add.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _attachments.length; i++)
                        InputChip(
                          label: Text(
                            _attachments[i].displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          avatar: Icon(
                            _attachments[i].mimeType.contains('pdf')
                                ? Icons.picture_as_pdf
                                : Icons.image_outlined,
                            size: 18,
                          ),
                          onDeleted: () => _removeAttachment(i),
                        ),
                    ],
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
            onTap: () => Get.toNamed(
              AppRoutes.noteEditor,
              arguments: row.$1,
              preventDuplicates: false,
            ),
          ),
      ],
    );
  }
}
