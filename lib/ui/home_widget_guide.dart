import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'components.dart';

/// An in-app preview of the launcher widgets. These Flutter cards illustrate
/// the native widget content; they are not launcher captures or controls.
class HomeWidgetGuide extends StatefulWidget {
  const HomeWidgetGuide({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeWidgetGuide> createState() => _HomeWidgetGuideState();
}

class _HomeWidgetGuideState extends State<HomeWidgetGuide> {
  Map<String, Object?> _snapshot = const {};
  bool _pinning = false;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  @override
  void didUpdateWidget(covariant HomeWidgetGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.state != widget.controller.state) {
      _loadSnapshot();
    }
  }

  Future<void> _loadSnapshot() async {
    try {
      final values = await Future.wait([
        widget.controller.widgetSnapshot(widgetId: null, kind: 'checklist'),
        widget.controller.widgetSnapshot(widgetId: null, kind: 'quick_lists'),
      ]);
      if (!mounted) return;
      setState(() {
        _snapshot = <String, Object?>{
          'checklist': _snapshotPart(values[0], 'checklist'),
          'quickLists': _snapshotPart(values[1], 'quickLists'),
          'pinSupported': values.any((value) => value['pinSupported'] == true),
        };
      });
    } catch (_) {
      // Older Android releases can render these Flutter previews without the
      // optional native snapshot or pin-request APIs.
    }
  }

  Future<void> _requestPin(String kind) async {
    if (_pinning) return;
    setState(() => _pinning = true);
    var accepted = false;
    try {
      accepted = await widget.controller.requestPinWidget(kind: kind);
    } catch (_) {
      accepted = false;
    } finally {
      if (mounted) setState(() => _pinning = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'Android opened a pin request. Follow the prompt to add it.'
                : 'Add it from your launcher’s Widgets picker.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final widgetColors = _WidgetPreviewColors.forContext(context);
    final active = state.outings.where((outing) => outing.isActive).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final outing = active.isEmpty ? null : active.first;
    final blueprint = outing == null
        ? state.blueprints.firstOrNull
        : state.blueprints
              .where((item) => item.id == outing.blueprintId)
              .firstOrNull;
    final fallbackTitle =
        outing?.blueprintName ?? blueprint?.name ?? 'Ready Yet?';
    final fallbackItems = outing != null
        ? outing.items
              .map((item) => (label: item.label, checked: item.checked))
              .toList()
        : blueprint?.items
                  .map((item) => (label: item.label, checked: false))
                  .toList() ??
              <({String label, bool checked})>[];
    final checkSnapshot = _snapshotMap(_snapshot['checklist']);
    final snapshotItems = _snapshotList(checkSnapshot['items'])
        .map(
          (item) => (
            label: item['label']?.toString() ?? '',
            checked: item['checked'] == true,
          ),
        )
        .where((item) => item.label.isNotEmpty)
        .toList();
    final items = snapshotItems.isNotEmpty ? snapshotItems : fallbackItems;
    final title = checkSnapshot['title']?.toString() ?? fallbackTitle;
    final checked = checkSnapshot['checked'] is int
        ? checkSnapshot['checked'] as int
        : outing?.checkedCount ?? 0;
    final total = checkSnapshot['total'] is int
        ? checkSnapshot['total'] as int
        : items.length;
    final progress =
        checkSnapshot['subtitle']?.toString() ??
        (outing == null
            ? blueprint == null
                  ? 'Open to see what to pack'
                  : total == 0
                  ? 'Add items before starting'
                  : '$total items ready to pack'
            : '$checked of $total packed');
    final actionLabel =
        checkSnapshot['primaryLabel']?.toString() ??
        (outing != null
            ? 'Open full outing'
            : blueprint == null
            ? 'Open app'
            : total == 0
            ? 'Add items first'
            : 'Start outing');
    final quickSnapshot = _snapshotMap(_snapshot['quickLists']);
    final quickListRows = _snapshotList(quickSnapshot['lists']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WidgetSectionTitle(),
        const SizedBox(height: 9),
        SurfaceCard(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A little closer to the door.',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Both widgets start at 2×2. Resize for more items or lists.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.appColors.muted),
              ),
              const SizedBox(height: 14),
              _PreviewFrame(
                title: 'Checklist widget',
                semanticsLabel: 'Flutter preview of the checklist widget',
                palette: widgetColors,
                child: _ChecklistPreview(
                  title: title,
                  progress: progress,
                  checked: checked,
                  total: total,
                  items: items,
                  actionLabel: actionLabel,
                  visibleRows: _checklistRowsForPreview(context),
                  palette: widgetColors,
                ),
              ),
              const SizedBox(height: 12),
              _PreviewFrame(
                title: 'Quick lists widget',
                semanticsLabel: 'Flutter preview of the quick lists widget',
                palette: widgetColors,
                child: _QuickListsPreview(
                  blueprints: state.blueprints.take(4).toList(),
                  activeOutings: active,
                  snapshotRows: quickListRows,
                  visibleRows: _quickListRowsForPreview(context),
                  palette: widgetColors,
                ),
              ),
              const SizedBox(height: 13),
              if (_snapshot['pinSupported'] == true)
                _PinButtons(
                  busy: _pinning,
                  onChecklist: () => _requestPin('checklist'),
                  onQuickLists: () => _requestPin('quick_lists'),
                )
              else
                _LauncherInstructions(),
              const SizedBox(height: 8),
              Text(
                'Widget previews · Layout adapts to your launcher.',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: context.appColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Map<String, Object?> _snapshotPart(Map<String, Object?> snapshot, String key) {
  return _snapshotMap(snapshot[key]).isNotEmpty
      ? _snapshotMap(snapshot[key])
      : snapshot;
}

Map<String, Object?> _snapshotMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const <String, Object?>{};

List<Map<String, Object?>> _snapshotList(Object? value) => value is List
    ? value.whereType<Map>().map(Map<String, Object?>.from).toList()
    : const <Map<String, Object?>>[];

class _PinButtons extends StatelessWidget {
  const _PinButtons({
    required this.busy,
    required this.onChecklist,
    required this.onQuickLists,
  });

  final bool busy;
  final VoidCallback onChecklist;
  final VoidCallback onQuickLists;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: busy ? null : onChecklist,
        icon: const Icon(Icons.checklist_rounded),
        label: const Text('Add checklist widget'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: busy ? null : onQuickLists,
        icon: const Icon(Icons.widgets_outlined),
        label: const Text('Add quick lists widget'),
      ),
    ],
  );
}

class _LauncherInstructions extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.appColors.surfaceRaised,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.touch_app_outlined,
          color: context.appColors.muted,
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Add a Ready Yet? widget from your launcher’s Widgets picker, then choose the lists it should show.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _WidgetSectionTitle extends StatelessWidget {
  const _WidgetSectionTitle();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Icon(
          Icons.widgets_outlined,
          size: 19,
          color: context.appColors.muted,
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          'Home-screen widgets',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _WidgetPreviewColors {
  const _WidgetPreviewColors({
    required this.surface,
    required this.border,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.actionInk,
    required this.rowSurface,
    required this.rowBorder,
    required this.track,
    required this.bagChip,
  });

  final Color surface;
  final Color border;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color actionInk;
  final Color rowSurface;
  final Color rowBorder;
  final Color track;
  final Color bagChip;

  static _WidgetPreviewColors forContext(BuildContext context) {
    if (MediaQuery.platformBrightnessOf(context) == Brightness.dark) {
      return const _WidgetPreviewColors(
        surface: Color(0xFF222920),
        border: Color(0xFF414D3D),
        ink: Color(0xFFF3F1E8),
        muted: Color(0xFFC1C6B9),
        accent: Color(0xFFD7F25B),
        actionInk: Color(0xFF20241E),
        rowSurface: Color(0xFF2B342A),
        rowBorder: Color(0xFF414D3D),
        track: Color(0xFF414D3D),
        bagChip: Color(0xFFF3F1E8),
      );
    }
    return const _WidgetPreviewColors(
      surface: Color(0xFF283329),
      border: Color(0xFF465444),
      ink: Color(0xFFF5F2EA),
      muted: Color(0xFFC5CFBE),
      accent: Color(0xFFD7F25B),
      actionInk: Color(0xFF20241E),
      rowSurface: Color(0xFF333F34),
      rowBorder: Color(0xFF4A5A48),
      track: Color(0xFF4A5A48),
      bagChip: Color(0xFFF5F2EA),
    );
  }
}

double _previewFontScale(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(.85, 3.0);

int _checklistRowsForPreview(BuildContext context) {
  final scale = _previewFontScale(context);
  final fullBaseHeight =
      8 +
      math.max(26, (27 * scale).ceil()) +
      4 +
      math.max(24, (19 * scale).ceil()) +
      6 +
      3 +
      48 +
      3;
  final compactBrand = math.max(24, (14 * scale).ceil());
  final compactTitle = math.max(24, (16 * scale).ceil());
  final compactBaseHeight = 4 + compactBrand + 1 + compactTitle + 1 + 1 + 48;
  final rowPitch = math.max(50, (18 * scale).ceil() + 2);
  final fullRows = ((275 - fullBaseHeight) ~/ rowPitch).clamp(0, 5);
  final compactRows = ((275 - compactBaseHeight) ~/ rowPitch).clamp(0, 5);
  return math.max(fullRows, compactRows).toInt();
}

int _quickListRowsForPreview(BuildContext context) {
  final scale = _previewFontScale(context);
  final fullBaseHeight = 12 + math.max(26, (27 * scale).ceil()) + 2 + 1 + 48;
  final compactBaseHeight = 8 + math.max(24, (12 * scale).ceil()) + 1 + 1 + 48;
  final rowPitch = math.max(48, (30 * scale).ceil());
  final fullRows = ((275 - fullBaseHeight) ~/ rowPitch).clamp(0, 4);
  final compactRows = ((275 - compactBaseHeight) ~/ rowPitch).clamp(0, 4);
  return math.max(fullRows, compactRows).toInt();
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.title,
    required this.semanticsLabel,
    required this.palette,
    required this.child,
  });

  final String title;
  final String semanticsLabel;
  final _WidgetPreviewColors palette;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$semanticsLabel, not interactive',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Eyebrow(title, color: context.appColors.muted)),
              Text(
                'PREVIEW',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.appColors.muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.border),
            ),
            child: child,
          ),
        ],
      ),
    ),
  );
}

