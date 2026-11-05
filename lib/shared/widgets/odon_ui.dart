import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:odon_booking/core/theme/app_theme.dart';

export 'package:odon_booking/core/theme/app_theme.dart';

/// Shared building blocks so every screen speaks the same visual language.
/// Prefer these over hand-rolled Containers with ad-hoc shadows and colours.

// ── Press feedback ──────────────────────────────────────────────────────────

/// Scales its child down the instant a pointer lands on it and springs back
/// on release, so a tap is acknowledged on press, not on lift.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final String? semanticLabel;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.semanticLabel,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduced = AppMotion.reduced(context);
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: Listener(
          onPointerDown: enabled ? (_) => _set(true) : null,
          onPointerUp: (_) => _set(false),
          onPointerCancel: (_) => _set(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onTapCancel: () => _set(false),
            child: AnimatedScale(
              scale: _down && !reduced ? widget.pressedScale : 1,
              // Quick in, softer out: the press lands immediately, the release settles.
              duration: _down ? const Duration(milliseconds: 90) : AppMotion.base,
              curve: AppMotion.ease,
              child: AnimatedOpacity(
                opacity: _down ? 0.88 : 1,
                duration: _down ? const Duration(milliseconds: 90) : AppMotion.base,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Containers ──────────────────────────────────────────────────────────────

/// The standard white card: hairline edge, soft lift, 16px corners.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;
  final bool shadow;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.margin,
    this.onTap,
    this.color = AppColors.surface,
    this.borderColor = AppColors.hairline,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.card,
        border: Border.all(color: borderColor),
        boxShadow: shadow ? AppShadow.card : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) card = Pressable(onTap: onTap, pressedScale: 0.985, child: card);
    return card;
  }
}

/// Centers content and caps its width so desktop layouts don't sprawl.
class PageBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.maxContent,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final g = AppLayout.gutter(context);
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: g),
          child: child,
        ),
      ),
    );
  }
}

// ── Headings ────────────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpace.md),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.headline),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppText.footnote),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Upper-case group label ("GROUND FLOOR").
class Eyebrow extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const Eyebrow(this.text,
      {super.key, this.padding = const EdgeInsets.only(bottom: AppSpace.sm)});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: Text(text.toUpperCase(), style: AppText.eyebrow));
}

// ── Small parts ─────────────────────────────────────────────────────────────

/// Icon in a soft rounded square. Monochrome unless a [color] carries meaning.
class IconWell extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  final Color? background;

  const IconWell(this.icon, {super.key, this.color, this.size = 40, this.background});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.ink;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? (color == null ? AppColors.sunken : AppColors.tint(c)),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: c, size: size * 0.5),
    );
  }
}

/// Compact status label. Colour encodes the state; text says it.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  const StatusPill(this.label,
      {super.key, this.color = AppColors.ink2, this.icon, this.solid = false});

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : AppColors.tint(color, 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppText.footnote.copyWith(
                fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.2),
          ),
        ),
      ]),
    );
  }
}

/// A coloured dot + label, used for legends.
class LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool outlined;
  const LegendDot(this.color, this.label, {super.key, this.outlined = false});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: outlined ? AppColors.surface : color,
            borderRadius: BorderRadius.circular(3),
            border: outlined ? Border.all(color: color, width: 1.2) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.footnote.copyWith(fontSize: 12, color: AppColors.ink2)),
      ]);
}

/// The hotel's seal, cropped to a circle.
class BrandSeal extends StatelessWidget {
  final double size;
  const BrandSeal({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset('assets/logo.JPG', fit: BoxFit.cover),
      );
}

// ── Metrics ─────────────────────────────────────────────────────────────────

class Metric {
  final String value;
  final String label;
  final String? caption;
  final Color? color;
  const Metric(this.value, this.label, {this.caption, this.color});
}

/// A row of figures in one card, split by hairlines. The value leads; the
/// label sits quietly underneath.
class MetricStrip extends StatelessWidget {
  final List<Metric> metrics;
  final Widget? footer;
  final double valueSize;

