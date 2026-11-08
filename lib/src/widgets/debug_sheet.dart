import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import '../api/app_errors.dart';
import '../state/flags_store.dart';

/// Debug surface: flagged posts and the recent failure log, both copyable.
///
/// Opened by long-pressing the app title. Deliberately tiny — it exists to get
/// the real reason for a broken file out of the app without a console.
Future<void> showDebugSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _DebugSheet(),
  );
}

class _DebugSheet extends StatelessWidget {
  const _DebugSheet();

  void _copy(BuildContext context, String text, String done) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  String _everything() {
    return [
      'KemonoBrowserProject diagnostics',
      'generated: ${DateTime.now().toUtc().toIso8601String()}',
      'platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      '',
      '=== FLAGS ===',
      FlagsStore.instance.exportText(),
      '',
      '=== ERRORS ===',
      AppErrors.instance.exportText(),
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Diagnostics', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _copy(context, _everything(), 'Flags + errors copied'),
                    icon: const Icon(Icons.copy_all, size: 18),
                    label: const Text('Copy all'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SignalBuilder(
                builder: (context) {
                  final flags = FlagsStore.instance.flags.value;
                  return _Row(
                    label: 'Flags',
                    value: '${flags.length}',
                    actions: [
                      _action(context, 'Copy', flags.isEmpty ? null : () => _copy(context, FlagsStore.instance.exportText(), 'Flags copied')),
                      _action(context, 'Clear', flags.isEmpty ? null : () {
                        FlagsStore.instance.clear();
                      }),
                    ],
                  );
                },
              ),
              SignalBuilder(
                builder: (context) {
                  final errors = AppErrors.instance.entries.value;
                  return _Row(
                    label: 'Errors',
                    value: '${errors.length}',
                    actions: [
                      _action(context, 'Copy', errors.isEmpty ? null : () => _copy(context, AppErrors.instance.exportText(), 'Errors copied')),
                      _action(context, 'Clear', errors.isEmpty ? null : AppErrors.instance.clear),
                    ],
                  );
                },
              ),
              const Divider(),
              Expanded(
                child: SignalBuilder(
                  builder: (context) {
                    final errors = AppErrors.instance.entries.value.reversed.take(20).toList();
                    if (errors.isEmpty) {
                      return Center(
                        child: Text('No errors recorded', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                      );
                    }
                    return ListView.separated(
                      itemCount: errors.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = errors[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.headline, style: theme.textTheme.bodySmall),
                          subtitle: e.body == null
                              ? null
                              : Text(
                                  e.body!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                                ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(BuildContext context, String label, VoidCallback? onTap) {
    return TextButton(onPressed: onTap, child: Text(label));
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final List<Widget> actions;

  const _Row({required this.label, required this.value, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: Theme.of(context).textTheme.bodyMedium),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        ...actions,
      ],
    );
  }
}