class _WidgetBrandHeader extends StatelessWidget {
  const _WidgetBrandHeader({required this.palette});

  final _WidgetPreviewColors palette;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: palette.bagChip,
          borderRadius: BorderRadius.circular(9),
        ),
        child: CustomPaint(
          size: const Size.square(20),
          painter: _BagMarkPainter(palette),
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ready Yet?',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            Text(
              'Before I Leave',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontSize: 9,
                letterSpacing: .2,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({
    required this.title,
    required this.progress,
    required this.checked,
    required this.total,
    required this.items,
    required this.actionLabel,
    required this.visibleRows,
    required this.palette,
  });

  final String title;
  final String progress;
  final int checked;
  final int total;
  final List<({String label, bool checked})> items;
  final String actionLabel;
  final int visibleRows;
  final _WidgetPreviewColors palette;

  @override
  Widget build(BuildContext context) {
    final shownItems = items.take(visibleRows).toList();
    final overflow = (total - shownItems.length).clamp(0, total);
    final action = overflow > 0
        ? '$actionLabel · +$overflow more'
        : actionLabel;
    final progressValue = total <= 0 ? 0.0 : (checked / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetBrandHeader(palette: palette),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF5F2EA),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ).copyWith(color: palette.ink),
              ),
            ),
            const SizedBox(width: 7),
            _WidgetBadge(text: progress, palette: palette, minWidth: 0),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 3),
          _WidgetProgressTrack(value: progressValue, palette: palette),
        ],
        if (shownItems.isNotEmpty) ...[
          const SizedBox(height: 3),
          for (final item in shownItems)
            _ChecklistPreviewRow(item: item, palette: palette),
        ],
        const SizedBox(height: 3),
        _WidgetActionButton(
          label: action,
          palette: palette,
          height: 48,
          fontSize: 13,
        ),
      ],
    );
  }
}

