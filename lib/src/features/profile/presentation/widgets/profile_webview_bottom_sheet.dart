import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/worthify_circular_icon_button.dart';

class ProfileWebViewBottomSheet extends StatefulWidget {
  const ProfileWebViewBottomSheet({
    super.key,
    required this.title,
    required this.initialUrl,
  });

  final String title;
  final String initialUrl;

  @override
  State<ProfileWebViewBottomSheet> createState() =>
      _ProfileWebViewBottomSheetState();
}

class _ProfileWebViewBottomSheetState
    extends State<ProfileWebViewBottomSheet> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  double _handleDragOffset = 0;
  static const double _maxHandleDrag = 140;
  bool _isContentAtTop = true;
  bool _scrollListenerInjected = false;
  int? _activeContentPointer;
  Offset? _initialContentPointerPosition;
  Offset? _lastContentPointerPosition;
  bool _isTrackingContentDrag = false;
  static const double _dragThreshold = 8.0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'WorthifyScrollState',
        onMessageReceived: (message) {
          final scrollOffset = double.tryParse(message.message) ?? 0;
          final atTop = scrollOffset <= 1.0;
          if (!mounted) {
            _isContentAtTop = atTop;
            return;
          }
          if (_isContentAtTop != atTop) {
            setState(() => _isContentAtTop = atTop);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _scrollListenerInjected = false;
            setState(() {
              _isLoading = true;
              _hasError = false;
              _isContentAtTop = true;
            });
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
            _injectScrollListener();
            // Re-inject periodically to ensure it's working
            Future.delayed(const Duration(milliseconds: 500), _injectScrollListener);
            Future.delayed(const Duration(milliseconds: 1000), _injectScrollListener);
          },
          onWebResourceError: (_) {
            _scrollListenerInjected = false;
            setState(() {
              _hasError = true;
              _isLoading = false;
              _isContentAtTop = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  void _handleReload() {
    setState(() {
      _hasError = false;
      _isLoading = true;
    });
    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _injectScrollListener() async {
    if (_scrollListenerInjected || _hasError) return;
    const script = '''
      (function() {
        if (!window.WorthifyScrollState || window.__worthifyScrollListenerAdded) return;
        window.__worthifyScrollListenerAdded = true;
        function sendScrollPosition() {
          var position = window.scrollY || 0;
          try {
            window.WorthifyScrollState.postMessage(String(position));
          } catch (err) {}
        }
        document.addEventListener('scroll', sendScrollPosition, true);
        sendScrollPosition();
      })();
    ''';
    try {
      await _controller.runJavaScript(script);
      _scrollListenerInjected = true;
    } catch (_) {
      _scrollListenerInjected = false;
    }
  }

  void _handleContentPointerDown(PointerDownEvent event) {
    if (!_canDragFromContent) {
      _cancelContentPointerTracking();
      return;
    }
    _activeContentPointer = event.pointer;
    _initialContentPointerPosition = event.position;
    _lastContentPointerPosition = event.position;
    _isTrackingContentDrag = false;
  }

  void _handleContentPointerMove(PointerMoveEvent event) {
    if (_activeContentPointer != event.pointer ||
        _lastContentPointerPosition == null ||
        _initialContentPointerPosition == null) {
      return;
    }

    if (!_isTrackingContentDrag && !_canDragFromContent) {
      _cancelContentPointerTracking();
      return;
    }

    final totalDy = event.position.dy - _initialContentPointerPosition!.dy;
    final dy = event.position.dy - _lastContentPointerPosition!.dy;
    _lastContentPointerPosition = event.position;

    if (!_isTrackingContentDrag) {
      // Check if we've exceeded the threshold
      if (totalDy.abs() < _dragThreshold) {
        // Haven't moved enough yet, keep waiting
        return;
      }

      // We've moved enough - decide direction
      if (totalDy > 0) {
        // Dragging down - start tracking for dismiss
        _isTrackingContentDrag = true;
        _onHandleDragStart(DragStartDetails(globalPosition: event.position));
      } else {
        // Dragging up - let web view handle scrolling
        _cancelContentPointerTracking();
        return;
      }
    }

    // We're tracking the drag, update it
    _onHandleDragUpdate(
      DragUpdateDetails(globalPosition: event.position, delta: Offset(0, dy)),
    );
  }

  void _handleContentPointerUp(PointerUpEvent event) {
    if (_activeContentPointer != event.pointer) return;
    if (_isTrackingContentDrag) {
      _onHandleDragEnd(DragEndDetails());
    }
    _cancelContentPointerTracking();
  }

  void _handleContentPointerCancel(PointerCancelEvent event) {
    if (_activeContentPointer != event.pointer) return;
    _cancelContentPointerTracking();
    _resetHandleDrag();
  }

  void _cancelContentPointerTracking() {
    _activeContentPointer = null;
    _initialContentPointerPosition = null;
    _lastContentPointerPosition = null;
    _isTrackingContentDrag = false;
  }

  void _onHandleDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy < 0 && _handleDragOffset <= 0) return;
    final updated = (_handleDragOffset + details.delta.dy)
        .clamp(0.0, _maxHandleDrag);
    setState(() {
      _handleDragOffset = updated;
    });
  }

  void _onHandleDragStart(DragStartDetails details) {
    if (!mounted) return;
    setState(() => _handleDragOffset = 0);
  }

  void _onHandleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_handleDragOffset > _maxHandleDrag / 2 || velocity > 900) {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    setState(() {
      _handleDragOffset = 0;
    });
  }

  void _resetHandleDrag() {
    if (!mounted) return;
    setState(() => _handleDragOffset = 0);
  }

  bool get _canDragFromContent => false;
  bool get _shouldHandleContentPointerEvents =>
      _isTrackingContentDrag && _canDragFromContent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
    final radius = context.radius.large;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      top: true,
      bottom: false,
      child: Transform.translate(
        offset: Offset(0, _handleDragOffset),
        child: Container(
          padding: EdgeInsets.only(
            bottom: (bottomInset > 0 ? bottomInset : spacing.l),
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(radius * 1.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, -6),
                // Pulls the shadow in so it doesn't tint the bottom edge
                spreadRadius: -8,
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _onHandleDragStart,
                onVerticalDragUpdate: _onHandleDragUpdate,
                onVerticalDragEnd: _onHandleDragEnd,
                onVerticalDragCancel: _resetHandleDrag,
                child: Column(
                  children: [
                    SizedBox(height: spacing.s),
                    Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        spacing.l,
                        spacing.m,
                        spacing.l,
                        spacing.s,
                      ),
                      child: Row(
                        children: [
                          WorthifyCircularIconButton(
                            icon: Icons.close,
                            iconSize: 18,
                            onPressed: () => Navigator.of(context).maybePop(),
                            tooltip: 'Close',
                            semanticLabel: 'Close',
                          ),
                          Expanded(
                            child: Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'PlusJakartaSans',
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.deferToChild,
                    onPointerDown: _shouldHandleContentPointerEvents
                        ? _handleContentPointerDown
                        : null,
                    onPointerMove: _shouldHandleContentPointerEvents
                        ? _handleContentPointerMove
                        : null,
                    onPointerUp: _shouldHandleContentPointerEvents
                        ? _handleContentPointerUp
                        : null,
                    onPointerCancel: _shouldHandleContentPointerEvents
                        ? _handleContentPointerCancel
                        : null,
                    child: Stack(
                      children: [
                        if (_hasError)
                          Center(
                            child: Padding(
                              padding: EdgeInsets.all(spacing.l),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.wifi_off_outlined,
                                    size: 48,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  SizedBox(height: spacing.m),
                                  Text(
                                    'Unable to load this page.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'PlusJakartaSans',
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  SizedBox(height: spacing.s),
                                  Text(
                                    'Please check your connection and try again.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colorScheme.onSurfaceVariant,
                                      fontFamily: 'PlusJakartaSans',
                                    ),
                                  ),
                                  SizedBox(height: spacing.m),
                                  FilledButton(
                                    onPressed: _handleReload,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          WebViewWidget(controller: _controller),
                        if (_isLoading)
                          Align(
                            alignment: Alignment.topCenter,
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              color: const Color(0xFFF2003C),
                              backgroundColor: const Color(0xFFF2003C)
                                  .withOpacity(0.2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
