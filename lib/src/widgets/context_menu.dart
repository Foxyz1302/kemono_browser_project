import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data types
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for entries in a [FContextMenu].
sealed class ContextMenuEntry {
  const ContextMenuEntry();
}

/// A tappable menu action.
///
/// Layout: `[icon] label [shortcut]` with an optional subtitle below the label.
class ContextMenuAction extends ContextMenuEntry {
  /// Label text. Required.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional subtitle shown below the label.
  final String? subtitle;

  /// Optional shortcut hint shown right-aligned (e.g. `Ctrl+C`).
  final String? shortcut;

  /// Called when the action is tapped.
  final VoidCallback? onTap;

  /// Whether the action is interactive. Defaults to true.
  final bool enabled;

  /// When true the label and icon are rendered in the error colour.
  final bool destructive;

  const ContextMenuAction({
    required this.label,
    this.icon,
    this.subtitle,
    this.shortcut,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
  });
}

/// A visual separator between groups of actions.
class ContextMenuDivider extends ContextMenuEntry {
  const ContextMenuDivider();
}

// ─────────────────────────────────────────────────────────────────────────────
// FContextMenu
// ─────────────────────────────────────────────────────────────────────────────

/// A Material-styled context menu that opens on right-click (desktop) or
/// long-press (touch).
///
/// Usage:
/// ```dart
/// FContextMenu(
///   entries: [
///     const ContextMenuAction(label: 'Copy', icon: Icons.copy, onTap: _onCopy),
///     const ContextMenuDivider(),
///     const ContextMenuAction(label: 'Delete', icon: Icons.delete, destructive: true, onTap: _onDelete),
///   ],
///   child: MyWidget(...),
/// )
/// ```
class FContextMenu extends StatefulWidget {
  /// The menu entries ([ContextMenuAction]s and [ContextMenuDivider]s).
  final List<ContextMenuEntry> entries;

  /// The widget that acts as the trigger area.
  final Widget child;

  /// Optional callback fired when the menu is dismissed (by action, outside
  /// tap, or Escape).
  final VoidCallback? onDismissed;

  const FContextMenu({
    required this.entries,
    required this.child,
    this.onDismissed,
    super.key,
  });

  @override
  State<FContextMenu> createState() => _FContextMenuState();
}

class _FContextMenuState extends State<FContextMenu> {
  final _overlayController = OverlayPortalController();
  Offset? _globalPosition;

  // ── helpers ───────────────────────────────────────────────────────────────

  static bool get _isTouchDevice =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.fuchsia;

  void _showAtGlobal(Offset globalPosition) {
    _globalPosition = globalPosition;
    setState(() {});
    _overlayController.show();
  }

  void _hide() {
    _globalPosition = null;
    _overlayController.hide();
    widget.onDismissed?.call();
  }

  void _onPrimaryTap(PointerEvent e) {
    // Hide only when the menu is already visible and a primary click happens
    // on the trigger (acts as a toggle-off).
    if (_overlayController.isShowing) {
      _hide();
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;

    // Right-click (desktop) / secondary button.
    child = Listener(
      onPointerDown: (e) {
        if (e.buttons & kSecondaryButton != 0) {
          _showAtGlobal(e.position);
        } else if (e.buttons & kPrimaryButton != 0) {
          _onPrimaryTap(e);
        }
      },
      child: child,
    );

    // Long-press (touch).
    if (_isTouchDevice) {
      child = GestureDetector(
        onLongPressStart: (details) => _showAtGlobal(details.globalPosition),
        behavior: HitTestBehavior.translucent,
        child: child,
      );
    }

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (_) {
        if (_globalPosition == null) {
          return const SizedBox.shrink();
        }
        return _ContextMenuOverlay(
          globalPosition: _globalPosition!,
          entries: widget.entries,
          onDismiss: _hide,
        );
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ContextMenuOverlay
// ─────────────────────────────────────────────────────────────────────────────

class _ContextMenuOverlay extends StatefulWidget {
  final Offset globalPosition;
  final List<ContextMenuEntry> entries;
  final VoidCallback onDismiss;

  const _ContextMenuOverlay({
    required this.globalPosition,
    required this.entries,
    required this.onDismiss,
  });

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  /// Key attached to the menu Card so we can measure its actual size.
  final _menuKey = GlobalKey();

  /// Adjusted position after overflow detection.
  Offset? _adjustedPos;

  /// Whether the exit animation is running.
  bool _dismissing = false;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.linear);
    _scale = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    );

    _animCtrl.addStatusListener(_onStatusChanged);
    // Start entrance.
    _animCtrl.forward();

    // Measure and adjust position after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _adjustPosition());
  }

  @override
  void dispose() {
    _animCtrl.removeStatusListener(_onStatusChanged);
    _animCtrl.dispose();
    super.dispose();
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _dismissing) {
      widget.onDismiss();
    }
  }

