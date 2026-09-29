import 'dart:async';
import 'package:app_account/app_account.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:url_launcher/url_launcher.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';

class FilesService {
  FilesService({required this.invoke, http.Client? client})
    : _client = client ?? http.Client();
  factory FilesService.account(AccountClient account) => FilesService(
    invoke: (body) async {
      try {
        final response = await account.invokeFunction(
          'pomodoist-files',
          body: body,
        );
        if (response.data is! Map) {
          throw const FileFailure('storage_unavailable');
        }
        final data = Map<String, dynamic>.from(response.data as Map);
        if (response.status >= 400 || data['error'] != null) {
          throw FileFailure(data['code']?.toString() ?? 'storage_unavailable');
        }
        return data;
      } on FunctionException catch (error) {
        throw FileFailure(
          error.details is Map
              ? (error.details as Map)['code']?.toString() ??
                    'storage_unavailable'
              : 'storage_unavailable',
        );
      }
    },
  );
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) invoke;
  final http.Client _client;
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> args = const {},
  ]) =>
      invoke({'action': action, ...args}).timeout(const Duration(seconds: 30));
  String contentType(XFile file) =>
      (file.mimeType != 'application/octet-stream' ? file.mimeType : null) ??
      switch (file.name.split('.').last.toLowerCase()) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'avif' => 'image/avif',
        'pdf' => 'application/pdf',
        'txt' => 'text/plain',
        'csv' => 'text/csv',
        'svg' => 'image/svg+xml',
        'html' || 'htm' => 'text/html',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'pptx' =>
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        _ => 'application/octet-stream',
      };
  Future<XFile?> pick() => openFile();
  Future<void> upload(
    XFile file,
    Uri url,
    String contentType,
    int size,
    void Function(double) progress,
  ) async {
    final request = http.StreamedRequest('PUT', url)..contentLength = size;
    request.headers.addAll({'content-type': contentType, 'x-upsert': 'false'});
    late http.StreamedResponse result;
    var sent = 0;
    await Future.wait<void>([
      _client.send(request).then<void>((response) {
        result = response;
      }),
      () async {
        try {
          await request.sink.addStream(
            file.openRead().map((chunk) {
              sent += chunk.length;
              progress(size == 0 ? 1 : sent / size);
              return chunk;
            }),
          );
        } finally {
          await request.sink.close();
        }
      }(),
    ], eagerError: true).timeout(const Duration(minutes: 3));
    await result.stream.drain<void>().timeout(const Duration(seconds: 30));
    if (result.statusCode != 409 &&
        (result.statusCode < 200 || result.statusCode >= 300)) {
      throw const FileFailure('upload_failed');
    }
  }

  Future<void> open(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const FileFailure('invalid_response');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const FileFailure('download_failed');
    }
  }

  void dispose() => _client.close();
}
