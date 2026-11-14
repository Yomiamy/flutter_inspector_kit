import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:http/http.dart' as http;

/// Demonstrates `captureHttpClient: true`: traffic that never passes through
/// [FlutterInspectorDioInterceptor] still shows up in the Network tab, marked
/// with the `httpClient` origin.
///
/// The Dio requests in `NetworkDemo` carry `sourceDio`, so they stay a single
/// `dio` entry instead of being recorded twice.
class HttpClientDemo {
  HttpClientDemo(this._inspector);

  final FlutterInspector _inspector;

  // No interceptor: only the HttpClient layer sees this Dio's requests.
  final Dio _plainDio = Dio();

  /// `package:http` goes through dart:io's HttpClient (IOClient).
  Future<void> fetchWithPackageHttp() async {
    try {
      final response = await http.get(Uri.parse('https://httpbin.org/json'));
      _inspector.log(
        'package:http request finished: ${response.statusCode}',
        level: LogLevel.info,
      );
    } on Exception catch (e, stackTrace) {
      _inspector.log(
        'package:http request failed: $e',
        level: LogLevel.error,
        stackTrace: stackTrace.toString(),
      );
    }
  }

  /// A Dio instance without the inspector's interceptor.
  Future<void> fetchWithPlainDio() async {
    try {
      await _plainDio.get('https://httpbin.org/get');
      _inspector.log('Plain Dio request finished', level: LogLevel.info);
    } on DioException catch (e, stackTrace) {
      _inspector.log(
        'Plain Dio request failed: $e',
        level: LogLevel.error,
        stackTrace: stackTrace.toString(),
      );
    }
  }

  /// `Image.network` downloads through HttpClient; open the entry in the
  /// Network tab to see the Response Preview.
  void showNetworkImage(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Image.network'),
        content: Image.network(
          'https://httpbin.org/image/png',
          errorBuilder: (context, error, stackTrace) =>
              Text('Image failed to load: $error'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
