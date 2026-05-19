import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../data/models/note.dart';
import '../../../data/objectbox/objectbox.dart';
import '../../../routes/app_routes.dart';
import '../../../services/vector_store_service.dart';
import '../controllers/chat_controller.dart';

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
          title: const Text('Ask your notes'),
          actions: [
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () async {
                await controller.clear();
              },
            ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                      onPressed: () => Get.toNamed(
                        AppRoutes.noteEditor,
                        arguments: note,
                      ),
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
