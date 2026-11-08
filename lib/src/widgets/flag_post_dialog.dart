import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/flags_store.dart';
import '../utils.dart';

/// Ask for a note about what looks wrong on [post], then store it locally.
///
/// Returns true when a flag was saved.
Future<bool> showFlagPostDialog(BuildContext context, Post post, {String? existing, bool clear = false}) async {
  final controller = TextEditingController(text: clear ? '' : (existing ?? ''));
  final comment = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(clear ? 'Remove flag' : 'Flag post'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              post.title.isEmpty ? '${post.service}/${post.user}/${post.id}' : post.title,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'What went wrong? (image did not load, wrong file, …)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!clear && existing != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop('__remove__'),
            child: const Text('Remove flag'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (!clear)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
      ],
    ),
  );

  controller.dispose();
  if (comment == null) return false;

  final key = '${post.service}/${post.user}/${post.id}';
  if (comment == '__remove__') {
    await FlagsStore.instance.remove(key);
    return false;
  }

  await FlagsStore.instance.save(PostFlag(
    key: key,
    url: '${FileHelpers.baseUrl}/${post.service}/user/${post.user}/post/${post.id}',
    service: post.service,
    creatorId: post.user,
    postId: post.id,
    title: post.title,
    comment: comment,
    createdAt: DateTime.now().toUtc().toIso8601String(),
    hasFull: post.hasFull,
    previewState: post.previewState,
    files: post.allFiles.map((f) {
      final state = f.tempUrl != null ? 'temporary' : (post.hasFull ? 'stored' : 'unavailable');
      return <String, dynamic>{
        'name': f.name,
        'state': state,
        if (f.previewOnly == true) 'previewOnly': true,
      };
    }).toList(),
  ));
  return true;
}
