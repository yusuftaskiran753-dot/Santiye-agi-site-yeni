import 'dart:io';

import 'package:flutter/material.dart';

/// Kanıt fotoğrafı seçme kutusu (yorum ve engelleme ekranlarında ortak).
class EvidencePhotoBox extends StatelessWidget {
  const EvidencePhotoBox({
    super.key,
    required this.path,
    required this.label,
    required this.onPick,
    required this.onClear,
    this.errorText,
  });

  final String path;
  final String label;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (path.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              key: const Key('evidence-pick'),
              onPressed: onPick,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(label, style: const TextStyle(fontSize: 16)),
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                errorText!,
                style: TextStyle(color: scheme.error, fontSize: 12.5),
              ),
            ),
        ],
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(path),
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: 90,
              alignment: Alignment.center,
              color: scheme.surfaceContainerHighest,
              child: const Text('Fotoğraf eklendi'),
            ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: IconButton.filled(
            key: const Key('evidence-clear'),
            tooltip: 'Fotoğrafı kaldır',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }
}
