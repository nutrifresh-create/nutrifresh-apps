import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/nf_theme.dart';
import '../utils/nf_formatters.dart';

/// Tombol/Kartu dengan efek tekan membal halus (micro-interaction ala iOS / POS modern)
class NfPressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;

  const NfPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.965,
    this.borderRadius,
  });

  @override
  State<NfPressScale> createState() => _NfPressScaleState();
}

class _NfPressScaleState extends State<NfPressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap?.call();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Angka Rupiah dengan animasi transisi mulus (smooth rolling counter)
class NfAnimatedRupiah extends StatelessWidget {
  final num value;
  final TextStyle? style;

  const NfAnimatedRupiah({
    super.key,
    required this.value,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(NfFormatters.rupiah(v), style: style),
    );
  }
}

/// Latar belakang utama:
/// - Mode Liquid Glass: Soft Botanical Mesh + 4 aura warna lembut agar efek blur kaca hidup
/// - Mode Natural: Latar solid bersih #F4F7F5 (super ringan tanpa blur)
class NfAmbientBackdrop extends StatelessWidget {
  final NfUiStyle style;
  final Widget child;

  const NfAmbientBackdrop({
    super.key,
    required this.style,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (style == NfUiStyle.natural) {
      return Container(
        color: const Color(0xFFF3F6F4),
        child: child,
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFDFEDE4),
            Color(0xFFECF5EF),
            Color(0xFFF5EFE2),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -90,
            left: -70,
            child: _glowOrb(290, const Color(0xFF4ADE80).withAlpha(82)),
          ),
          Positioned(
            top: -50,
            right: -80,
            child: _glowOrb(270, const Color(0xFFFACC15).withAlpha(66)),
          ),
          Positioned(
            bottom: -90,
            right: -50,
            child: _glowOrb(310, const Color(0xFF38BDF8).withAlpha(58)),
          ),
          Positioned(
            bottom: 90,
            left: -90,
            child: _glowOrb(260, const Color(0xFFFB923C).withAlpha(52)),
          ),
          child,
        ],
      ),
    );
  }

  Widget _glowOrb(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withAlpha(24),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Wadah Kaca Liquid Glass (BackdropFilter blur nyata) vs Kartu Solid Natural
class NfGlassSurface extends StatelessWidget {
  final NfUiStyle style;
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? tintColor;
  final Color? borderColor;
  final double blurSigma;
  final bool elevated;

  const NfGlassSurface({
    super.key,
    required this.style,
    required this.child,
    this.borderRadius = 24,
    this.padding,
    this.margin,
    this.tintColor,
    this.borderColor,
    this.blurSigma = 18,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    if (style == NfUiStyle.natural) {
      return Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: tintColor ?? Colors.white,
          borderRadius: radius,
          border: Border.all(color: borderColor ?? const Color(0xFFE2E8F0)),
          boxShadow: elevated
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withAlpha(11),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: child,
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: const Color(0xFF0F172A).withAlpha(22),
                  blurRadius: 22,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tintColor != null
                    ? [tintColor!.withAlpha(225), tintColor!.withAlpha(185)]
                    : [
                        Colors.white.withAlpha(212),
                        const Color(0xFFF6FBF8).withAlpha(178),
                      ],
              ),
              border: Border.all(
                color: borderColor ?? Colors.white.withAlpha(232),
                width: 1.25,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Logo resmi NutriFresh tertanam 100% lokal (assets/images/logo.png — tampil instan walau offline!)
class NfBrandLogoPill extends StatelessWidget {
  final double height;
  final bool compact;

  const NfBrandLogoPill({
    super.key,
    this.height = 38,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(245),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9EBD0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withAlpha(14),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/logo.png',
        height: height - 10,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_rounded, color: NfColors.greenDark, size: 18),
            SizedBox(width: 4),
            Text('NutriFresh', style: TextStyle(fontWeight: FontWeight.w900, color: NfColors.brown, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Modal / Bottom-Sheet Liquid Glass ala iOS 26 dengan transisi smooth spring (scale+fade di PC, slide sheet di HP)
Future<T?> showNfGlassModal<T>({
  required BuildContext context,
  required NfUiStyle style,
  required String title,
  String? subtitle,
  IconData? icon,
  List<Color>? headerGradient,
  double maxWidth = 480,
  required Widget Function(BuildContext modalContext) builder,
}) {
  final isWide = MediaQuery.of(context).size.width >= 640;
  final isGlass = style == NfUiStyle.glass;

  Widget buildShell(BuildContext ctx, bool asSheet) {
    final radius = asSheet
        ? const BorderRadius.vertical(top: Radius.circular(30))
        : BorderRadius.circular(28);
    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (asSheet)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 42,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          decoration: BoxDecoration(
            gradient: headerGradient != null ? LinearGradient(colors: headerGradient) : null,
            color: headerGradient == null ? Colors.white.withAlpha(isGlass ? 165 : 255) : null,
            border: Border(
              bottom: BorderSide(
                color: headerGradient != null
                    ? Colors.white.withAlpha(60)
                    : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: headerGradient != null ? Colors.white.withAlpha(55) : NfColors.lightBg,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: headerGradient != null ? Colors.white : NfColors.greenDark,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: headerGradient != null ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: headerGradient != null
                              ? Colors.white.withAlpha(220)
                              : const Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: headerGradient != null ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              18,
              14,
              18,
              18 + (asSheet ? MediaQuery.of(ctx).viewInsets.bottom : 0),
            ),
            child: builder(ctx),
          ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isGlass ? 26 : 0,
          sigmaY: isGlass ? 26 : 0,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: asSheet ? double.infinity : maxWidth,
            maxHeight: MediaQuery.of(ctx).size.height * (asSheet ? 0.91 : 0.88),
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: isGlass ? const Color(0xFFF6FBF8).withAlpha(235) : const Color(0xFFF8FAFC),
            border: Border.all(
              color: isGlass ? Colors.white.withAlpha(240) : const Color(0xFFE2E8F0),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withAlpha(65),
                blurRadius: 36,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: inner,
        ),
      ),
    );
  }

  if (!isWide) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF0F172A).withAlpha(125),
      builder: (ctx) => buildShell(ctx, true),
    );
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: const Color(0xFF0F172A).withAlpha(125),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, _, __) => Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: buildShell(ctx, false),
        ),
      ),
    ),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Kontrol Tab Kapsul Geser (iOS Sliding Pill — halus & tanpa centang Material 3!)
class NfSlidingSegmented<T> extends StatelessWidget {
  final NfUiStyle style;
  final List<(T, String, IconData?)> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool greenActive;

  const NfSlidingSegmented({
    super.key,
    required this.style,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.greenActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeIndex = items.indexWhere((e) => e.$1 == selected).clamp(0, items.length - 1).toInt();
    final isGlass = style == NfUiStyle.glass;

    final track = Container(
      height: 42,
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: isGlass ? const Color(0xFFE4EFE9).withAlpha(182) : const Color(0xFFEDF2EE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isGlass ? Colors.white.withAlpha(225) : const Color(0xFFDCE5DF),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segW = constraints.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: segW * activeIndex,
                top: 0,
                bottom: 0,
                width: segW,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: greenActive
                        ? const LinearGradient(colors: [Color(0xFF8BC34A), Color(0xFF558B2F)])
                        : null,
                    color: greenActive ? null : Colors.white,
                    border: Border.all(
                      color: greenActive ? Colors.white.withAlpha(110) : Colors.white,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (greenActive ? NfColors.greenDark : const Color(0xFF0F172A))
                            .withAlpha(greenActive ? 65 : 24),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: items.map((entry) {
                  final isAct = entry.$1 == selected;
                  final fgColor = isAct
                      ? (greenActive ? Colors.white : NfColors.greenDark)
                      : const Color(0xFF475569);
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onChanged(entry.$1);
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (entry.$3 != null) ...[
                              Icon(entry.$3, size: 15, color: fgColor),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: Text(
                                entry.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isAct ? FontWeight.w900 : FontWeight.w700,
                                  color: fgColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );

    if (!isGlass) return track;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: track,
      ),
    );
  }
}

/// Item untuk Floating Liquid Glass Bottom Dock & Desktop Sidebar (berwarna khas per menu!)
class NfDockItem {
  final IconData icon;
  final String label;
  final Color activeColor;
  final Color softBg;
  final int badgeCount;

  const NfDockItem({
    required this.icon,
    required this.label,
    this.activeColor = NfColors.greenDark,
    this.softBg = const Color(0xFFECFCCB),
    this.badgeCount = 0,
  });
}

/// Dock Bawah Kapsul Melayang iOS 26 dengan Lensa Geser Berwarna Halus
class NfFloatingDock extends StatelessWidget {
  final NfUiStyle style;
  final List<NfDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const NfFloatingDock({
    super.key,
    required this.style,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isGlass = style == NfUiStyle.glass;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final currentAccent = items[selectedIndex].activeColor;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, safeBottom > 8 ? safeBottom : 10),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withAlpha(isGlass ? 45 : 32),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: isGlass ? 22 : 0,
              sigmaY: isGlass ? 22 : 0,
            ),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: isGlass ? const Color(0xFFEBF4EE).withAlpha(192) : Colors.white,
                border: Border.all(
                  color: isGlass ? Colors.white.withAlpha(232) : const Color(0xFFDBE4DE),
                  width: 1.25,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemW = constraints.maxWidth / items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        left: itemW * selectedIndex,
                        top: 0,
                        bottom: 0,
                        width: itemW,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: isGlass ? Colors.white.withAlpha(248) : items[selectedIndex].softBg,
                            border: Border.all(
                              color: currentAccent.withAlpha(80),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: currentAccent.withAlpha(48),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(items.length, (i) {
                          final item = items[i];
                          final active = i == selectedIndex;
                          return Expanded(
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onSelected(i);
                              },
                              borderRadius: BorderRadius.circular(999),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AnimatedScale(
                                        scale: active ? 1.12 : 1.0,
                                        duration: const Duration(milliseconds: 220),
                                        curve: Curves.easeOutBack,
                                        child: Icon(
                                          item.icon,
                                          size: 20,
                                          color: active ? item.activeColor : item.activeColor.withAlpha(175),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                                          color: active ? item.activeColor : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.badgeCount > 0)
                                    Positioned(
                                      top: 4,
                                      right: itemW * 0.14,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: NfColors.danger,
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: Colors.white, width: 1.2),
                                        ),
                                        child: Text(
                                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
