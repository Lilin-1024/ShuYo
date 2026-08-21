import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../../core/forum_url_resolver.dart';
import '../models/common.dart';
import 'forum_image_headers.dart';
import 'sha1_hash.dart';

class ForumImageCache {
  ForumImageCache._(this._directory);

  static const maxBytes = 100 * 1024 * 1024;
  static const _indexFilename = 'index.json';
  static ForumImageCache? _shared;
  static Future<ForumImageCache>? _sharedFuture;
  static String? _currentAccount;
  static bool _networkEnabled = true;

  final Directory _directory;
  final _entries = <String, _ForumImageEntry>{};
  final _failedKeys = <String>{};
  int _generation = 0;
  Future<void> _writeQueue = Future<void>.value();
  bool _loaded = false;

  static Future<ForumImageCache> shared() {
    final existing = _shared;
    if (existing != null) {
      return Future.value(existing);
    }
    return _sharedFuture ??= _openShared();
  }

  static Future<ForumImageCache> _openShared() async {
    // The platform cache directory is excluded from iCloud and Android backup.
    final root = await getApplicationCacheDirectory();
    final cache = ForumImageCache._(Directory('${root.path}/forum-images'));
    await cache._load();
    _shared = cache;
    return cache;
  }

  static void configureCurrentAccount(String? username) {
    _currentAccount =
        username?.trim().isEmpty == true ? null : username?.trim();
  }

  static String currentPrivateNamespace() {
    return privateNamespaceFor(_currentAccount ?? 'unknown');
  }

  static String privateNamespaceFor(String username) =>
      'private:${username.toLowerCase()}';

  static void setNetworkEnabled(bool enabled) {
    if (enabled && !_networkEnabled) {
      _shared?._failedKeys.clear();
    }
    _networkEnabled = enabled;
  }

  static bool get networkEnabled => _networkEnabled;

  Future<File?> getImage(
    String rawUrl, {
    String variant = 'display',
    String namespace = 'public',
    bool pinned = false,
  }) async {
    final url = _canonicalUrl(rawUrl);
    if (url.isEmpty) {
      return null;
    }
    await _ensureLoaded();
    final key = _key(url, variant, namespace);
    final entry = _entries[key];
    if (entry != null) {
      final file = File('${_directory.path}/${entry.filename}');
      if (await file.exists()) {
        entry.lastAccessAt = DateTime.now();
        await _saveIndex();
        if (pinned && !entry.pinned) {
          entry.pinned = true;
          await _saveIndex();
        }
        return file;
      }
      _entries.remove(key);
      await _saveIndex();
    }
    if (!_networkEnabled || _failedKeys.contains(key)) {
      return null;
    }
    _failedKeys.add(key);
    final generation = _generation;
    try {
      final downloaded = await _download(url);
      if (generation != _generation) {
        return null;
      }
      final filename = '$key.${_extensionForMime(downloaded.mimeType)}';
      final target = File('${_directory.path}/$filename');
      await _atomicWrite(target, downloaded.bytes);
      if (generation != _generation) {
        return null;
      }
      _entries[key] = _ForumImageEntry(
        key: key,
        url: url,
        variant: variant,
        namespace: namespace,
        filename: filename,
        mimeType: downloaded.mimeType,
        size: downloaded.bytes.length,
        lastAccessAt: DateTime.now(),
        etag: downloaded.etag,
        lastModified: downloaded.lastModified,
        pinned: pinned,
      );
      await _trimToCapacity();
      await _saveIndex();
      return await target.exists() ? target : null;
    } on Object {
      return null;
    }
  }

  Future<int> get storageSize async {
    await _ensureLoaded();
    return _entries.values.fold<int>(0, (total, entry) => total + entry.size);
  }

  Future<void> clearAll() async {
    await _ensureLoaded();
    _generation++;
    _failedKeys.clear();
    final files = [
      for (final entry in _entries.values)
        File('${_directory.path}/${entry.filename}'),
    ];
    _entries.clear();
    await Future.wait(files.map((file) async {
      if (await file.exists()) {
        await file.delete();
      }
    }));
    await _saveIndex();
  }

  Future<void> deletePrivateNamespace(String username) async {
    await _ensureLoaded();
    _generation++;
    final namespace = privateNamespaceFor(username);
    final removed =
        _entries.values.where((entry) => entry.namespace == namespace).toList();
    for (final entry in removed) {
      final file = File('${_directory.path}/${entry.filename}');
      if (await file.exists()) {
        await file.delete();
      }
      _entries.remove(entry.key);
    }
    await _saveIndex();
  }

