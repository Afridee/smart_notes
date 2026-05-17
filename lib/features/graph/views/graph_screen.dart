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

/// Max line width inside a node (full title wraps within this).
const double _kNodeTextMaxWidth = 260;

const double _kNodeMinWidth = 92;
const double _kNodeMinHeight = 44;
const double _kNodePadH = 20;
const double _kNodePadV = 12;

/// Border (e.g. selection glow) eats inset; keep measured box slightly larger.
const double _kNodeBoxSlack = 4;

/// Extra vertical room so rendered [Text] matches [TextPainter] line metrics.
const double _kNodeHeightSlack = 8;

/// Fallback if a note id is missing from [SemanticGraphLayout.nodeSizes].
const double _kNodeLayFallbackW = 168;
const double _kNodeLayFallbackH = 56;

String _graphNodeDisplayTitle(String title) {
  final t = title.trim();
  return t.isEmpty ? 'Untitled' : t;
}

/// Text style must match [_NodeChip] labels for layout measurement.
TextStyle _graphNodeTitleTextStyle() => GoogleFonts.dmSerifDisplay(
      color: Colors.white,
      fontSize: 13,
      height: 1.2,
    );

Map<int, Size> measureGraphNodeSizes(List<Note> notes) {
  final style = _graphNodeTitleTextStyle();
  final out = <int, Size>{};
  for (final n in notes) {
    final text = _graphNodeDisplayTitle(n.title);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    // First pass: cap width at [_kNodeTextMaxWidth]. Second pass: the real inner
    // width after applying [_kNodeMinWidth], so titles don't reflow (e.g.
    // "Untitled" fitting [minWidth] but measured as one wide line).
    var innerW = _kNodeTextMaxWidth.toDouble();
    late double outerW;
    for (var pass = 0; pass < 2; pass++) {
      tp.layout(maxWidth: innerW);
      outerW = math.max(
        _kNodeMinWidth,
        tp.width + _kNodePadH * 2 + _kNodeBoxSlack,
      );
      innerW = (outerW - _kNodePadH * 2).clamp(1.0, double.infinity);
    }

    final w = outerW;
    final h = math.max(
      _kNodeMinHeight,
      tp.height + _kNodePadV * 2 + _kNodeBoxSlack + _kNodeHeightSlack,
    );
    out[n.id] = Size(w, h);
  }
  return out;
}

class SemanticGraphLayout {
  SemanticGraphLayout({
    required this.positions,
    required this.size,
    required this.nodeSizes,
  });

  final Map<int, Offset> positions;
  final Size size;
  final Map<int, Size> nodeSizes;

  Size sizeOf(int noteId) =>
      nodeSizes[noteId] ??
      const Size(_kNodeLayFallbackW, _kNodeLayFallbackH);
}

