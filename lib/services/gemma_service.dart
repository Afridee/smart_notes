import 'dart:developer' show log;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:get/get.dart';

/// Owns the Gemma inference model lifecycle:
/// download/install (idempotent), warm-up, and chat creation.
class GemmaService extends GetxService {
  /// LiteRT-LM bundle for on-device Gemma 4 E4B IT (same family as
  /// [google/gemma-4-E4B-it](https://huggingface.co/google/gemma-4-E4B-it) PyTorch
  /// weights, but not the safetensors file — flutter_gemma needs `.litertlm`).
  /// See [litert-community/gemma-4-E4B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) (~4.3GB, ungated).
  static const String defaultModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm';

  static const ModelType modelType = ModelType.gemmaIt;
  static const ModelFileType fileType = ModelFileType.litertlm;
  /// Context window for the LiteRT session. Gemma 4 / `.litertlm` often fails
  /// inference (invoke status 13) if this is too small for template + RAG input.
  /// RAG still truncates via [RagService] to limit actual prompt size.
  static const int defaultMaxTokens = 2048;

  final isInstalled = false.obs;
  final isReady = false.obs;
  final downloadPct = 0.obs;
  final lastError = RxnString();

  InferenceModel? _model;
  InferenceModel? get model => _model;

  /// Context window size of the loaded inference model (for RAG prompt budgeting).
  int get loadedMaxTokens => _model?.maxTokens ?? defaultMaxTokens;

  Future<void> _closeChat(InferenceChat? chat) async {
    if (chat == null) return;
    try {
      await chat.close();
    } catch (e, st) {
      log(
        'GemmaService: failed to close chat (may already be closed)',
        name: 'GemmaService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Releases the active [InferenceModel.chat] session, if any.
  Future<void> closeCurrentChat() async {
    await _closeChat(_model?.chat);
  }

  Future<GemmaService> ensureInstalled({
    String? url,
    String? hfToken,
  }) async {
    try {
      lastError.value = null;
      await FlutterGemma.installModel(modelType: modelType, fileType: fileType)
          .fromNetwork(url ?? defaultModelUrl, token: hfToken)
          .withProgress((p) => downloadPct.value = p)
          .install();
      isInstalled.value = true;
      return this;
    } catch (e, st) {
      lastError.value = e.toString();
      log(
        'GemmaService.ensureInstalled failed',
        name: 'GemmaService',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<GemmaService> warmup({
    int maxTokens = defaultMaxTokens,
    PreferredBackend? preferredBackend,
  }) async {
    if (_model != null) {
      isReady.value = true;
      return this;
    }
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
    );
    isReady.value = true;
    return this;
  }

  Future<InferenceChat> newChat({
    String? systemInstruction,
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
  }) async {
    final m = _model;
    if (m == null) {
      throw StateError('GemmaService.warmup() must be called before newChat().');
    }
    // flutter_gemma overwrites [InferenceModel.chat] without closing the old
    // session; leak / memory growth otherwise.
    await _closeChat(m.chat);
    return m.createChat(
      temperature: temperature,
      topK: topK,
      topP: topP,
      systemInstruction: systemInstruction,
    );
  }

  @override
  void onClose() {
    _model?.close();
    super.onClose();
  }
}
