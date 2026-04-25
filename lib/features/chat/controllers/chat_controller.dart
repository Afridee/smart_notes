import 'dart:async';
import 'dart:developer' show log;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:get/get.dart';

import '../../../services/embedding_service.dart';
import '../../../services/gemma_service.dart';
import '../../../services/rag_service.dart';
import '../../../services/vector_store_service.dart';

enum ChatRole { user, assistant, system }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    this.citations = const [],
  });

  final ChatRole role;
  final RxString text;
  final List<SimilarChunk> citations;

  factory ChatMessage.user(String text) =>
      ChatMessage(role: ChatRole.user, text: text.obs);

  factory ChatMessage.assistantStreaming() =>
      ChatMessage(role: ChatRole.assistant, text: ''.obs);

  factory ChatMessage.assistant(String text,
          {List<SimilarChunk> citations = const []}) =>
      ChatMessage(
        role: ChatRole.assistant,
        text: text.obs,
        citations: citations,
      );
}

class ChatController extends GetxController {
  ChatController({
    GemmaService? gemma,
    EmbeddingService? embedder,
    VectorStoreService? vectorStore,
    RagService? rag,
  })  : _gemma = gemma ?? Get.find<GemmaService>(),
        _embedder = embedder ?? Get.find<EmbeddingService>(),
        _vectorStore = vectorStore ?? Get.find<VectorStoreService>(),
        _rag = rag ?? Get.find<RagService>();

  final GemmaService _gemma;
  final EmbeddingService _embedder;
  final VectorStoreService _vectorStore;
  final RagService _rag;

  final messages = <ChatMessage>[].obs;
  final isAnswering = false.obs;
  final stage = ''.obs;

  InferenceChat? _chat;
  StreamSubscription<ModelResponse>? _activeSub;

  Future<void> _ensureChat() async {
    if (_chat != null) return;
    _chat = await _gemma.newChat(systemInstruction: _rag.systemInstruction);
  }

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || isAnswering.value) return;

    isAnswering.value = true;
    stage.value = 'Embedding question…';
    messages.add(ChatMessage.user(q));
    final assistant = ChatMessage.assistantStreaming();
    messages.add(assistant);

    try {
      await _ensureChat();

      final qVec = await _embedder.embed(q, taskType: TaskType.retrievalQuery);
      stage.value = 'Searching notes…';
      final hits = await _vectorStore.searchSimilar(qVec, k: 3);

      final prompt = _rag.buildPrompt(question: q, retrieved: hits);

      stage.value = 'Generating…';
      await _chat!.addQueryChunk(Message.text(text: prompt, isUser: true));
      final completer = Completer<void>();
      _activeSub = _chat!.generateChatResponseAsync().listen(
        (resp) {
          if (resp is TextResponse) {
            assistant.text.value += resp.token;
          }
        },
        onError: (e, st) {
          log('chat stream error', name: 'ChatController', error: e, stackTrace: st);
          assistant.text.value += '\n\n[error: $e]';
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      await completer.future;

      final updated = ChatMessage.assistant(
        assistant.text.value,
        citations: hits,
      );
      messages[messages.length - 1] = updated;
      stage.value = '';
    } catch (e, st) {
      log('ChatController.ask failed', name: 'ChatController', error: e, stackTrace: st);
      assistant.text.value += '\n\n[error: $e]';
      stage.value = 'Error';
    } finally {
      isAnswering.value = false;
      await _activeSub?.cancel();
      _activeSub = null;
    }
  }

  void clear() {
    messages.clear();
    _chat = null;
  }

  @override
  void onClose() {
    _activeSub?.cancel();
    super.onClose();
  }
}
