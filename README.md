# smart_notes

Flutter app for notes with **on-device RAG** (retrieval-augmented generation): notes are chunked, embedded, and stored locally; questions retrieve relevant chunks and are answered with an on-device model.

## Architecture

On-device RAG uses `flutter_gemma` for embeddings and inference, and **ObjectBox** as the local vector store (HNSW index).

![On-device RAG architecture](docs/assets/rag-architecture.png)

### Save note flow

1. **Write a note** — user creates content.
2. **Chunk note text** — split into segments (about 500 tokens).
3. **Embed chunks** — `EmbeddingGemma` (`flutter_gemma`) produces vectors.
4. **Store in ObjectBox** — text, vectors, and metadata are indexed (HNSW) for search.

### Ask question flow

1. **Ask a question** — user query in chat.
2. **Embed question** — same `EmbeddingGemma` model as for notes.
3. **Vector search** — nearest neighbors in ObjectBox (e.g. top 3 chunks).
4. **Build prompt** — retrieved chunks are injected into a template.
5. **Gemma (on-device)** — `flutter_gemma` runs the shared on-device LLM on the prompt.
6. **Answer in chat** — response is shown to the user.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
