import 'dart:async';

import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../data/models/chunk_retrieval_range.dart';
import '../../../data/models/note.dart';
import '../../../data/objectbox/objectbox.dart';
import '../../../routes/app_routes.dart';
import '../../../services/vector_store_service.dart';
import '../controllers/chat_controller.dart';
import '../smart_notes_attachment_opener.dart';

class ChatPage extends GetView<ChatController> {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final inputCtrl = TextEditingController();
    final scrollCtrl = ScrollController();

    void scrollToEnd() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollCtrl.hasClients) return;
        scrollCtrl.animateTo(
          scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hi, Afridee!'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(34),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Obx(() {
                  final theme = Theme.of(context);
                  final range = controller.chunkRetrievalRange.value;
                  return Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _chunkRetrievalRangeLabel(range),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          actions: [
            Obx(() {
              final busy = controller.isAnswering.value;
              return IconButton(
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: busy
                    ? null
                    : () {
                        unawaited(
                          _pickChunkRetrievalRange(context, controller),
                        );
                      },
              );
            }),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Obx(() {
                  final items = controller.messages;
                  scrollToEnd();
                  if (items.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Ask anything about your notes.\n'
                          'The model only sees the most relevant chunks.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _Bubble(message: items[i]),
                  );
                }),
              ),
              Obx(() {
                final s = controller.stage.value;
                if (s.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(s, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: inputCtrl,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Ask about your notes…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Obx(() {
                      final busy = controller.isAnswering.value;
                      return FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () {
                                final t = inputCtrl.text;
                                inputCtrl.clear();
                                controller.ask(t);
                              },
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final theme = Theme.of(context);
    final sourceNotes = message.citations.isEmpty
        ? const <Note>[]
        : _notesFromCitations(message.citations);
    final color = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(() {
              final text = message.text.value;
              if (isUser) {
                return Text(text);
              }
              return SelectionArea(
                child: GptMarkdown(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium,
                  followLinkColor: true,
                  onLinkTap: (url, title) async {
                    await openSmartNotesAttachmentFromChat(
                      context,
                      url,
                      message.citations,
                    );
                  },
                ),
              );
            }),
            if (sourceNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Sources',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final note in sourceNotes)
                    ActionChip(
                      avatar: Icon(
                        Icons.article_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      label: Text(
                        _referenceLabel(note.title),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          Get.toNamed(AppRoutes.noteEditor, arguments: note),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<Note> _notesFromCitations(List<SimilarChunk> citations) {
  final box = Get.find<ObjectBox>();
  final seen = <int>{};
  final out = <Note>[];
  for (final s in citations) {
    final id = s.chunk.note.targetId;
    if (id == 0 || seen.contains(id)) continue;
    seen.add(id);
    final note = box.noteBox.get(id);
    if (note != null) out.add(note);
  }
  return out;
}

String _referenceLabel(String title) {
  final t = title.trim();
  if (t.isEmpty) return 'Untitled note';
  if (t.length <= 52) return t;
  return '${t.substring(0, 50)}…';
}

String _chunkRetrievalRangeLabel(ChunkCreatedAtRange r) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String ordinalSuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    return switch (day % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }

  String friendly(DateTime d) =>
      '${d.day}${ordinalSuffix(d.day)} ${months[d.month - 1]}, ${d.year}';
  return '${friendly(r.startInclusive)} to ${friendly(r.endInclusive)}';
}

Future<void> _pickChunkRetrievalRange(
  BuildContext context,
  ChatController c,
) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final r = c.chunkRetrievalRange.value;
  final value = <DateTime?>[
    DateTime(
      r.startInclusive.year,
      r.startInclusive.month,
      r.startInclusive.day,
    ),
    DateTime(r.endInclusive.year, r.endInclusive.month, r.endInclusive.day),
  ];

  final picked = await showCalendarDatePicker2Dialog(
    context: context,
    config: CalendarDatePicker2WithActionButtonsConfig(
      calendarType: CalendarDatePicker2Type.range,
      firstDate: DateTime(2000),
      lastDate: today,
    ),
    dialogSize: const Size(325, 400),
    value: value,
    borderRadius: BorderRadius.circular(15),
  );
  if (!context.mounted) return;
  if (picked == null || picked.length < 2) return;
  final a = picked[0];
  final b = picked[1];
  if (a == null || b == null) return;
  c.setChunkRetrievalRange(normalizeChunkRange(a, b));
}
