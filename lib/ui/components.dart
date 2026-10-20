import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../app/theme.dart';

const iconChoices = <String, IconData>{
  'wallet': Icons.account_balance_wallet_outlined,
  'key': Icons.key_outlined,
  'keys': Icons.key_outlined,
  'phone': Icons.smartphone_rounded,
  'water': Icons.water_drop_outlined,
  'lunch': Icons.lunch_dining_outlined,
  'book': Icons.menu_book_outlined,
  'notebook': Icons.book_outlined,
  'pen': Icons.edit_outlined,
  'laptop': Icons.laptop_mac_rounded,
  'briefcase': Icons.work_outline_rounded,
  'badge': Icons.badge_outlined,
  'dumbbell': Icons.fitness_center_rounded,
  'shoe': Icons.directions_run_rounded,
  'shoes': Icons.directions_run_rounded,
  'towel': Icons.dry_cleaning_outlined,
  'suitcase': Icons.luggage_outlined,
  'headphones': Icons.headphones_rounded,
  'clothes': Icons.checkroom_outlined,
  'medicine': Icons.medication_outlined,
  'charger': Icons.bolt_rounded,
  'bag': Icons.backpack_outlined,
  'umbrella': Icons.umbrella_outlined,
  'ticket': Icons.confirmation_number_outlined,
  'passport': Icons.travel_explore_outlined,
  'glasses': Icons.visibility_outlined,
  'sanitizer': Icons.sanitizer_outlined,
  'soap': Icons.soap_outlined,
  // ItemGlyph paints this key as a perfume bottle. Keep an icon fallback for
  // callers that only understand Material IconData.
  'perfume': Icons.spa_outlined,
  'other': Icons.circle_outlined,
  'spark': Icons.auto_awesome_outlined,
};

/// The icons shown when adding or editing a checklist item.
///
/// Historical keys such as `keys`, `shoes`, and `spark` remain in
/// [iconChoices] for saved data, but aliases are not offered twice.
const iconChoiceKeys = <String>[
  'bag',
  'wallet',
  'key',
  'phone',
  'badge',
  'laptop',
  'briefcase',
  'charger',
  'water',
  'lunch',
  'book',
  'notebook',
  'pen',
  'headphones',
  'glasses',
  'clothes',
  'towel',
  'medicine',
  'soap',
  'sanitizer',
  'perfume',
  'suitcase',
  'ticket',
  'passport',
  'umbrella',
  'other',
];

String iconLabel(String key) {
  const labels = <String, String>{
    'wallet': 'Wallet',
    'key': 'Key',
    'keys': 'Keys',
    'phone': 'Phone',
    'water': 'Water bottle',
    'lunch': 'Lunch',
    'book': 'Book',
    'notebook': 'Notebook',
    'pen': 'Pen',
    'laptop': 'Laptop',
    'briefcase': 'Briefcase',
    'badge': 'ID card',
    'dumbbell': 'Workout gear',
    'shoe': 'Shoes',
    'shoes': 'Shoes',
    'towel': 'Towel',
    'suitcase': 'Suitcase',
    'headphones': 'Headphones',
    'clothes': 'Clothes',
    'medicine': 'Medicine',
    'charger': 'Charger',
    'bag': 'Bag',
    'umbrella': 'Umbrella',
    'ticket': 'Ticket',
    'passport': 'Passport',
    'glasses': 'Glasses',
    'sanitizer': 'Hand sanitizer',
    'soap': 'Soap',
    'perfume': 'Perfume',
    'other': 'Other',
    'spark': 'Special item',
  };
  final known = labels[key];
  if (known != null) return known;

  final words = key
      .trim()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'));
  final readable = words
      .where((word) => word.isNotEmpty)
      .take(4)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
  return readable.isEmpty ? 'Other' : readable;
}