class _ChecklistPreviewRow extends StatelessWidget {
  const _ChecklistPreviewRow({required this.item, required this.palette});

  final ({String label, bool checked}) item;
  final _WidgetPreviewColors palette;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: palette.rowSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.rowBorder),
    ),
    child: Row(
      children: [
        _WidgetCheckMark(checked: item.checked, palette: palette),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.ink, fontSize: 14, height: 1.2),
          ),
        ),
      ],
    ),
  );
}

class _WidgetCheckMark extends StatelessWidget {
  const _WidgetCheckMark({required this.checked, required this.palette});

  final bool checked;
  final _WidgetPreviewColors palette;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: checked ? palette.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      border: checked ? null : Border.all(color: palette.muted, width: 1.5),
    ),
    child: checked
        ? Icon(Icons.check_rounded, size: 16, color: palette.actionInk)
        : null,
  );
}

class _WidgetProgressTrack extends StatelessWidget {
  const _WidgetProgressTrack({required this.value, required this.palette});

  final double value;
  final _WidgetPreviewColors palette;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: palette.track)),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: constraints.maxWidth * value,
                child: ColoredBox(color: palette.accent),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WidgetBadge extends StatelessWidget {
  const _WidgetBadge({
    required this.text,
    required this.palette,
    required this.minWidth,
  });

  final String text;
  final _WidgetPreviewColors palette;
  final double minWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: minWidth,
      minHeight: 24,
      maxWidth: 145,
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.actionInk,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.05,
        ),
      ),
    ),
  );
}

class _WidgetActionButton extends StatelessWidget {
  const _WidgetActionButton({
    required this.label,
    required this.palette,
    required this.height,
    required this.fontSize,
  });

  final String label;
  final _WidgetPreviewColors palette;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: BoxConstraints(minHeight: height),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: palette.accent,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: palette.actionInk,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
    ),
  );
}

class _BagMarkPainter extends CustomPainter {
  const _BagMarkPainter(this.palette);

