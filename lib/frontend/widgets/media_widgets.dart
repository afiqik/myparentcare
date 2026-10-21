import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../database_storage/media_repository.dart';
import '../../database_storage/models.dart';
import '../theme.dart';

/// Gambar yang disimpan dalam Firestore `media/{id}` (Blob termampat).
/// Dimuat turun sekali, kemudian dari cache memori/cakera.
class FirestoreImage extends StatefulWidget {
  final String mediaId;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? error;

  const FirestoreImage({
    super.key,
    required this.mediaId,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  @override
  State<FirestoreImage> createState() => _FirestoreImageState();
}

class _FirestoreImageState extends State<FirestoreImage> {
  Future<MediaItem?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void didUpdateWidget(FirestoreImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId) _future = _load();
  }

  Future<MediaItem?> _load() {
    final repo = context.read<MediaRepository>();
    return repo.fetch(widget.mediaId).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaItem?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data?.bytes;
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => widget.error ?? const _MediaFallback(),
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return widget.error ?? const _MediaFallback();
        }
        return widget.placeholder ??
            const ColoredBox(
              color: AppTheme.surfaceTint,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
      },
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTheme.surfaceTint,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: AppTheme.inkSoft),
      ),
    );
  }
}

Future<void> openExternalLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the link.')),
    );
  }
}

/// Galeri gambar & video bagi satu program.
class MediaGallery extends StatelessWidget {
  final List<MediaRef> media;
  final void Function(MediaRef ref)? onDelete;

  const MediaGallery({super.key, required this.media, this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: media.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = media[index];
          return SizedBox(
            width: 176,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: item.isVideo
                        ? VideoLinkTile(media: item)
                        : GestureDetector(
                            onTap: () => _openImage(context, item),
                            child: FirestoreImage(mediaId: item.id),
                          ),
                  ),
                ),
                if (onDelete != null)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton.filledTonal(
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onDelete!(item),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openImage(BuildContext context, MediaRef item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InteractiveViewer(
              child: FirestoreImage(mediaId: item.id, fit: BoxFit.contain),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pautan video (YouTube/Drive). Gambar kecil YouTube jika tersedia.
class VideoLinkTile extends StatelessWidget {
  final MediaRef media;

  const VideoLinkTile({super.key, required this.media});

  @override
  Widget build(BuildContext context) {
    final youtubeId = MediaRepository.youtubeId(media.url);
    return Material(
      color: AppTheme.ink,
      child: InkWell(
        onTap: () => openExternalLink(context, media.url),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (youtubeId != null)
              Image.network(
                'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x00000000), Color(0xAA000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Text(
                media.caption.isEmpty ? 'Watch video' : media.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
