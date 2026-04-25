import 'dart:developer' show log;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:get/get.dart';

/// Owns the EmbeddingGemma model lifecycle and exposes a thin
/// API for generating query/document vectors.
class EmbeddingService extends GetxService {
  /// EmbeddingGemma 512 (~179MB) — gated, requires HF token.
  static const String defaultModelUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq512_mixed-precision.tflite';
  static const String defaultTokenizerUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';
  static const String iosTokenizerUrl =
      'https://github.com/DenisovAV/flutter_gemma/releases/download/v0.12.5/embeddinggemma_tokenizer.json';

  final isInstalled = false.obs;
  final isReady = false.obs;
  final modelDownloadPct = 0.obs;
  final tokenizerDownloadPct = 0.obs;
  final lastError = RxnString();

  EmbeddingModel? _embedder;
  EmbeddingModel? get embedder => _embedder;

  /// Convenience aggregate of model+tokenizer progress for a single bar.
  int get combinedPct =>
      ((modelDownloadPct.value + tokenizerDownloadPct.value) / 2).floor();

  Future<EmbeddingService> ensureInstalled({
    String? modelUrl,
    String? tokenizerUrl,
    String? iosTokenizerUrl,
    String? hfToken,
  }) async {
    try {
      lastError.value = null;
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(modelUrl ?? defaultModelUrl, token: hfToken)
          .tokenizerFromNetwork(
            tokenizerUrl ?? defaultTokenizerUrl,
            token: hfToken,
            iosPath: iosTokenizerUrl ?? EmbeddingService.iosTokenizerUrl,
          )
          .withModelProgress((p) => modelDownloadPct.value = p)
          .withTokenizerProgress((p) => tokenizerDownloadPct.value = p)
          .install();
      isInstalled.value = true;
      return this;
    } catch (e, st) {
      lastError.value = e.toString();
      log(
        'EmbeddingService.ensureInstalled failed',
        name: 'EmbeddingService',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<EmbeddingService> warmup({PreferredBackend? preferredBackend}) async {
    if (_embedder != null) {
      isReady.value = true;
      return this;
    }
    _embedder = await FlutterGemma.getActiveEmbedder(
      preferredBackend: preferredBackend,
    );
    isReady.value = true;
    return this;
  }

  Future<List<double>> embed(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) {
    final e = _embedder;
    if (e == null) {
      throw StateError('EmbeddingService.warmup() must be called first.');
    }
    return e.generateEmbedding(text, taskType: taskType);
  }

  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalDocument,
  }) {
    final e = _embedder;
    if (e == null) {
      throw StateError('EmbeddingService.warmup() must be called first.');
    }
    return e.generateEmbeddings(texts, taskType: taskType);
  }

  Future<int> dimension() async {
    final e = _embedder;
    if (e == null) {
      throw StateError('EmbeddingService.warmup() must be called first.');
    }
    return e.getDimension();
  }

  @override
  void onClose() {
    _embedder?.close();
    super.onClose();
  }
}