  // ── positioning ───────────────────────────────────────────────────────────

  void _adjustPosition() {
    final menuBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (menuBox == null || !menuBox.hasSize) return;

    final menuSize = menuBox.size;
    final mediaQuery = MediaQuery.of(context);
    final screen = mediaQuery.size;
    final padding = mediaQuery.padding;

    var x = widget.globalPosition.dx;
    var y = widget.globalPosition.dy;

    // Horizontal flip.
    if (x + menuSize.width > screen.width) {
      x = screen.width - menuSize.width - padding.right;
    }
    // Vertical flip.
    if (y + menuSize.height > screen.height) {
      y = screen.height - menuSize.height - padding.bottom;
    }

    // Ensure minimum edge padding.
    x = x.clamp(padding.left, screen.width - menuSize.width - padding.right);
    y = y.clamp(padding.top, screen.height - menuSize.height - padding.bottom);

    if (_adjustedPos == null || _adjustedPos!.dx != x || _adjustedPos!.dy != y) {
      setState(() => _adjustedPos = Offset(x, y));
    }
  }

  // ── dismiss ───────────────────────────────────────────────────────────────

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _animCtrl.reverse();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pos = _adjustedPos ?? widget.globalPosition;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Stack(
      children: [
        // Invisible barrier. Listener catches ALL pointer events (left,
        // right, middle click). Menu items (above in the stack) take
        // priority via InkWell gesture absorption.
        Positioned.fill(
          child: Listener(
            onPointerDown: (_) => _dismiss(),
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        // The menu itself.
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: Material(
            type: MaterialType.transparency,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
              },
              child: FocusScope(
                child: FadeTransition(
                  opacity: Tween<double>(begin: 0, end: 1).animate(_fade),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.93, end: 1).animate(_scale),
                    child: Card(
                      key: _menuKey,
                      margin: EdgeInsets.zero,
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      color: cs.surfaceContainerHighest,
                      surfaceTintColor: Colors.transparent,
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildEntries(theme),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEntries(ThemeData theme) {
    final children = <Widget>[];
    for (final entry in widget.entries) {
      switch (entry) {
        case ContextMenuAction action:
          children.add(_ContextMenuActionWidget(
            action: action,
            onActionPerformed: _dismiss,
          ));
        case ContextMenuDivider _:
          children.add(Divider(height: 1, thickness: 1, color: theme.dividerColor));
      }
    }
    return children;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ContextMenuActionWidget
// ─────────────────────────────────────────────────────────────────────────────

class _ContextMenuActionWidget extends StatelessWidget {
  final ContextMenuAction action;
  final VoidCallback onActionPerformed;

  const _ContextMenuActionWidget({
    required this.action,
    required this.onActionPerformed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    final foreground = action.destructive
        ? cs.error
        : (action.enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38));

    return InkWell(
      onTap: action.enabled
          ? () {
              action.onTap?.call();
              onActionPerformed();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action.icon != null) ...[
              Icon(action.icon, size: 18, color: foreground),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action.label, style: text.bodyLarge?.copyWith(color: foreground)),
                  if (action.subtitle != null)
                    Text(
                      action.subtitle!,
                      style: text.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                ],
              ),
            ),
            if (action.shortcut != null) ...[
              const SizedBox(width: 24),
              Text(
                action.shortcut!,
                style: text.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
