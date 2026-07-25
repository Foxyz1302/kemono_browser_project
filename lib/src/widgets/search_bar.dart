import 'dart:async';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// A debounced search bar that immediately updates a signal on every keystroke
/// and fires [onSearch] after 150ms of inactivity.
///
/// Pattern sourced from MySearchBar in meme_collector_project.
class SearchBar extends StatefulWidget {
  final Signal<String> querySignal;
  final String hintText;
  final ValueChanged<String>? onSearch;

  const SearchBar({
    super.key,
    required this.querySignal,
    this.hintText = 'Search...',
    this.onSearch,
  });

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  late final TextEditingController _controller;
  Timer? _debounce;
  static const _debounceDuration = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.querySignal.value);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    widget.querySignal.value = text;
    setState(() {}); // refresh suffix icon visibility
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      widget.onSearch?.call(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  _onChanged('');
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onChanged: _onChanged,
    );
  }
}
