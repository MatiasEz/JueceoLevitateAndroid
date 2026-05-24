import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

const googleDriveFileScope = 'https://www.googleapis.com/auth/drive.file';

class GoogleDriveUploadedFile {
  GoogleDriveUploadedFile({
    required this.id,
    required this.name,
    this.webViewLink,
  });

  final String id;
  final String name;
  final String? webViewLink;
}

class GoogleDriveExportSummary {
  GoogleDriveExportSummary({
    required this.rootFolderName,
    required this.uploadedFiles,
  });

  final String rootFolderName;
  final List<GoogleDriveUploadedFile> uploadedFiles;
}

class GoogleDriveService {
  GoogleDriveService({
    this.clientId,
    this.serverClientId,
  });

  final String? clientId;
  final String? serverClientId;
  static Future<void>? _initialization;

  Future<GoogleDriveUploadedFile> uploadPdf({
    required Uint8List bytes,
    required String fileName,
    required List<String> folderPath,
  }) async {
    final headers = await _authorizationHeaders();
    String? parentId;
    for (final folderName in folderPath) {
      parentId = await _ensureFolder(headers, folderName, parentId: parentId);
    }
    return _uploadFile(
      headers,
      bytes: bytes,
      fileName: fileName,
      parentId: parentId,
    );
  }

  Future<Map<String, String>> _authorizationHeaders() async {
    await _ensureInitialized();
    final signIn = GoogleSignIn.instance;
    GoogleSignInAccount? account;
    final lightweight = signIn.attemptLightweightAuthentication();
    if (lightweight != null) {
      account = await lightweight;
    }
    account ??= await signIn.authenticate(
      scopeHint: const [googleDriveFileScope],
    );
    final headers = await account.authorizationClient.authorizationHeaders(
      const [googleDriveFileScope],
      promptIfNecessary: true,
    );
    if (headers == null) {
      throw StateError('No se autorizó el acceso a Google Drive.');
    }
    return headers;
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= GoogleSignIn.instance.initialize(
      clientId: _emptyToNull(clientId),
      serverClientId: _emptyToNull(serverClientId),
    );
  }

  Future<String> _ensureFolder(
    Map<String, String> authHeaders,
    String name, {
    String? parentId,
  }) async {
    final existing = await _findFolder(authHeaders, name, parentId: parentId);
    if (existing != null) return existing;
    final response = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files'),
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({
        'name': name,
        'mimeType': 'application/vnd.google-apps.folder',
        if (parentId != null) 'parents': [parentId],
      }),
    );
    _throwIfFailed(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  Future<String?> _findFolder(
    Map<String, String> authHeaders,
    String name, {
    String? parentId,
  }) async {
    final queryParts = [
      "name='${_escapeDriveQuery(name)}'",
      "mimeType='application/vnd.google-apps.folder'",
      'trashed=false',
      if (parentId != null) "'${_escapeDriveQuery(parentId)}' in parents",
    ];
    final response = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': queryParts.join(' and '),
        'spaces': 'drive',
        'fields': 'files(id,name)',
        'pageSize': '1',
      }),
      headers: authHeaders,
    );
    _throwIfFailed(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final files = json['files'] as List<dynamic>? ?? const [];
    if (files.isEmpty) return null;
    return (files.first as Map<String, dynamic>)['id'] as String?;
  }

  Future<GoogleDriveUploadedFile> _uploadFile(
    Map<String, String> authHeaders, {
    required Uint8List bytes,
    required String fileName,
    required String? parentId,
  }) async {
    final boundary = 'levitate_${DateTime.now().microsecondsSinceEpoch}';
    final metadata = {
      'name': fileName,
      'mimeType': 'application/pdf',
      if (parentId != null) 'parents': [parentId],
    };
    final body = <int>[
      ...utf8.encode('--$boundary\r\n'),
      ...utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
      ...utf8.encode(jsonEncode(metadata)),
      ...utf8.encode('\r\n--$boundary\r\n'),
      ...utf8.encode('Content-Type: application/pdf\r\n\r\n'),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final response = await http.post(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
        'uploadType': 'multipart',
        'fields': 'id,name,webViewLink',
      }),
      headers: {
        ...authHeaders,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: Uint8List.fromList(body),
    );
    _throwIfFailed(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return GoogleDriveUploadedFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? fileName,
      webViewLink: json['webViewLink'] as String?,
    );
  }

  void _throwIfFailed(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(response.statusCode, response.body);
    }
  }

  String _escapeDriveQuery(String value) {
    return value.replaceAll('\\', r'\\').replaceAll("'", r"\'");
  }

  String? _emptyToNull(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}

class GoogleDriveException implements Exception {
  GoogleDriveException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'Google Drive error $statusCode: $body';
}
