import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../../data/models/note.dart';
import '../../../routes/app_routes.dart';
import '../../../services/gemma_service.dart';
import '../controllers/graph_controller.dart';

/// Subscribes [Obx] to graph "Why?" reactive fields (side effect only).
void _consumeWhyRebuildSignals(GraphController g) {
  g.whyExplanationRevision.value;
  g.whyGeneratingPairs.length;
}

/// Dim base + brighter highlight so the sweep reads in light and dark themes.
({Color base, Color highlight}) _whyRowShimmerColors(ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  if (isDark) {
    final base = scheme.surfaceContainerHigh;
    final highlight = Color.alphaBlend(
      Colors.white.withOpacity(0.22),
      scheme.surfaceContainerHighest,
    );
    return (base: base, highlight: highlight);
  }
  final base = scheme.surfaceContainerHigh;
  final highlight = Color.alphaBlend(
    Colors.black.withOpacity(0.68),
    scheme.surfaceContainerLow,
  );
  return (base: base, highlight: highlight);
}

class GraphNodeSheet extends StatelessWidget {
  const GraphNodeSheet({super.key, required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final graph = Get.find<GraphController>();
    final scheme = Theme.of(context).colorScheme;
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
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outline.withOpacity(0.35),
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
                            color: scheme.onSurface,
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
                            color: scheme.onSurfaceVariant,
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
                            color: scheme.onSurface,
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
                              color: scheme.onSurfaceVariant.withOpacity(0.85),
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
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
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
  /// Outcomes we do not persist in [GraphController.whyExplanationCache], e.g.
  /// `'(No response)'`, so the row can still show them without an Obx bump.
  String? _localExplanation;

  GraphController get _g => Get.find<GraphController>();

  GemmaService get _gemma => Get.find<GemmaService>();

  String get _pairKey => _g.pairKey(widget.focus.id, widget.related.id);

  Future<void> _onWhy() async {
    final key = _pairKey;
    final cached = _g.whyExplanationCache[key];
    if (cached != null && cached.isNotEmpty) {
      setState(() => _localExplanation = null);
      return;
    }
    if (_g.whyGeneratingPairs.contains(key)) return;

    if (!_gemma.isReady.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemma is not ready yet.')),
      );
      return;
    }

    try {
      final s = await _g.generateWhySentence(widget.focus, widget.related);
      if (mounted) setState(() => _localExplanation = s);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not explain: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.related.title.trim().isEmpty
        ? '(Untitled)'
        : widget.related.title;
    final scheme = Theme.of(context).colorScheme;

    return Obx(() {
      _consumeWhyRebuildSignals(_g);
      final pk = _pairKey;
      final cached = _g.whyExplanationCache[pk];
      final displayed =
          (cached != null && cached.isNotEmpty) ? cached : _localExplanation;
      final hasExplained =
          displayed != null && displayed.isNotEmpty;
      final generating = _g.whyGeneratingPairs.contains(pk);
      final shimmer = _whyRowShimmerColors(scheme);

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
                    Get.toNamed(
                      AppRoutes.noteEditor,
                      arguments: widget.related,
                    );
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
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.scorePercent}% similar',
                          style: GoogleFonts.syne(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!hasExplained && !generating)
                TextButton(
                  onPressed: _onWhy,
                  child: Text(
                    'Why?',
                    style: GoogleFonts.syne(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (generating)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Shimmer.fromColors(
                baseColor: shimmer.base,
                highlightColor: shimmer.highlight,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: shimmer.base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          if (hasExplained)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Text(
                displayed,
                style: GoogleFonts.syne(
                  fontSize: 13,
                  height: 1.35,
                  color: scheme.onSurface.withOpacity(0.82),
                ),
              ),
            ),
        ],
      );
    });
  }
}