/// Places connected components in circular clusters; unlinked notes in a grid below.
SemanticGraphLayout computeSemanticGraphLayout({
  required List<Note> notes,
  required List<NoteEdge> edges,
  required Map<int, Size> nodeSizes,
}) {
  Size szOf(int id) =>
      nodeSizes[id] ?? const Size(_kNodeLayFallbackW, _kNodeLayFallbackH);

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

  void bump(Offset c, int noteId) {
    final s = szOf(noteId);
    maxX = math.max(maxX, c.dx + s.width / 2 + 48);
    maxY = math.max(maxY, c.dy + s.height / 2 + 48);
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
    final maxSide = comp
        .map((id) => math.max(szOf(id).width, szOf(id).height))
        .reduce(math.max);
    final rBase = n <= 2 ? 130.0 : 95.0 + 22.0 * (n - 2).clamp(0, 8);
    final r = math.max(rBase, maxSide * 0.52 + 28);

    if (n == 1) {
      final id = comp[0];
      final c = Offset(cx, cy);
      positions[id] = c;
      bump(c, id);
    } else {
      for (var i = 0; i < n; i++) {
        final id = comp[i];
        final angle = -math.pi / 2 + 2 * math.pi * i / n;
        final c = Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
        positions[id] = c;
        bump(c, id);
      }
    }
    compIndex++;
  }

  var rowX = 72.0;
  var rowY = baseY + 320;
  var rowH = 0.0;
  const colGap = 20.0;
  const rowGap = 28.0;
  const maxRow = 920.0;

  for (final note in notes) {
    final id = note.id;
    if (inEdge.contains(id)) continue;
    final s = szOf(id);
    if (rowX + s.width > 72 + maxRow && rowX > 72) {
      rowX = 72;
      rowY += rowH + rowGap;
      rowH = 0;
    }
    final c = Offset(rowX + s.width / 2, rowY + s.height / 2);
    positions[id] = c;
    bump(c, id);
    rowX += s.width + colGap;
    rowH = math.max(rowH, s.height);
  }

  return SemanticGraphLayout(
    positions: positions,
    nodeSizes: nodeSizes,
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

          final nodeSizes = measureGraphNodeSizes(notes);
          final layout = computeSemanticGraphLayout(
            notes: notes,
            edges: edges,
            nodeSizes: nodeSizes,
          );

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
                child: _GraphViewport(
                  key: const ValueKey<String>('semantic_graph_viewport'),
                  controller: controller,
                  layout: layout,
                  edges: edges,
                  notes: notes,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Interactive graph with optional one-shot zoom to the note opened from the list.
class _GraphViewport extends StatefulWidget {
  const _GraphViewport({
    super.key,
    required this.controller,
    required this.layout,
    required this.edges,
    required this.notes,
  });

  final GraphController controller;
  final SemanticGraphLayout layout;
  final List<NoteEdge> edges;
  final List<Note> notes;

  @override
  State<_GraphViewport> createState() => _GraphViewportState();
}

class _GraphViewportState extends State<_GraphViewport> {
  bool _didScheduleViewportFocus = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport =
            Size(constraints.maxWidth, constraints.maxHeight);
        if (!_didScheduleViewportFocus &&
            widget.controller.pendingGraphViewportFocus) {
          _didScheduleViewportFocus = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.controller.focusGraphViewportOnSelectedIfPending(
              positions: widget.layout.positions,
              viewport: viewport,
            );
          });
        }

        return InteractiveViewer(
          transformationController: widget.controller.graphTransform,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(640),
          minScale: 0.25,
          maxScale: 5,
          child: SizedBox(
            width: widget.layout.size.width,
            height: widget.layout.size.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: widget.layout.size,
                  painter: _EdgesPainter(
                    edges: widget.edges,
                    positions: widget.layout.positions,
                    threshold: kGraphSimilarityThreshold,
                  ),
                ),
                for (final note in widget.notes)
                  _PositionedNoteNode(
                    layout: widget.layout,
                    note: note,
                    center: widget.layout.positions[note.id] ?? Offset.zero,
                    controller: widget.controller,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PositionedNoteNode extends StatelessWidget {
  const _PositionedNoteNode({
    required this.layout,
    required this.note,
    required this.center,
    required this.controller,
  });

  final SemanticGraphLayout layout;
  final Note note;
  final Offset center;
  final GraphController controller;

  @override
  Widget build(BuildContext context) {
    final id = note.id;
    final box = layout.sizeOf(id);
    return Positioned(
      left: center.dx - box.width / 2,
      top: center.dy - box.height / 2,
      width: box.width,
      height: box.height,
      child: Obx(() {
        final _ = controller.selectedNoteId.value;
        final opacity = controller.opacityForNode(id);
        final glow = controller.selectedGlow(id);
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          opacity: opacity,
          child: _NodeChip(
            label: _graphNodeDisplayTitle(note.title),
            size: box,
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
        );
      }),
    );
  }
}

class _NodeChip extends StatelessWidget {
  const _NodeChip({
    required this.label,
    required this.size,
    required this.glow,
    required this.onTap,
  });

  final String label;
  final Size size;
  final bool glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final halfShortSide = math.min(size.width, size.height) / 2;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        width: size.width,
        height: size.height,
        padding: const EdgeInsets.symmetric(
          horizontal: _kNodePadH,
          vertical: _kNodePadV,
        ),
        decoration: BoxDecoration(
          color: _kNodeFill,
          borderRadius: BorderRadius.circular(halfShortSide),
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
        alignment: Alignment.center,
        child: Text(
          label,
          style: _graphNodeTitleTextStyle(),
          textAlign: TextAlign.center,
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}