  const MetricStrip(this.metrics, {super.key, this.footer, this.valueSize = 28});

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var i = 0; i < metrics.length; i++) {
      final m = metrics[i];
      if (i > 0) {
        cells.add(Container(width: 1, color: AppColors.hairline,
            margin: const EdgeInsets.symmetric(vertical: 4)));
      }
      cells.add(Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : AppSpace.lg, right: AppSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.ease,
                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                child: FittedBox(
                  key: ValueKey(m.value),
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(m.value,
                      style: AppText.number(valueSize, color: m.color ?? AppColors.ink)),
                ),
              ),
              const SizedBox(height: 6),
              Text(m.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.footnote.copyWith(color: AppColors.ink2)),
              if (m.caption != null)
                Text(m.caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.footnote.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ));
    }
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.sm, AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)),
          if (footer != null) ...[
            const SizedBox(height: AppSpace.lg),
            Padding(padding: const EdgeInsets.only(right: AppSpace.sm), child: footer!),
          ],
        ],
      ),
    );
  }
}

/// A thin proportion bar (e.g. occupancy).
class ProportionBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;
  const ProportionBar(this.value,
      {super.key, this.color = AppColors.ink, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Container(color: AppColors.sunken),
          TweenAnimationBuilder<double>(
            tween: Tween(end: v),
            duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.slow,
            curve: AppMotion.ease,
            builder: (_, t, __) => FractionallySizedBox(
              widthFactor: t,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Segmented control ───────────────────────────────────────────────────────

/// Apple-style segmented control driven by a [TabController]: a sunken track
/// with a raised white thumb that follows the selection.
class SegmentedTabs extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  final List<IconData>? icons;

  const SegmentedTabs({
    super.key,
    required this.controller,
    required this.labels,
    this.icons,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(11),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [
            BoxShadow(color: Color(0x14121614), blurRadius: 4, offset: Offset(0, 1)),
            BoxShadow(color: Color(0x0A121614), blurRadius: 1, offset: Offset(0, 0)),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppColors.ink,
        unselectedLabelColor: AppColors.ink3,
        labelStyle: AppText.bodyStrong.copyWith(fontSize: 13.5),
        unselectedLabelStyle: AppText.callout.copyWith(fontSize: 13.5),
        labelPadding: EdgeInsets.zero,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        tabs: [
          for (var i = 0; i < labels.length; i++)
            Tab(
              height: 34,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icons != null) ...[
                  Icon(icons![i], size: 15),
                  const SizedBox(width: 6),
                ],
                Text(labels[i]),
              ]),
            ),
        ],
      ),
    );
  }
}

// ── Feedback ────────────────────────────────────────────────────────────────

enum BannerTone { info, success, warning, danger }

class InlineBanner extends StatelessWidget {
  final String message;
  final BannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  const InlineBanner(this.message,
      {super.key, this.tone = BannerTone.info, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (tone) {
      BannerTone.info => (AppColors.info, Icons.info_outline_rounded),
      BannerTone.success => (AppColors.success, Icons.check_circle_outline_rounded),
      BannerTone.warning => (AppColors.warning, Icons.error_outline_rounded),
      BannerTone.danger => (AppColors.danger, Icons.wifi_off_rounded),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.07),
        borderRadius: AppRadius.control,
        border: Border.all(color: AppColors.tint(color, 0.22)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message, style: AppText.callout.copyWith(color: AppColors.ink))),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: color, minimumSize: const Size(44, 36)),
            child: Text(actionLabel!),
          ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            IconWell(icon, size: 56),
            const SizedBox(height: AppSpace.lg),
            Text(title, style: AppText.headline, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: AppText.callout, textAlign: TextAlign.center),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: AppSpace.xl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  final String? label;
  const LoadingView({super.key, this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          if (label != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(label!, style: AppText.footnote),
          ],
        ]),
      );
}

// ── Translucent chrome ──────────────────────────────────────────────────────

