import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A single-row toolbar that the user drags sideways when its buttons don't
/// fit, like the MacBook Touch Bar. The edges fade out while more buttons are
/// hidden in that direction, so it's obvious the bar can be dragged.
class TouchBar extends StatefulWidget {
  const TouchBar({super.key, required this.children, this.trailing, this.height = 52});

  final List<Widget> children;

  /// Pinned to the right edge and never scrolls away (e.g. "hide keyboard").
  final Widget? trailing;

  final double height;

  @override
  State<TouchBar> createState() => _TouchBarState();
}

class _TouchBarState extends State<TouchBar> {
  final _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdges());
  }

  @override
  void didUpdateWidget(TouchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdges());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateEdges() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final left = position.pixels > 1;
    final right = position.pixels < position.maxScrollExtent - 1;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      child: SizedBox(
        height: widget.height,
        child: Row(
          children: [
            Expanded(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  _updateEdges();
                  return false;
                },
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      _canScrollLeft ? Colors.transparent : Colors.black,
                      Colors.black,
                      Colors.black,
                      _canScrollRight ? Colors.transparent : Colors.black,
                    ],
                    stops: const [0, 0.08, 0.92, 1],
                  ).createShader(bounds),
                  // Mouse and trackpad drag it too (web, desktop), like a swipe.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                    child: ListView(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: widget.children,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.trailing != null) ...[
              const VerticalDivider(width: 1, indent: 10, endIndent: 10),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
