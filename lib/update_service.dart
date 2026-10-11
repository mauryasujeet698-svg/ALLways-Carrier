import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AllwaysUpdateGate extends StatefulWidget {
  final Widget child;
  final String repo;
  final String packageChannel;
  final String assetName;
  final String manifestDoc;

  const AllwaysUpdateGate({
    super.key,
    required this.child,
    required this.repo,
    required this.packageChannel,
    required this.assetName,
    required this.manifestDoc,
  });

  @override
  State<AllwaysUpdateGate> createState() => _AllwaysUpdateGateState();
}

class _AllwaysUpdateGateState extends State<AllwaysUpdateGate> {
  Timer? _timer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _manifestSub;
  String? version;
  String? url;
  String? expectedSha256;
  String notes = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _listenForPublishedManifest();
    _check();
    // Firestore is the primary push-updated manifest. Poll GitHub only as a
    // fallback for installations that have not yet received a manifest.
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _manifestSub?.cancel();
    super.dispose();
  }

  void _listenForPublishedManifest() {
    _manifestSub = FirebaseFirestore.instance
        .collection('settings')
        .doc(widget.manifestDoc)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data != null) _applyManifest(data);
    }, onError: (_) {});
  }

  List<int> _parts(String value) => value
      .replaceFirst(RegExp(r'^[^0-9]*'), '')
      .split('.')
      .map((part) => int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '0') ?? 0)
      .toList();

  bool _newer(String remote, String local) {
    final a = _parts(remote), b = _parts(local);
    for (var i = 0; i < 3; i++) {
      final aa = i < a.length ? a[i] : 0;
      final bb = i < b.length ? b[i] : 0;
      if (aa != bb) return aa > bb;
    }
    return false;
  }

  String _normalDigest(dynamic value) =>
      (value ?? '').toString().trim().toLowerCase().replaceFirst(RegExp(r'^sha256:'), '');

  bool _validManifest(Map<String, dynamic> data) {
    final remote = (data['version'] ?? '').toString().trim();
    final apkUrl = (data['apkUrl'] ?? data['url'] ?? '').toString().trim();
    final digest = _normalDigest(data['sha256'] ?? data['digest']);
    final uri = Uri.tryParse(apkUrl);
    return remote.isNotEmpty &&
        uri != null &&
        uri.scheme == 'https' &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(digest);
  }

  Future<void> _applyManifest(Map<String, dynamic> data) async {
    if (!_validManifest(data)) return;
    final remote = (data['version'] ?? '').toString().trim();
    final apkUrl = (data['apkUrl'] ?? data['url'] ?? '').toString().trim();
    final digest = _normalDigest(data['sha256'] ?? data['digest']);
    final info = await PackageInfo.fromPlatform();
    if (!mounted || !_newer(remote, info.version)) return;
    setState(() {
      version = remote;
      url = apkUrl;
      expectedSha256 = digest;
      notes = (data['notes'] ?? '').toString();
    });
  }

  Future<void> _check() async {
    if (busy) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc(widget.manifestDoc)
          .get()
          .timeout(const Duration(seconds: 8));
      final manifest = snapshot.data();
      if (manifest != null && _validManifest(manifest)) {
        await _applyManifest(manifest);
        return;
      }
    } catch (_) {}

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/${widget.repo}/releases/tags/allways-latest'),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'ALLways-Updater',
        },
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final release = jsonDecode(response.body);
      if (release is! Map) return;
      final name = (release['name'] ?? '').toString();
      final remote = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(name)?.group(1) ?? '';
      final assets = release['assets'] is List ? release['assets'] as List : const [];
      for (final asset in assets) {
        if (asset is! Map || (asset['name'] ?? '').toString() != widget.assetName) continue;
        final apkUrl = (asset['browser_download_url'] ?? '').toString().trim();
        final digest = _normalDigest(asset['digest']);
        await _applyManifest({
          'version': remote,
          'apkUrl': apkUrl,
          'sha256': digest,
          'notes': (release['body'] ?? '').toString(),
        });
        return;
      }
    } catch (_) {}
  }

  Future<void> _install() async {
    final downloadUrl = url;
    final expected = expectedSha256;
    if (downloadUrl == null || downloadUrl.isEmpty ||
        expected == null || expected.isEmpty || busy) return;

    setState(() => busy = true);
    final progress = ValueNotifier<double>(0);
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('Updating ALLways to ${version ?? ''}'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: value > 0 ? value : null),
                const SizedBox(height: 12),
                Text(value > 0
                    ? 'Downloading ${(value * 100).toStringAsFixed(0)}%'
                    : 'Starting secure download…'),
              ],
            ),
          ),
        ),
      );
      final file = File('${Directory.systemTemp.path}/allways_${DateTime.now().millisecondsSinceEpoch}.apk');
      final cacheBust = downloadUrl.contains('?') ? '&' : '?';
      await Dio().download(
        '$downloadUrl${cacheBust}cacheBust=${DateTime.now().millisecondsSinceEpoch}',
        file.path,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
      );
      final actual = sha256.convert(await file.readAsBytes()).toString().toLowerCase();
      if (actual != expected) {
        try { await file.delete(); } catch (_) {}
        throw StateError('Downloaded update failed SHA-256 verification.');
      }
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();

      final result = await MethodChannel(widget.packageChannel)
          .invokeMethod<String>('installApk', {'path': file.path});
      if (result == 'permission_required') {
        await MethodChannel(widget.packageChannel).invokeMethod('openInstallSettings');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allow ALLways to install updates, then tap UPDATE again.')),
          );
        }
      } else if (result != 'started' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start installation: ${result ?? 'unknown error'}')),
        );
      }
    } catch (error) {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: ${error.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      progress.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (version == null) return widget.child;
    final cleanNotes = notes.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Material(
            elevation: 6,
            color: Theme.of(context).colorScheme.primaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.system_update),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('New ALLways update available', style: TextStyle(fontWeight: FontWeight.w900)),
                          Text(
                            'Version $version is ready${cleanNotes.isNotEmpty ? ' • $cleanNotes' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(onPressed: busy ? null : _install, child: const Text('UPDATE')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