/// Frosted surface for bars that float over scrolling content.
class Frosted extends StatelessWidget {
  final Widget child;
  final Color tint;
  final double opacity;
  final Border? border;

  const Frosted({
    super.key,
    required this.child,
    this.tint = AppColors.canvas,
    this.opacity = 0.82,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final reduceTransparency = MediaQuery.maybeHighContrastOf(context) ?? false;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: reduceTransparency ? 1 : opacity),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Small key/value line used in detail cards.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final bool emphasize;

  const InfoRow(this.label, this.value,
      {super.key, this.icon, this.valueColor, this.emphasize = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.ink3),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: AppText.callout)),
          const SizedBox(width: AppSpace.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: (emphasize ? AppText.bodyStrong : AppText.body)
                  .copyWith(color: valueColor ?? AppColors.ink),
            ),
          ),
        ]),
      );
}

// ── Large-title header ──────────────────────────────────────────────────────

/// iOS-style large title: a big left-aligned title that, as you scroll,
/// fades out while a small centred title fades into a frosted bar.
class LargeTitleSliverAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final double maxWidth;

  const LargeTitleSliverAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.bottom,
    this.maxWidth = AppLayout.maxContent,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottomH = bottom?.preferredSize.height ?? 0;
    final large = subtitle == null ? 60.0 : 78.0;
    const toolbar = kToolbarHeight;
    final inset = AppLayout.inset(context, maxWidth);

    return SliverAppBar(
      pinned: true,
      expandedHeight: toolbar + large + bottomH,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const Border(),
      leading: leading,
      actions: actions,
      bottom: bottom,
      flexibleSpace: LayoutBuilder(builder: (ctx, c) {
        final minH = top + toolbar + bottomH;
        final maxH = top + toolbar + large + bottomH;
        final t = ((c.maxHeight - minH) / (maxH - minH)).clamp(0.0, 1.0); // 1 = expanded
        final collapsed = t < 0.02;
        return Stack(fit: StackFit.expand, children: [
          AnimatedOpacity(
            opacity: collapsed ? 1 : 0,
            duration: AppMotion.fast,
            child: const Frosted(
              border: Border(bottom: BorderSide(color: AppColors.hairline, width: 0.5)),
              child: SizedBox.expand(),
            ),
          ),
          if (!collapsed) const ColoredBox(color: AppColors.canvas),
          // Small title in the bar.
          Positioned(
            top: top,
            left: 64,
            right: 64,
            height: toolbar,
            child: Center(
              child: Opacity(
                opacity: (1 - t * 4).clamp(0.0, 1.0),
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.headline.copyWith(fontSize: 17)),
              ),
            ),
          ),
          // Large title under the bar.
          Positioned(
            left: inset,
            right: inset,
            bottom: bottomH + 12,
            child: Opacity(
              opacity: ((t - 0.25) / 0.75).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.largeTitle),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.callout),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

/// Initials in a circle — a person reads faster than a generic icon.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  const InitialsAvatar(this.name, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.sunken, shape: BoxShape.circle),
      child: Text(initials,
          style: AppText.bodyStrong.copyWith(fontSize: size * 0.36, color: AppColors.ink2)),
    );
  }
}

/// Square icon button with a hairline, for actions on cards.
class CardIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  const CardIconButton(this.icon,
      {super.key, required this.tooltip, this.onPressed, this.filled = false});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: onPressed,
          pressedScale: 0.92,
          semanticLabel: tooltip,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: filled ? AppColors.ink : AppColors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: filled ? AppColors.ink : AppColors.hairlineStrong),
            ),
            child: Icon(icon, size: 18, color: filled ? Colors.white : AppColors.ink),
          ),
        ),
      );
}

/// Standard text field decoration. Borders, fill and colours come from the
/// theme; screens only say what the field is.
InputDecoration fieldDecoration(String label,
        {IconData? icon, String? hint, String? helper, Widget? suffix, String? prefixText}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixText: prefixText,
      prefixIcon: icon == null ? null : Icon(icon, size: 19),
      suffixIcon: suffix,
    );
