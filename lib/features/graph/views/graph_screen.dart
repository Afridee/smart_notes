import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Node;
import 'package:google_fonts/google_fonts.dart';

import '../../../data/models/note.dart';
import '../../../data/models/note_edge.dart';
import '../../../services/note_graph_service.dart';
import '../controllers/graph_controller.dart';
import '../widgets/graph_node_sheet.dart';

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
TextStyle _graphNodeTitleTextStyle(ColorScheme scheme) => GoogleFonts.dmSerifDisplay(
      color: scheme.onPrimary,
      fontSize: 13,
      height: 1.2,
    );

Map<int, Size> measureGraphNodeSizes(
  List<Note> notes, {
  required TextStyle titleStyle,
}) {
  final style = titleStyle;
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
    final rBase = n <= 2 ? 150.0 : 110.0 + 26.0 * (n - 2).clamp(0, 10);
    final r = math.max(rBase, maxSide * 0.62 + 36);

    if (n == 1) {
      final id = comp[0];
      positions[id] = Offset(cx, cy);
    } else {
      for (var i = 0; i < n; i++) {
        final id = comp[i];
        final angle = -math.pi / 2 + 2 * math.pi * i / n;
        positions[id] = Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
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
    rowX += s.width + colGap;
    rowH = math.max(rowH, s.height);
  }

  _separateOverlappingNodes(
    positions,
    nodeSizes,
    ids,
    gap: 12,
  );

  // Overlap resolution can move centers above/left of the initial placement.
  // Nodes must lie inside the Stack's SizedBox for hit testing; Clip.none
  // still paints overflow but taps outside the box do not reach children.
  const layoutMargin = 48.0;
  final bounds = _axisAlignedNodeBounds(positions, nodeSizes, ids);
  final tx = layoutMargin - bounds.left;
  final ty = layoutMargin - bounds.top;
  if (tx != 0.0 || ty != 0.0) {
    for (final id in ids) {
      final c = positions[id];
      if (c != null) positions[id] = Offset(c.dx + tx, c.dy + ty);
    }
  }

  final canvasW = math.max(520.0, bounds.width + 2 * layoutMargin);
  final canvasH = math.max(420.0, bounds.height + 2 * layoutMargin);

  return SemanticGraphLayout(
    positions: positions,
    nodeSizes: nodeSizes,
    size: Size(canvasW, canvasH),
  );
}

/// Tight axis-aligned bounds of all node chips (center ± half size).
Rect _axisAlignedNodeBounds(
  Map<int, Offset> positions,
  Map<int, Size> nodeSizes,
  Set<int> ids,
) {
  Size szOf(int id) =>
      nodeSizes[id] ?? const Size(_kNodeLayFallbackW, _kNodeLayFallbackH);

  var minL = double.infinity;
  var minT = double.infinity;
  var maxR = double.negativeInfinity;
  var maxB = double.negativeInfinity;

  for (final id in ids) {
    final c = positions[id];
    if (c == null) continue;
    final s = szOf(id);
    minL = math.min(minL, c.dx - s.width / 2);
    minT = math.min(minT, c.dy - s.height / 2);
    maxR = math.max(maxR, c.dx + s.width / 2);
    maxB = math.max(maxB, c.dy + s.height / 2);
  }

  if (!minL.isFinite || !minT.isFinite) {
    return const Rect.fromLTWH(0, 0, 520, 420);
  }
  return Rect.fromLTRB(minL, minT, maxR, maxB);
}

/// Pushes axis-aligned node boxes apart so they do not overlap (after initial placement).
void _separateOverlappingNodes(
  Map<int, Offset> positions,
  Map<int, Size> nodeSizes,
  Set<int> ids, {
  double gap = 10,
  int maxIterations = 120,
}) {
  Size szOf(int id) =>
      nodeSizes[id] ?? const Size(_kNodeLayFallbackW, _kNodeLayFallbackH);

  final list = ids.toList();
  for (var iter = 0; iter < maxIterations; iter++) {
    var anyOverlap = false;
    for (var a = 0; a < list.length; a++) {
      for (var b = a + 1; b < list.length; b++) {
        final idA = list[a];
        final idB = list[b];
        final cA = positions[idA];
        final cB = positions[idB];
        if (cA == null || cB == null) continue;

        final sA = szOf(idA);
        final sB = szOf(idB);
        final halfW = (sA.width + sB.width) / 2 + gap;
        final halfH = (sA.height + sB.height) / 2 + gap;
        final dx = cB.dx - cA.dx;
        final dy = cB.dy - cA.dy;
        final overlapX = halfW - dx.abs();
        final overlapY = halfH - dy.abs();
        if (overlapX <= 0 || overlapY <= 0) continue;

        anyOverlap = true;
        if (overlapX < overlapY) {
          final push = overlapX / 2 + 0.5;
          final sx = dx >= 0 ? 1.0 : -1.0;
          positions[idA] = Offset(cA.dx - sx * push, cA.dy);
          positions[idB] = Offset(cB.dx + sx * push, cB.dy);
        } else {
          final push = overlapY / 2 + 0.5;
          final sy = dy >= 0 ? 1.0 : -1.0;
          positions[idA] = Offset(cA.dx, cA.dy - sy * push);
          positions[idB] = Offset(cB.dx, cB.dy + sy * push);
        }
      }
    }
    if (!anyOverlap) break;
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.edges,
    required this.positions,
    required this.threshold,
    required this.edgeColor,
  });

  final List<NoteEdge> edges;
  final Map<int, Offset> positions;
  final double threshold;
  final Color edgeColor;

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
          ..color = edgeColor.withOpacity(opacity)
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.positions != positions ||
        oldDelegate.threshold != threshold ||
        oldDelegate.edgeColor != edgeColor;
  }
}

