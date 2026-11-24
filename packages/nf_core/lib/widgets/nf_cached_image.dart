import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class NfCachedImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const NfCachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  State<NfCachedImage> createState() => _NfCachedImageState();
}

class _NfCachedImageState extends State<NfCachedImage> {
  static final Map<String, Uint8List> _memCache = {};
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NfCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  String _safeFileName(String u) {
    final hash = u.codeUnits.fold<int>(17, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return 'img_$hash.bin';
  }

  Future<void> _load() async {
    final u = widget.url.trim();
    if (u.isEmpty || (!u.startsWith('http://') && !u.startsWith('https://'))) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (_memCache.containsKey(u)) {
      if (mounted) setState(() => _bytes = _memCache[u]);
      return;
    }

    try {
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${dir.path}${Platform.pathSeparator}nf_img_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final file = File('${cacheDir.path}${Platform.pathSeparator}${_safeFileName(u)}');
      if (await file.exists()) {
        final diskBytes = await file.readAsBytes();
        if (diskBytes.isNotEmpty) {
          _remember(u, diskBytes);
          if (mounted) setState(() => _bytes = diskBytes);
          return;
        }
      }

      final resp = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        _remember(u, resp.bodyBytes);
        await file.writeAsBytes(resp.bodyBytes, flush: false);
        if (mounted) setState(() => _bytes = resp.bodyBytes);
      } else {
        if (mounted) setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _remember(String key, Uint8List data) {
    if (_memCache.length > 180) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[key] = data;
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_bytes != null) {
      child = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else if (_failed) {
      child = _placeholder();
    } else {
      child = Container(
        width: widget.width ?? 48,
        height: widget.height ?? 48,
        color: const Color(0xFFE2E8F0),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }

  Widget _placeholder() {
    return Container(
      width: widget.width ?? 48,
      height: widget.height ?? 48,
      color: const Color(0xFFF4F9F1),
      alignment: Alignment.center,
      child: const Icon(Icons.eco_rounded, color: Color(0xFF7CB342), size: 24),
    );
  }
}