  final _WidgetPreviewColors palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final handle = Paint()
      ..color = palette.actionInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    final handlePath = Path()
      ..moveTo(8, 9)
      ..cubicTo(8, 5.5, 9.4, 4, 12, 4)
      ..cubicTo(14.6, 4, 16, 5.5, 16, 9);
    canvas.drawPath(handlePath, handle);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTRB(4, 8, 20, 20.5),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(body, Paint()..color = palette.actionInk);
    canvas.drawRect(
      const Rect.fromLTRB(6.5, 10, 17.5, 18.5),
      Paint()..color = palette.accent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(9, 11.5, 15, 15.8),
        const Radius.circular(1),
      ),
      Paint()..color = palette.bagChip,
    );
    final tick = Path()
      ..moveTo(10, 13.6)
      ..lineTo(11.1, 14.6)
      ..lineTo(13.8, 12.4);
    canvas.drawPath(
      tick,
      Paint()
        ..color = palette.actionInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BagMarkPainter oldDelegate) =>
      oldDelegate.palette.ink != palette.ink ||
      oldDelegate.palette.accent != palette.accent ||
      oldDelegate.palette.actionInk != palette.actionInk ||
      oldDelegate.palette.bagChip != palette.bagChip;
}

class _QuickListsPreview extends StatelessWidget {
  const _QuickListsPreview({
    required this.blueprints,
    required this.activeOutings,
    required this.snapshotRows,
    required this.visibleRows,
    required this.palette,
  });

  final List<Blueprint> blueprints;
  final List<Outing> activeOutings;
  final List<Map<String, Object?>> snapshotRows;
  final int visibleRows;
  final _WidgetPreviewColors palette;

  @override
  Widget build(BuildContext context) {
    final count = snapshotRows.isNotEmpty
        ? snapshotRows.length
        : blueprints.length;
    final overflow = (count - visibleRows).clamp(0, count);
    final action = overflow > 0
        ? 'Manage quick lists · +$overflow more'
        : 'Manage quick lists';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetBrandHeader(palette: palette),
        const SizedBox(height: 2),
        if (snapshotRows.isNotEmpty)
          for (final row in snapshotRows.take(visibleRows))
            _QuickListPreviewRow.fromSnapshot(row: row, palette: palette)
        else
          for (final blueprint in blueprints.take(visibleRows))
            _QuickListPreviewRow.fromState(
              blueprint: blueprint,
              outing: activeOutings
                  .where((outing) => outing.blueprintId == blueprint.id)
                  .firstOrNull,
              palette: palette,
            ),
        const SizedBox(height: 2),
        _WidgetActionButton(
          label: action,
          palette: palette,
          height: 48,
          fontSize: 12,
        ),
      ],
    );
  }
}

class _QuickListPreviewRow extends StatelessWidget {
  const _QuickListPreviewRow({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.palette,
  });

  factory _QuickListPreviewRow.fromSnapshot({
    required Map<String, Object?> row,
    required _WidgetPreviewColors palette,
  }) {
    final hasActive = row['hasActive'] == true;
    final total = row['total'] is int ? row['total'] as int : 0;
    final checked = row['checked'] is int ? row['checked'] as int : 0;
    final badge = hasActive && total > 0
        ? '$checked/$total'
        : total > 0
        ? 'READY'
        : 'EMPTY';
    return _QuickListPreviewRow(
      title: row['title']?.toString() ?? 'List',
      subtitle: row['subtitle']?.toString() ?? 'Open list',
      badge: badge,
      palette: palette,
    );
  }

  factory _QuickListPreviewRow.fromState({
    required Blueprint blueprint,
    required Outing? outing,
    required _WidgetPreviewColors palette,
  }) {
    final total = outing?.items.length ?? blueprint.items.length;
    final checked = outing?.checkedCount ?? 0;
    return _QuickListPreviewRow(
      title: blueprint.name,
      subtitle: outing != null
          ? '$checked of $total packed'
          : blueprint.items.isEmpty
          ? 'Add items in app'
          : '$total items ready',
      badge: outing != null && total > 0
          ? '$checked/$total'
          : total > 0
          ? 'READY'
          : 'EMPTY',
      palette: palette,
    );
  }

  final String title;
  final String subtitle;
  final String badge;
  final _WidgetPreviewColors palette;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: palette.rowSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.rowBorder),
    ),
    child: Row(
      children: [
        _BagChip(palette: palette),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _WidgetBadge(text: badge, palette: palette, minWidth: 42),
      ],
    ),
  );
}

class _BagChip extends StatelessWidget {
  const _BagChip({required this.palette});

  final _WidgetPreviewColors palette;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: palette.bagChip,
      borderRadius: BorderRadius.circular(9),
    ),
    child: CustomPaint(
      size: const Size.square(20),
      painter: _BagMarkPainter(palette),
    ),
  );
}