IconData iconFor(String key) => iconChoices[key] ?? Icons.circle_outlined;

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color ?? context.appColors.muted,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w800,
      fontSize: 10,
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: color ?? context.appColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: context.appColors.line.withValues(alpha: .72)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.accentInk,
          disabledBackgroundColor: colors.surfaceRaised,
          disabledForegroundColor: colors.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class SaveErrorBanner extends StatelessWidget {
  const SaveErrorBanner({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.peach,
      child: Semantics(
        button: true,
        label: 'Couldn’t save changes. Tap to retry.',
        onTap: onRetry,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onRetry,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 19, color: colors.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Couldn’t save changes. Tap to retry.',
                        style: TextStyle(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.refresh_rounded, size: 19, color: colors.ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    this.icon,
    this.iconKey,
    required this.color,
    this.size = 48,
  }) : assert(icon != null || iconKey != null);
  final IconData? icon;
  final String? iconKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = color == colors.accent ? colors.accentInk : colors.ink;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: iconKey == null
          ? Icon(icon!, color: foreground, size: size * .48)
          : ItemGlyph(iconKey: iconKey!, color: foreground, size: size * .48),
    );
  }
}

class ItemGlyph extends StatelessWidget {
  const ItemGlyph({
    super.key,
    required this.iconKey,
    required this.color,
    this.size = 24,
  });

  final String iconKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => iconKey == 'perfume'
      ? Center(
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(painter: _PerfumeBottlePainter(color)),
          ),
        )
      : Icon(iconFor(iconKey), color: color, size: size);
}

class _PerfumeBottlePainter extends CustomPainter {
  const _PerfumeBottlePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.translate(
      (size.width - size.shortestSide) / 2,
      (size.height - size.shortestSide) / 2,
    );
    canvas.scale(scale);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bottle = Path()
      ..moveTo(7, 9)
      ..lineTo(9, 7.5)
      ..lineTo(15, 7.5)
      ..lineTo(17, 9)
      ..lineTo(18.5, 10.5)
      ..lineTo(18.5, 20)
      ..quadraticBezierTo(18.5, 22, 16.5, 22)
      ..lineTo(7.5, 22)
      ..quadraticBezierTo(5.5, 22, 5.5, 20)
      ..lineTo(5.5, 10.5)
      ..close();
    canvas.drawPath(bottle, outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(9.5, 4.5, 14.5, 7.5),
        const Radius.circular(0.8),
      ),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(8.5, 1.8, 15.5, 4.5),
        const Radius.circular(0.8),
      ),
      outline,
    );
    canvas.drawLine(const Offset(12, 1.8), const Offset(12, 0.6), outline);
    canvas.drawLine(const Offset(12, 0.6), const Offset(15.3, 0.6), outline);
    canvas.drawLine(const Offset(15.3, 0.6), const Offset(16, 1.5), outline);
    canvas.drawLine(const Offset(8, 13), const Offset(16, 13), outline);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PerfumeBottlePainter oldDelegate) =>
      oldDelegate.color != color;
}

class BagTray extends StatefulWidget {
  const BagTray({
    super.key,
    required this.checked,
    required this.total,
    this.compact = false,
    this.sealed = false,
  });
  final int checked;
  final int total;
  final bool compact;
  final bool sealed;

  @override
  State<BagTray> createState() => _BagTrayState();
}

