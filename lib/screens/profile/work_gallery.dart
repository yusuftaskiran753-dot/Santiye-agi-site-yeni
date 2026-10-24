import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../models/work_photo.dart';
import '../../services/portfolio_backend.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class WorkGallery extends StatefulWidget {
  const WorkGallery({super.key, required this.userId});
  final String userId;
  @override
  State<WorkGallery> createState() => _WorkGalleryState();
}

class _WorkGalleryState extends State<WorkGallery> {
  PortfolioBackend? _backend;
  Future<List<WorkPhoto>>? _photos;
  final Map<String, Future<Uint8List>> _images = {};
  bool _busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = context.read<AppState>().backend;
    if (backend is PortfolioBackend && !identical(backend, _backend)) {
      _backend = backend as PortfolioBackend;
      _photos = _backend!.fetchWorkPhotos(widget.userId);
      if (backend.isLive &&
          backend.userId == widget.userId &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _recoverSelection();
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant WorkGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _images.clear();
      _photos = _backend?.fetchWorkPhotos(widget.userId);
    }
  }

  void _reload() {
    setState(() {
      _photos = _backend!.fetchWorkPhotos(widget.userId);
    });
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (picked == null || !mounted) return;
      await _reviewSelection(picked);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recoverSelection() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (!mounted || lost.isEmpty) return;
      if (lost.exception != null) throw lost.exception!;
      final files = lost.files;
      if (files == null || files.isEmpty) return;
      setState(() => _busy = true);
      await _reviewSelection(files.first);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewSelection(XFile picked) async {
    if (await picked.length() > 8 * 1024 * 1024) {
      throw Exception('Fotoğraf en fazla 8 MB olmalı.');
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final caption = await showDialog<String>(
      context: context,
      builder: (_) => _PhotoCaption(bytes: bytes),
    );
    if (caption == null || !mounted) return;
    await _send(bytes, caption, newUuid());
  }

  Future<void> _send(Uint8List bytes, String caption, String id) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _backend!.uploadWorkPhoto(bytes, caption, id: id);
      if (mounted) {
        _reload();
        showSnack(context, 'İş fotoğrafı profilinize eklendi.');
      }
    } catch (e) {
      if (mounted) {
        showError(context, e, onRetry: () => _send(bytes, caption, id));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(WorkPhoto photo) async {
    if (!await confirm(
      context,
      'Fotoğraf silinsin mi?',
      message: 'Bu fotoğraf profilinizden kaldırılacak.',
      ok: 'Sil',
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _backend!.deleteWorkPhoto(photo.id);
      _images.remove(photo.id);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = context.watch<AppState>().myId == widget.userId;
    if (_backend == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(mine ? 'Yaptığım işler' : 'Yaptığı işler'),
        FutureBuilder<List<WorkPhoto>>(
          future: _photos,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Text('İş fotoğrafları yüklenemedi.'),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Tekrar dene'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final photos = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (photos.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Henüz iş fotoğrafı paylaşılmadı.'),
                    ),
                  ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    final image = _images.putIfAbsent(
                      photo.id,
                      () => _backend!.fetchWorkPhotoBytes(photo.id),
                    );
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Expanded(
                            child: FutureBuilder<Uint8List>(
                              future: image,
                              builder: (context, snap) {
                                if (snap.hasError) {
                                  return IconButton(
                                    tooltip: 'Fotoğrafı yeniden yükle',
                                    icon: const Icon(Icons.refresh),
                                    onPressed: () => setState(() {
                                      _images.remove(photo.id);
                                    }),
                                  );
                                }
                                if (!snap.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                return InkWell(
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => Dialog(
                                      child: InteractiveViewer(
                                        child: Image.memory(
                                          snap.data!,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: Image.memory(
                                    snap.data!,
                                    width: double.infinity,
                                    cacheWidth: 512,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    photo.caption.isEmpty
                                        ? 'İş fotoğrafı'
                                        : photo.caption,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              if (mine)
                                IconButton(
                                  tooltip: 'Fotoğrafı sil',
                                  onPressed: _busy
                                      ? null
                                      : () => _delete(photo),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (mine) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy || photos.length >= 20 ? null : _upload,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(_busy ? 'İşlem sürüyor…' : 'İş fotoğrafı ekle'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'En fazla 20 fotoğraf paylaşabilirsiniz. Fotoğraflarınız profilinizi ziyaret eden kullanıcılara görünür.',
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PhotoCaption extends StatefulWidget {
  const _PhotoCaption({required this.bytes});
  final Uint8List bytes;
  @override
  State<_PhotoCaption> createState() => _PhotoCaptionState();
}

class _PhotoCaptionState extends State<_PhotoCaption> {
  final _caption = TextEditingController();
  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yaptığınız işi paylaşın'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.memory(widget.bytes, height: 160, fit: BoxFit.contain),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            maxLength: 200,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'İş açıklaması (isteğe bağlı)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _caption.text.trim().replaceAll(RegExp(r'[\r\n]'), ' '),
        ),
        child: const Text('Paylaş'),
      ),
    ],
  );
}
