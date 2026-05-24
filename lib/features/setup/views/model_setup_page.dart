import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/model_setup_controller.dart';

class ModelSetupPage extends GetView<ModelSetupController> {
  const ModelSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text("Afridee's notes",
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'First-run setup: downloading on-device models. '
                'This happens once.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              _ModelProgress(
                title: 'Gemma 4 E4B (inference)',
                subtitleBuilder: () => _gemmaSubtext(controller),
                progressBuilder: () =>
                    controller.gemma.downloadPct.value / 100.0,
                isDoneBuilder: () => controller.gemma.isReady.value,
              ),
              const SizedBox(height: 24),
              _ModelProgress(
                title: 'EmbeddingGemma (vectors)',
                subtitleBuilder: () => _embedderSubtext(controller),
                progressBuilder: () =>
                    controller.embedder.combinedPct / 100.0,
                isDoneBuilder: () => controller.embedder.isReady.value,
              ),
              const Spacer(),
              Obx(() {
                final err = controller.error.value;
                if (err == null) return const SizedBox.shrink();
                return Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Setup failed',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(err,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: controller.start,
                            child: const Text('Retry'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (!Get.find<ModelSetupController>().hasHfToken)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Heads up: HUGGINGFACE_TOKEN not set. EmbeddingGemma is gated '
                    '(accept Google’s license on Hugging Face, then add hf_... to '
                    'config.json and run with --dart-define-from-file=config.json).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Per-row copy so a global [SetupStage.error] does not look like Gemma failed
  /// when the embedder step is the one that hit HTTP 401.
  String _gemmaSubtext(ModelSetupController c) {
    if (c.gemma.isReady.value) return 'On-device model loaded';
    final s = c.stage.value;
    if (s == SetupStage.downloadingGemma) {
      return 'Downloading — ${c.gemma.downloadPct.value.clamp(0, 100)}%';
    }
    if (s == SetupStage.warmingGemma) return 'Loading into memory';
    if (s == SetupStage.error && !c.gemma.isReady.value) {
      return 'Failed — see message below';
    }
    return 'Waiting to start';
  }

  String _embedderSubtext(ModelSetupController c) {
    if (c.embedder.isReady.value) return 'Model and tokenizer ready';
    final s = c.stage.value;
    if (s == SetupStage.downloadingGemma || s == SetupStage.warmingGemma) {
      return 'After Gemma is ready';
    }
    if (s == SetupStage.downloadingEmbedder) {
      return 'Downloading TFLite + tokenizer — ${c.embedder.combinedPct.clamp(0, 100)}%';
    }
    if (s == SetupStage.warmingEmbedder) return 'Loading into memory';
    if (s == SetupStage.error && c.gemma.isReady.value && !c.embedder.isReady.value) {
      return 'Failed — usually missing HF token or license (see below)';
    }
    if (s == SetupStage.error) {
      return 'Failed — see message below';
    }
    return 'TFLite + sentencepiece (gated on Hugging Face)';
  }
}

class _ModelProgress extends StatelessWidget {
  const _ModelProgress({
    required this.title,
    required this.subtitleBuilder,
    required this.progressBuilder,
    required this.isDoneBuilder,
  });

  final String title;
  final String Function() subtitleBuilder;
  final double Function() progressBuilder;
  final bool Function() isDoneBuilder;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final pct = progressBuilder();
      final done = isDoneBuilder();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium)),
              Text(done
                  ? 'Ready'
                  : '${(pct * 100).clamp(0, 100).toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: done ? 1 : pct.clamp(0.0, 1.0),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitleBuilder(),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    });
  }
}
