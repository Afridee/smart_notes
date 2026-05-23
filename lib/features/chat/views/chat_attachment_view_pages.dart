import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PdfAttachmentViewerPage extends StatefulWidget {
  const PdfAttachmentViewerPage({
    super.key,
    required this.path,
    required this.title,
  });

  final String path;
  final String title;

  @override
  State<PdfAttachmentViewerPage> createState() =>
      _PdfAttachmentViewerPageState();
}

class _PdfAttachmentViewerPageState extends State<PdfAttachmentViewerPage> {
  late final PdfController _controller = PdfController(
    document: PdfDocument.openFile(widget.path),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: PdfView(
        controller: _controller,
        scrollDirection: Axis.vertical,
        builders: PdfViewBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) => const Center(
            child: CircularProgressIndicator(),
          ),
          errorBuilder: (_, Exception err) => Center(
            child: Text('Could not load PDF:\n$err'),
          ),
        ),
      ),
    );
  }
}

class ImageAttachmentViewerPage extends StatelessWidget {
  const ImageAttachmentViewerPage({
    super.key,
    required this.path,
    required this.title,
  });

  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: InteractiveViewer(
        minScale: 0.25,
        maxScale: 8,
        child: Center(
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Could not display this image on this platform.'),
            ),
          ),
        ),
      ),
    );
  }
}