class GraphScreen extends GetView<GraphController> {
  const GraphScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final graphService = Get.find<NoteGraphService>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
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
              style: GoogleFonts.syne(color: scheme.onSurfaceVariant),
            ),
          );
        }

        final edges = graphService.edgesForGraphView(
          graphService.allEdges(),
          notes.length,
        );

        final titleStyle = _graphNodeTitleTextStyle(scheme);
        final nodeSizes = measureGraphNodeSizes(notes, titleStyle: titleStyle);
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
                  color: scheme.onSurfaceVariant.withOpacity(0.9),
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
                edgeLineColor: scheme.onSurface,
                nodeTitleStyle: titleStyle,
              ),
            ),
          ],
        );
      }),
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
    required this.edgeLineColor,
    required this.nodeTitleStyle,
  });

  final GraphController controller;
  final SemanticGraphLayout layout;
  final List<NoteEdge> edges;
  final List<Note> notes;
  final Color edgeLineColor;
  final TextStyle nodeTitleStyle;

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
                    threshold: kGraphSimilarityFloor,
                    edgeColor: widget.edgeLineColor,
                  ),
                ),
                for (final note in widget.notes)
                  _PositionedNoteNode(
                    layout: widget.layout,
                    note: note,
                    center: widget.layout.positions[note.id] ?? Offset.zero,
                    controller: widget.controller,
                    nodeTitleStyle: widget.nodeTitleStyle,
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
    required this.nodeTitleStyle,
  });

  final SemanticGraphLayout layout;
  final Note note;
  final Offset center;
  final GraphController controller;
  final TextStyle nodeTitleStyle;

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
            colorScheme: Theme.of(context).colorScheme,
            titleStyle: nodeTitleStyle,
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
    required this.colorScheme,
    required this.titleStyle,
    required this.onTap,
  });

  final String label;
  final Size size;
  final bool glow;
  final ColorScheme colorScheme;
  final TextStyle titleStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final halfShortSide = math.min(size.width, size.height) / 2;
    final borderGlowColor = colorScheme.onPrimary;
    // White halo reads well on dark filled chips; light backgrounds need a darker shadow.
    final shadowGlowColor = colorScheme.brightness == Brightness.dark
        ? borderGlowColor.withOpacity(0.55)
        : colorScheme.shadow.withOpacity(0.38);
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
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(halfShortSide),
          border: Border.all(
            color: glow ? borderGlowColor : Colors.transparent,
            width: glow ? 2 : 0,
          ),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: shadowGlowColor,
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ]
              : const [],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: titleStyle,
          textAlign: TextAlign.center,
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}