class _BagTrayState extends State<BagTray> with TickerProviderStateMixin {
  static const _packingSpring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 30,
  );
  static const _sealDuration = Duration(milliseconds: 360);

  late final AnimationController _packing = AnimationController(vsync: this);
  late final AnimationController _sealing = AnimationController(
    vsync: this,
    duration: _sealDuration,
  );
  bool _initialized = false;
  bool _reducedMotion = false;
  int _motionGeneration = 0;

  double get _targetProgress =>
      widget.total == 0 ? 0 : (widget.checked / widget.total).clamp(0.0, 1.0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (!_initialized) {
      _initialized = true;
      _reducedMotion = reducedMotion;
      _packing.value = _targetProgress;
      _sealing.value = widget.sealed ? 1 : 0;
      return;
    }
    if (_reducedMotion != reducedMotion) {
      _reducedMotion = reducedMotion;
      if (reducedMotion) {
        ++_motionGeneration;
        _packing.stop();
        _sealing.stop();
        _packing.value = _targetProgress;
        _sealing.value = widget.sealed ? 1 : 0;
      }
    }
  }

  @override
  void didUpdateWidget(covariant BagTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checked != widget.checked ||
        oldWidget.total != widget.total ||
        oldWidget.sealed != widget.sealed) {
      _animateToTargets();
    }
  }

  void _animateToTargets() {
    final generation = ++_motionGeneration;
    final target = _targetProgress;
    if (_reducedMotion) {
      _packing.value = target;
      _sealing.value = widget.sealed ? 1 : 0;
      return;
    }

    final packing = _packing.animateWith(
      SpringSimulation(
        _packingSpring,
        _packing.value,
        target,
        _packing.velocity,
      ),
    );

    if (!widget.sealed) {
      if (_sealing.value == 0 && !_sealing.isAnimating) return;
      _sealing.animateBack(
        0,
        duration: _sealDuration,
        curve: Curves.easeOutCubic,
      );
      return;
    }

    unawaited(_sealAfterPacking(packing, generation));
  }

  Future<void> _sealAfterPacking(TickerFuture packing, int generation) async {
    try {
      await packing.orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _motionGeneration || !widget.sealed) return;
    try {
      await _sealing
          .animateTo(1, duration: _sealDuration, curve: Curves.easeInOutCubic)
          .orCancel;
    } on TickerCanceled {
      // A rapid reverse or route removal cancels the remaining motion.
    }
  }

  @override
  void dispose() {
    _packing.dispose();
    _sealing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final complete = widget.total > 0 && widget.checked >= widget.total;
    final height = widget.compact ? 142.0 : 188.0;
    return Semantics(
      image: true,
      label: widget.total == 0
          ? 'An empty illustrated packing bag'
          : '${widget.checked} of ${widget.total} items packed${complete ? ', all items checked' : ''}${widget.sealed ? ', outing finished' : ''}',
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: AnimatedBuilder(
          animation: Listenable.merge([_packing, _sealing]),
          builder: (context, _) => CustomPaint(
            painter: _BagPainter(
              colors: context.appColors,
              progress: _packing.value,
              complete: complete,
              closeProgress: _sealing.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _BagPainter extends CustomPainter {
  _BagPainter({
    required this.colors,
    required this.progress,
    required this.complete,
    required this.closeProgress,
  });
  final AppColors colors;
  final double progress;
  final bool complete;
  final double closeProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * .55;
    final scale = math.min(size.height / 188, size.width / 310);
    final contentsOpacity =
        1 - Curves.easeInCubic.transform(closeProgress.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);
    final shadowPaint = Paint()
      ..color = colors.ink.withValues(alpha: colors.isDark ? .16 : .08);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 53), width: 176, height: 21),
      shadowPaint,
    );

    final outline = Paint()
      ..color = colors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = colors.surfaceRaised;
    final bag = Path()
      ..moveTo(-59, -23)
      ..quadraticBezierTo(-67, -18, -67, -5)
      ..lineTo(-57, 42)
      ..quadraticBezierTo(-54, 51, -44, 51)
      ..lineTo(44, 51)
      ..quadraticBezierTo(54, 51, 57, 42)
      ..lineTo(67, -5)
      ..quadraticBezierTo(67, -18, 59, -23)
      ..close();
    canvas.drawPath(bag, fill);
    canvas.drawPath(bag, outline);
    // Essentials start loose on the tray and settle into the open bag as the
    // checklist progresses. The original bag and pocket remain the focus.
    final colorsList = [
      colors.sky,
      colors.lilac,
      colors.peach,
      colors.accent,
      colors.sky,
    ];
    for (var i = 0; i < 5; i++) {
      final packed = ((progress * 5 - i).clamp(0.0, 1.0));
      final x0 = (i - 2) * 39.0;
      final y0 = -39.0 + (i.isEven ? 0 : 6.0);
      final x1 = (i - 2) * 18.0;
      final y1 = -12.0;
      final t = Curves.easeOutCubic.transform(packed);
      final x = x0 + (x1 - x0) * t;
      final y = y0 + (y1 - y0) * t;
      final paint = Paint()
        ..color = colorsList[i].withValues(alpha: contentsOpacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((i - 2) * .12 * (1 - t));
      switch (i) {
        case 0:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-10, -13, 20, 27),
              const Radius.circular(5),
            ),
            paint,
          );
          break;
        case 1:
          canvas.drawCircle(const Offset(0, 0), 11, paint);
          canvas.drawCircle(
            const Offset(0, 0),
            5,
            Paint()..color = colors.canvas.withValues(alpha: contentsOpacity),
          );
          break;
        case 2:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-13, -10, 26, 20),
              const Radius.circular(5),
            ),
            paint,
          );
          break;
        case 3:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-7, -14, 14, 28),
              const Radius.circular(7),
            ),
            paint,
          );
          break;
        default:
          canvas.drawCircle(const Offset(0, 0), 10, paint);
          canvas.drawLine(
            const Offset(-6, 2),
            const Offset(6, 2),
            Paint()
              ..color = colors.ink.withValues(alpha: .7 * contentsOpacity)
              ..strokeWidth = 2,
          );
          break;
      }
      canvas.restore();
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-38, -10, 76, 43),
        const Radius.circular(12),
      ),
      Paint()
        ..color = colors.isDark
            ? const Color(0xFF23342C)
            : const Color(0xFFDEE8CE),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-38, -10, 76, 43),
        const Radius.circular(12),
      ),
      Paint()
        ..color = colors.ink.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final handle = Path()
      ..moveTo(-28, -22)
      ..cubicTo(-26, -49, -15, -60, 0, -60)
      ..cubicTo(15, -60, 26, -49, 28, -22);
    final handleBg = Paint()
      ..color = colors.canvas
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(handle, handleBg);
    canvas.drawPath(handle, outline);

    if (closeProgress > 0) {
      final flap = Path()
        ..moveTo(-49, -22)
        // At zero the flap collapses onto the existing mouth seam. Its area
        // and paint opacity then grow together, so the first seal frame has
        // no full-size jump.
        ..quadraticBezierTo(0, -22 + closeProgress * 5, 49, -22)
        ..lineTo(40, -22 + closeProgress * 21)
        ..quadraticBezierTo(
          0,
          -22 + closeProgress * 30,
          -40,
          -22 + closeProgress * 21,
        )
        ..close();
      final flapOpacity = closeProgress.clamp(0.0, 1.0);
      canvas.drawPath(
        flap,
        Paint()
          ..color = Color.lerp(
            colors.surfaceRaised,
            colors.accent,
            closeProgress * .4,
          )!.withValues(alpha: flapOpacity),
      );
      canvas.drawPath(
        flap,
        Paint()
          ..color = colors.ink.withValues(alpha: .68 * flapOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final clasp = Paint()
      ..color = Color.lerp(colors.ink, colors.accent, closeProgress)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, 8), width: 20, height: 19),
        const Radius.circular(6),
      ),
      clasp,
    );
    if (closeProgress > .8) {
      final checkPaint = Paint()
        ..color = colors.accentInk.withValues(
          alpha: ((closeProgress - .8) / .2).clamp(0.0, 1.0),
        )
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final check = Path()
        ..moveTo(-4, 8)
        ..lineTo(-1, 11)
        ..lineTo(5, 5);
      canvas.drawPath(check, checkPaint);
    } else {
      canvas.drawCircle(
        const Offset(0, 8),
        2.4,
        Paint()..color = colors.accent,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BagPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.progress != progress ||
      oldDelegate.complete != complete ||
      oldDelegate.closeProgress != closeProgress;
}

class ChecklistRow extends StatelessWidget {
  const ChecklistRow({
    super.key,
    required this.label,
    required this.icon,
    required this.checked,
    required this.onToggle,
    this.onMore,
    this.trailing,
  });
  final String label;
  final String icon;
  final bool checked;
  final VoidCallback onToggle;
  final VoidCallback? onMore;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            button: true,
            checked: checked,
            label: label,
            onTap: onToggle,
            child: ExcludeSemantics(
              child: Material(
                color: colors.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onToggle,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          IconTile(
                            iconKey: icon,
                            color: checked
                                ? colors.accent
                                : colors.surfaceRaised,
                            size: 44,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 180),
                              style: theme.textTheme.titleMedium!.copyWith(
                                color: checked ? colors.muted : colors.ink,
                                decoration: checked
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                decorationColor: colors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                              child: Text(label, softWrap: true),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: checked
                                      ? colors.accent
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: checked
                                        ? colors.accent
                                        : colors.muted,
                                    width: 2,
                                  ),
                                ),
                                child: checked
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 20,
                                        color: colors.accentInk,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ?trailing,
        if (onMore != null)
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              onPressed: onMore,
              tooltip: 'More options for $label',
              icon: const Icon(Icons.more_horiz_rounded),
              color: colors.muted,
            ),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });
  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTile(icon: icon, color: context.appColors.lilac, size: 62),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
