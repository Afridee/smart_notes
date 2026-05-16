import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Node;
import 'package:google_fonts/google_fonts.dart';

import '../../../data/models/note.dart';
import '../../../data/models/note_edge.dart';
import '../../../services/note_graph_service.dart';
import '../controllers/graph_controller.dart';
import '../widgets/graph_node_sheet.dart';

const Color _kGraphBg = Color(0xFF0D0D0D);
const Color _kNodeFill = Color(0xFF6C63FF);

/// Layout box per node (centers are stored in [SemanticGraphLayout.positions]).
const double _kNodeLayW = 168;
const double _kNodeLayH = 56;

class SemanticGraphLayout {
  SemanticGraphLayout({
    required this.positions,
    required this.size,
  });

  final Map<int, Offset> positions;
  final Size size;
}

/// Places connected components in circular clusters; unlinked notes in a grid below.
SemanticGraphLayout computeSemanticGraphLayout({
  required List<Note> notes,
  required List<NoteEdge> edges,
}) {
  final ids = notes.map((n) => n.id).toSet();
  final filtered =
      edges.where((e) => ids.contains(e.noteIdA) && ids.contains(e.noteIdB)).toList();

  final inEdge = <int>{};
  final adj = <int, Set<int>>{};
  for (final e in filtered) {
    inEdge.add(e.noteIdA);
    inEdge.add(e.noteIdB);
    adj.putIfAbsent(e.noteIdA, () => {}).add(e.noteIdB);
    adj.putIfAbsent(e.noteIdB, () => {}).add(e.noteIdA);
  }

  final positions = <int, Offset>{};
  var maxX = 400.0;
  var maxY = 400.0;

  void bump(Offset c) {
    maxX = math.max(maxX, c.dx + _kNodeLayW / 2 + 48);
    maxY = math.max(maxY, c.dy + _kNodeLayH / 2 + 48);
  }

  final seen = <int>{};
  var compIndex = 0;
  const baseY = 220.0;
  const colPitch = 340.0;

  for (final start in inEdge) {
    if (seen.contains(start)) continue;
    final stack = <int>[start];
    seen.add(start);
    final comp = <int>[];
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      comp.add(u);
      for (final v in adj[u] ?? {}) {
        if (!seen.contains(v)) {
          seen.add(v);
          stack.add(v);
        }
      }
    }
    comp.sort();

    final cx = 220 + compIndex * colPitch;
    final cy = baseY;
    final n = comp.length;
    final r = n <= 2 ? 130.0 : 95.0 + 22.0 * (n - 2).clamp(0, 8);

    if (n == 1) {
      final c = Offset(cx, cy);
      positions[comp[0]] = c;
      bump(c);
    } else {
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + 2 * math.pi * i / n;
        final c = Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
        positions[comp[i]] = c;
        bump(c);
      }
    }
    compIndex++;
  }

  var ix = 72.0;
  var iy = baseY + 320;
  const isoW = 188.0;
  const isoH = 76.0;
  var rowAccum = 0.0;
  const maxRow = 920.0;

  for (final note in notes) {
    final id = note.id;
    if (inEdge.contains(id)) continue;
    if (rowAccum + isoW > maxRow) {
      ix = 72;
      iy += isoH;
      rowAccum = 0;
    }
    final c = Offset(ix + isoW / 2, iy + isoH / 2);
    positions[id] = c;
    bump(c);
    ix += isoW;
    rowAccum += isoW;
  }

  return SemanticGraphLayout(
    positions: positions,
    size: Size(math.max(520, maxX + 80), math.max(420, maxY + 80)),
  );
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.edges,
    required this.positions,
    required this.threshold,
  });

  final List<NoteEdge> edges;
  final Map<int, Offset> positions;
  final double threshold;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final a = positions[e.noteIdA];
      final b = positions[e.noteIdB];
      if (a == null || b == null) continue;
      final span = (1.0 - threshold).clamp(0.01, 1.0);
      final t =
          ((e.similarityScore - threshold) / span).clamp(0.0, 1.0).toDouble();
      final opacity = 0.14 + t * 0.48;
      final stroke = 0.85 + t * 2.3;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Colors.white.withOpacity(opacity)
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.positions != positions ||
        oldDelegate.threshold != threshold;
  }
}

class GraphScreen extends GetView<GraphController> {
  const GraphScreen({super.key});

  static String _nodeLabel(String title) {
    final t = title.trim().isEmpty ? 'Untitled' : title.trim();
    return t.length <= 20 ? t : '${t.substring(0, 20)}…';
  }

  @override
  Widget build(BuildContext context) {
    final graphService = Get.find<NoteGraphService>();

    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: _kGraphBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _kGraphBg,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Semantic graph',
            style: GoogleFonts.syne(fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh layout',
              icon: const Icon(Icons.refresh),
              onPressed: controller.rebuildGraph,
            ),
          ],
        ),
        body: Obx(() {
          final _ = controller.graphVersion.value;
          final notes = graphService.allNotesSorted();
          if (notes.isEmpty) {
            return Center(
              child: Text(
                'No notes to display yet.',
                style: GoogleFonts.syne(color: Colors.white54),
              ),
            );
          }

          final edges = graphService.edgesForGraphView(
            graphService.allEdges(),
            notes.length,
          );

          final layout = computeSemanticGraphLayout(notes: notes, edges: edges);

          final subtitle = edges.isEmpty
              ? 'No similarity edges yet. Save notes so embeddings run; similar pairs appear as lines.'
              : 'Pinch to zoom · drag to pan · lines = similarity (thicker = stronger). Notes without lines are not linked yet.';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  subtitle,
                  style: GoogleFonts.syne(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(640),
                  minScale: 0.25,
                  maxScale: 5,
                  child: SizedBox(
                    width: layout.size.width,
                    height: layout.size.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CustomPaint(
                          size: layout.size,
                          painter: _EdgesPainter(
                            edges: edges,
                            positions: layout.positions,
                            threshold: kGraphSimilarityThreshold,
                          ),
                        ),
                        for (final note in notes)
                          _PositionedNoteNode(
                            note: note,
                            center: layout.positions[note.id] ?? Offset.zero,
                            controller: controller,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _PositionedNoteNode extends StatelessWidget {
  const _PositionedNoteNode({
    required this.note,
    required this.center,
    required this.controller,
  });

  final Note note;
  final Offset center;
  final GraphController controller;

  @override
  Widget build(BuildContext context) {
    final id = note.id;
    return Positioned(
      left: center.dx - _kNodeLayW / 2,
      top: center.dy - _kNodeLayH / 2,
      width: _kNodeLayW,
      height: _kNodeLayH,
      child: Obx(() {
        final _ = controller.selectedNoteId.value;
        final opacity = controller.opacityForNode(id);
        final glow = controller.selectedGlow(id);
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          opacity: opacity,
          child: Center(
            child: _NodeChip(
              label: GraphScreen._nodeLabel(note.title),
              glow: glow,
              onTap: () {
                controller.selectNote(id);
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (ctx) => GraphNodeSheet(note: note),
                ).whenComplete(() => controller.selectNote(null));
              },
            ),
          ),
        );
      }),
    );
  }
}

class _NodeChip extends StatelessWidget {
  const _NodeChip({
    required this.label,
    required this.glow,
    required this.onTap,
  });

  final String label;
  final bool glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kNodeFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: glow ? Colors.white : Colors.transparent,
            width: glow ? 2 : 0,
          ),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.55),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSerifDisplay(
            color: Colors.white,
            fontSize: 13,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
