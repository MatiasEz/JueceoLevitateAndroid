import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const defaultAppUpdateManifestUrl =
    'https://matiasez.github.io/JueceoLevitateAndroid/latest.json';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.required,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final Uri apkUrl;
  final bool required;
  final String notes;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final versionCode = _intFromJson(json['versionCode']);
    final versionName = (json['versionName'] as String?)?.trim() ?? '';
    final apkUrl = Uri.parse((json['apkUrl'] as String?)?.trim() ?? '');
    if (versionCode <= 0) {
      throw const FormatException('versionCode invalido');
    }
    if (!apkUrl.hasScheme || !apkUrl.hasAuthority) {
      throw const FormatException('apkUrl invalida');
    }

    return AppUpdateInfo(
      versionCode: versionCode,
      versionName: versionName.isEmpty ? versionCode.toString() : versionName,
      apkUrl: apkUrl,
      required: json['required'] == true,
      notes: (json['notes'] as String?)?.trim() ?? '',
    );
  }

  static int _intFromJson(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}

class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    Uri? manifestUri,
  })  : _client = client ?? http.Client(),
        manifestUri = manifestUri ??
            Uri.parse(const String.fromEnvironment(
              'APP_UPDATE_MANIFEST_URL',
              defaultValue: defaultAppUpdateManifestUrl,
            ));

  static const _channel =
      MethodChannel('com.levitate.jueceocoreografias/updater');

  final http.Client _client;
  final Uri manifestUri;

  Future<AppUpdateInfo?> fetchAvailableUpdate() async {
    if (!Platform.isAndroid) return null;

    final currentVersionCode = await _currentVersionCode();
    final response = await _client.get(manifestUri, headers: const {
      'Cache-Control': 'no-cache'
    }).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw HttpException(
        'No se pudo consultar actualizaciones (${response.statusCode})',
        uri: manifestUri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('latest.json no es un objeto JSON valido');
    }

    final update = AppUpdateInfo.fromJson(decoded);
    return update.versionCode > currentVersionCode ? update : null;
  }

  Future<File> downloadApk(
    AppUpdateInfo update, {
    required ValueChangedDouble onProgress,
  }) async {
    final request = http.Request('GET', update.apkUrl)
      ..headers['User-Agent'] = 'LevitateAndroidUpdater';
    final response = await _client.send(request).timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode != 200) {
      throw HttpException(
        'No se pudo descargar el APK (${response.statusCode})',
        uri: update.apkUrl,
      );
    }

    final directory =
        await Directory('${Directory.systemTemp.path}/levitate_updates')
            .create(recursive: true);
    final file = File('${directory.path}/levitate-${update.versionCode}.apk');
    final sink = file.openWrite();
    var receivedBytes = 0;
    final totalBytes = response.contentLength;

    try {
      await for (final chunk in response.stream) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        if (totalBytes != null && totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      }
    } finally {
      await sink.close();
    }

    onProgress(1);
    return file;
  }

  Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  Future<void> openInstallSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openInstallSettings');
  }

  Future<void> installApk(File apkFile) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('installApk', {'path': apkFile.path});
  }

  Future<int> _currentVersionCode() async {
    return await _channel.invokeMethod<int>('getVersionCode') ?? 0;
  }

  void close() => _client.close();
}

typedef ValueChangedDouble = void Function(double value);