  Future<void> _load() async {
    await _directory.create(recursive: true);
    var changed = false;
    final indexFile = File('${_directory.path}/$_indexFilename');
    if (await indexFile.exists()) {
      try {
        final decoded = jsonDecode(await indexFile.readAsString());
        if (decoded is List) {
          for (final item in decoded.whereType<JsonMap>()) {
            final entry = _ForumImageEntry.fromJson(item);
            if (entry != null) {
              _entries[entry.key] = entry;
            }
          }
        }
      } on Object {
        _entries.clear();
      }
    }
    for (final entry in _entries.values.toList()) {
      if (!await File('${_directory.path}/${entry.filename}').exists()) {
        _entries.remove(entry.key);
        changed = true;
      }
    }
    _loaded = true;
    if (changed) {
      await _saveIndex();
    }
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) {
      await _load();
    }
  }

  Future<_DownloadedForumImage> _download(String url) async {
    final uri = ForumUrlResolver.uri(url);
    final client = HttpClient();
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 12));
      final headers = await ForumImageHeaders.forUrl(url);
      headers?.forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final contentType = response.headers.contentType?.mimeType;
      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (builder, chunk) {
          builder.add(chunk);
          return builder;
        },
      ).then((builder) => builder.takeBytes());
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          bytes.isEmpty) {
        throw const FormatException('invalid image response');
      }
      if (contentType != null &&
          !contentType.toLowerCase().startsWith('image/')) {
        throw const FormatException('non-image response');
      }
      if (!_looksLikeImage(bytes, contentType)) {
        throw const FormatException('corrupt image response');
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      return _DownloadedForumImage(
        bytes: bytes,
        mimeType: contentType ?? _mimeTypeFromBytes(bytes),
        etag: response.headers.value(HttpHeaders.etagHeader),
        lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _atomicWrite(File target, Uint8List bytes) async {
    await _directory.create(recursive: true);
    final temporary =
        File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<void> _trimToCapacity() async {
    var total = _entries.values.fold(0, (sum, entry) => sum + entry.size);
    if (total <= maxBytes) {
      return;
    }
    final candidates = _entries.values.where((entry) => !entry.pinned).toList()
      ..sort((a, b) => a.lastAccessAt.compareTo(b.lastAccessAt));
    for (final entry in candidates) {
      if (total <= maxBytes) {
        break;
      }
      final file = File('${_directory.path}/${entry.filename}');
      if (await file.exists()) {
        await file.delete();
      }
      _entries.remove(entry.key);
      total -= entry.size;
    }
  }

  Future<void> _saveIndex() {
    final operation = _writeQueue.then((_) async {
      final file = File('${_directory.path}/$_indexFilename');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode([for (final entry in _entries.values) entry.toJson()]),
        flush: true,
      );
      await temporary.rename(file.path);
    });
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  String _key(String url, String variant, String namespace) {
    final source = '$namespace|$variant|$url';
    return Sha1Hash.hex(Uint8List.fromList(utf8.encode(source)));
  }

  String _canonicalUrl(String value) {
    final resolved = ForumUrlResolver.resolve(value);
    final uri = Uri.tryParse(resolved);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '';
    }
    return uri.replace(fragment: '').toString();
  }

  static bool _looksLikeImage(Uint8List bytes, String? mimeType) {
    if (mimeType?.toLowerCase().startsWith('image/') == true) {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return true;
    }
    if (bytes.length >= 6 &&
        (utf8.decode(bytes.sublist(0, 6), allowMalformed: true) == 'GIF87a' ||
            utf8.decode(bytes.sublist(0, 6), allowMalformed: true) ==
                'GIF89a')) {
      return true;
    }
    return bytes.length >= 12 &&
        utf8.decode(bytes.sublist(0, 4), allowMalformed: true) == 'RIFF' &&
        utf8.decode(bytes.sublist(8, 12), allowMalformed: true) == 'WEBP';
  }

  static String _mimeTypeFromBytes(Uint8List bytes) {
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      return 'image/png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49) {
      return 'image/gif';
    }
    return 'image/webp';
  }

  static String _extensionForMime(String mimeType) {
    return switch (mimeType.toLowerCase()) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
  }
}

class _DownloadedForumImage {
  const _DownloadedForumImage({
    required this.bytes,
    required this.mimeType,
    required this.etag,
    required this.lastModified,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? etag;
  final String? lastModified;
}

class _ForumImageEntry {
  _ForumImageEntry({
    required this.key,
    required this.url,
    required this.variant,
    required this.namespace,
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.lastAccessAt,
    required this.etag,
    required this.lastModified,
    required this.pinned,
  });

  final String key;
  final String url;
  final String variant;
  final String namespace;
  final String filename;
  final String mimeType;
  final int size;
  DateTime lastAccessAt;
  final String? etag;
  final String? lastModified;
  bool pinned;

  static _ForumImageEntry? fromJson(JsonMap json) {
    final key = stringValue(json['key']);
    final filename = stringValue(json['filename']);
    final lastAccessAt = dateValue(json['last_access_at']);
    final size = intValue(json['size']);
    if (key.isEmpty || filename.isEmpty || lastAccessAt == null || size <= 0) {
      return null;
    }
    return _ForumImageEntry(
      key: key,
      url: stringValue(json['url']),
      variant: stringValue(json['variant'], 'display'),
      namespace: stringValue(json['namespace'], 'public'),
      filename: filename,
      mimeType: stringValue(json['mime_type'], 'image/jpeg'),
      size: size,
      lastAccessAt: lastAccessAt,
      etag:
          stringValue(json['etag']).isEmpty ? null : stringValue(json['etag']),
      lastModified: stringValue(json['last_modified']).isEmpty
          ? null
          : stringValue(json['last_modified']),
      pinned: boolValue(json['pinned']),
    );
  }

  JsonMap toJson() => {
        'key': key,
        'url': url,
        'variant': variant,
        'namespace': namespace,
        'filename': filename,
        'mime_type': mimeType,
        'size': size,
        'last_access_at': lastAccessAt.toIso8601String(),
        if (etag != null) 'etag': etag,
        if (lastModified != null) 'last_modified': lastModified,
        'pinned': pinned,
      };
}
