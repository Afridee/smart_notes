import 'package:get/get.dart';

import '../data/objectbox/objectbox.dart';
import '../services/chunker_service.dart';
import '../services/embedding_service.dart';
import '../services/gemma_service.dart';
import '../services/rag_service.dart';
import '../services/note_graph_service.dart';
import '../services/vector_store_service.dart';

/// Boot-time DI graph.
///
/// `ObjectBox` opens the database before any service that depends on it.
/// Both LLM services are registered eagerly but their model
/// downloads/warm-ups are kicked off from the setup page so progress
/// is reactive in the UI.
class InitialBindings extends Bindings {
  @override
  void dependencies() {
    Get.putAsync<ObjectBox>(() async => ObjectBox.open(), permanent: true);

    Get.put<GemmaService>(GemmaService(), permanent: true);
    Get.put<EmbeddingService>(EmbeddingService(), permanent: true);
    Get.put<ChunkerService>(ChunkerService(), permanent: true);
    Get.put<RagService>(RagService(), permanent: true);

    Get.lazyPut<VectorStoreService>(
      () => VectorStoreService(Get.find<ObjectBox>()),
      fenix: true,
    );

    Get.lazyPut<NoteGraphService>(
      () => NoteGraphService(
        Get.find<ObjectBox>(),
        Get.find<VectorStoreService>(),
      ),
      fenix: true,
    );
  }
}
