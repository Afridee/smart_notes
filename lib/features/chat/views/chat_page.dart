import 'package:flutter/material.dart';
import 'package:get/get.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask your notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: controller.clear,
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
            Obx(() => Text(message.text.value)),
            if (message.citations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < message.citations.length; i++)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '#${i + 1} · ${message.citations[i].score.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall,
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
