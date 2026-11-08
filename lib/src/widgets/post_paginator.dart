import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Offset pager for a creator's posts.
///
/// The JSON API exposes no total count, so [total] is scraped from the
/// server-rendered creator page and may be null. When it is null the pager
/// still offers prev/next and a page number, just without "of N".
class PostPaginator extends StatefulWidget {
  final int page;
  final int pageSize;
  final int? total;
  final ValueChanged<int> onPage;

  const PostPaginator({
    super.key,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onPage,
  });

  @override
  State<PostPaginator> createState() => _PostPaginatorState();
}

class _PostPaginatorState extends State<PostPaginator> {
  final _jumpController = TextEditingController();

  @override
  void dispose() {
    _jumpController.dispose();
    super.dispose();
  }

  int? get _maxPage {
    final total = widget.total;
    if (total == null) return null;
    return ((total + widget.pageSize - 1) ~/ widget.pageSize).clamp(1, 1 << 30);
  }

  bool get _hasMultiplePages => _maxPage == null || _maxPage! > 1;

  bool get _canGoNext {
    final maxPage = _maxPage;
    return maxPage == null || widget.page < maxPage;
  }

  void _go(int page) {
    final maxPage = _maxPage;
    final target = maxPage == null ? page : page.clamp(1, maxPage);
    if (target == widget.page) return;
    widget.onPage(target);
  }

  void _jump() {
    final value = int.tryParse(_jumpController.text.trim());
    _jumpController.clear();
    if (value == null) return;
    _go(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.total;
    final first = (widget.page - 1) * widget.pageSize + 1;
    final last = widget.page * widget.pageSize;
    final label = total == null
        ? 'Page ${widget.page}'
        : 'Showing $first - ${last > total ? total : last} of $total';

    if (!_hasMultiplePages) {
      return Center(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Numbers + arrows + jump do not fit on a phone; collapse to
        // "‹ Page N of M ›" and keep the jump field only when there is room.
        final wide = constraints.maxWidth >= 620;
        return wide ? _wide(theme, label) : _compact(theme, label, constraints.maxWidth);
      },
    );
  }

  Widget _wide(ThemeData theme, String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'First page',
          onPressed: widget.page > 1 ? () => _go(1) : null,
          icon: const Icon(Icons.first_page, size: 18),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Previous page',
          onPressed: widget.page > 1 ? () => _go(widget.page - 1) : null,
          icon: const Icon(Icons.chevron_left, size: 18),
        ),
        ..._numberButtons(theme),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Next page',
          onPressed: _canGoNext ? () => _go(widget.page + 1) : null,
          icon: const Icon(Icons.chevron_right, size: 18),
        ),
        if (_maxPage != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Last page',
            onPressed: widget.page < _maxPage! ? () => _go(_maxPage!) : null,
            icon: const Icon(Icons.last_page, size: 18),
          ),
        if (_maxPage != null) ...[
          const SizedBox(width: 8),
          SizedBox(width: 64, height: 30, child: _jumpField(theme)),
        ],
      ],
    );
  }

  Widget _compact(ThemeData theme, String label, double maxWidth) {
    final maxPage = _maxPage;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'First page',
              onPressed: widget.page > 1 ? () => _go(1) : null,
              icon: const Icon(Icons.first_page, size: 18),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Previous page',
              onPressed: widget.page > 1 ? () => _go(widget.page - 1) : null,
              icon: const Icon(Icons.chevron_left, size: 18),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                maxPage == null ? '${widget.page}' : '${widget.page} / $maxPage',
                style: theme.textTheme.bodySmall,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Next page',
              onPressed: _canGoNext ? () => _go(widget.page + 1) : null,
              icon: const Icon(Icons.chevron_right, size: 18),
            ),
            if (maxPage != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Last page',
                onPressed: widget.page < maxPage ? () => _go(maxPage) : null,
                icon: const Icon(Icons.last_page, size: 18),
              ),
            if (maxPage != null && maxWidth >= 320) ...[
              const SizedBox(width: 4),
              SizedBox(width: 56, height: 28, child: _jumpField(theme)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _jumpField(ThemeData theme) {
    return TextField(
      controller: _jumpController,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => _jump(),
      style: theme.textTheme.bodySmall,
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'page',
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        border: OutlineInputBorder(),
      ),
    );
  }

  List<Widget> _numberButtons(ThemeData theme) {
    final maxPage = _maxPage;
    if (maxPage == null) return const [];
    const window = 9;
    var start = widget.page - window ~/ 2;
    if (start < 1) start = 1;
    var end = start + window - 1;
    if (end > maxPage) {
      end = maxPage;
      start = (end - window + 1).clamp(1, maxPage);
    }
    final buttons = <Widget>[];
    for (var p = start; p <= end; p++) {
      final isCurrent = p == widget.page;
      buttons.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: isCurrent ? null : () => _go(p),
            child: Container(
              constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: isCurrent ? theme.colorScheme.primary.withValues(alpha: 0.18) : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$p',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return buttons;
  }
}
