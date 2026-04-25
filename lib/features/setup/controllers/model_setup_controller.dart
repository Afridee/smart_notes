import 'dart:developer' show log;

import 'package:get/get.dart';

import '../../../routes/app_routes.dart';
import '../../../services/embedding_service.dart';
import '../../../services/gemma_service.dart';

enum SetupStage {
  idle,
  downloadingGemma,
  warmingGemma,
  downloadingEmbedder,
  warmingEmbedder,
  done,
  error,
}

class ModelSetupController extends GetxController {
  ModelSetupController({GemmaService? gemma, EmbeddingService? embedder})
      : _gemma = gemma ?? Get.find<GemmaService>(),
        _embedder = embedder ?? Get.find<EmbeddingService>();

  final GemmaService _gemma;
  final EmbeddingService _embedder;

  static const String _hfToken =
      String.fromEnvironment('HUGGINGFACE_TOKEN', defaultValue: '');

  final stage = SetupStage.idle.obs;
  final error = RxnString();

  GemmaService get gemma => _gemma;
  EmbeddingService get embedder => _embedder;

  bool get hasHfToken => _hfToken.isNotEmpty;

  @override
  void onReady() {
    super.onReady();
    start();
  }

  Future<void> start() async {
    if (stage.value == SetupStage.done) return;
    error.value = null;
    try {
      stage.value = SetupStage.downloadingGemma;
      await _gemma.ensureInstalled(hfToken: hasHfToken ? _hfToken : null);

      stage.value = SetupStage.warmingGemma;
      await _gemma.warmup();

      stage.value = SetupStage.downloadingEmbedder;
      await _embedder.ensureInstalled(
        hfToken: hasHfToken ? _hfToken : null,
      );

      stage.value = SetupStage.warmingEmbedder;
      await _embedder.warmup();

      stage.value = SetupStage.done;
      Get.offAllNamed(AppRoutes.notes);
    } catch (e, st) {
      error.value = e.toString();
      stage.value = SetupStage.error;
      log('ModelSetupController.start failed', name: 'ModelSetupController', error: e, stackTrace: st);
    }
  }
}
