import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../../data/models/note.dart';
import '../../../routes/app_routes.dart';
import '../../../services/gemma_service.dart';
import '../controllers/graph_controller.dart';

class GraphNodeSheet extends StatelessWidget {
  const GraphNodeSheet({super.key, required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final graph = Get.find<GraphController>();
    final related = graph.relatedForNote(note.id);
    final preview = note.body.trim();
    final previewShort =
        preview.length <= 100 ? preview : '${preview.substring(0, 100)}…';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.48,
      minChildSize: 0.22,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161616),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          note.title.trim().isEmpty ? '(Untitled)' : note.title,
                          style: GoogleFonts.dmSerifDisplay(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          previewShort.isEmpty ? '—' : previewShort,
                          style: GoogleFonts.syne(
                            fontSize: 14,
                            height: 1.35,
                            color: Colors.white.withOpacity(0.75),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Related Notes',
                          style: GoogleFonts.syne(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ),
                    if (related.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'No edges above the similarity threshold yet.',
                            style: GoogleFonts.syne(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final r = related[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: _RelatedWhyRow(
                                focus: note,
                                related: r.other,
                                scorePercent:
                                    (r.score * 100).round().clamp(0, 100),
                              ),
                            );
                          },
                          childCount: related.length,
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                      sliver: SliverToBoxAdapter(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            Get.toNamed(AppRoutes.noteEditor, arguments: note);
                          },
                          child: Text(
                            'Open Note',
                            style: GoogleFonts.syne(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RelatedWhyRow extends StatefulWidget {
  const _RelatedWhyRow({
    required this.focus,
    required this.related,
    required this.scorePercent,
  });

  final Note focus;
  final Note related;
  final int scorePercent;

  @override
  State<_RelatedWhyRow> createState() => _RelatedWhyRowState();
}

class _RelatedWhyRowState extends State<_RelatedWhyRow> {
  bool _loading = false;
  String? _text;

  GraphController get _g => Get.find<GraphController>();

  GemmaService get _gemma => Get.find<GemmaService>();

  @override
  void initState() {
    super.initState();
    final key = _g.pairKey(widget.focus.id, widget.related.id);
    _text = _g.whyExplanationCache[key];
  }

  Future<void> _onWhy() async {
    if (_loading) return;
    final key = _g.pairKey(widget.focus.id, widget.related.id);
    final cached = _g.whyExplanationCache[key];
    if (cached != null && cached.isNotEmpty) {
      setState(() => _text = cached);
      return;
    }

    if (!_gemma.isReady.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemma is not ready yet.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final s = await _g.generateWhySentence(widget.focus, widget.related);
      if (mounted) setState(() => _text = s);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not explain: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.related.title.trim().isEmpty
        ? '(Untitled)'
        : widget.related.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  Get.toNamed(AppRoutes.noteEditor, arguments: widget.related);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.syne(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.scorePercent}% similar',
                        style: GoogleFonts.syne(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_text == null && !_loading)
              TextButton(
                onPressed: _onWhy,
                child: Text(
                  'Why?',
                  style: GoogleFonts.syne(
                    color: const Color(0xFFB8B3FF),
                  ),
                ),
              ),
          ],
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Shimmer.fromColors(
              baseColor: Colors.white.withOpacity(0.08),
              highlightColor: Colors.white.withOpacity(0.22),
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        if (_text != null && _text!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 4),
            child: Text(
              _text!,
              style: GoogleFonts.syne(
                fontSize: 13,
                height: 1.35,
                color: Colors.white.withOpacity(0.82),
              ),
            ),
          ),
      ],
    );
  }
}
