import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;

import '../models/detection_result.dart';

enum ApiErrorType { timeout, noInternet, serverError, parseError, unknown }

class ApiException implements Exception {
  final ApiErrorType type;
  final String message;
  ApiException(this.type, this.message);
  @override
  String toString() => 'ApiException($type): $message';
}

class ApiService {
  // 컴퓨터의 Wi-Fi IP 주소로 변경하여 스마트폰에서 접속 가능하도록 설정
  static const String serverBaseUrl = 'http://10.0.24.103:8001';
  static const Duration _requestTimeout = Duration(seconds: 30);

  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  Uri get _predictUri => Uri.parse('$serverBaseUrl/predict/objects-distance');

  Future<PredictionResponse?> predictFromXFilePath(
    String imagePath, {
    double dangerThreshold = 1.5,
    double referenceDepth = 1.0,
  }) async {
    try {
      final originalFile = File(imagePath);
      final originalBytes = await originalFile.readAsBytes();

      final compressedBytes = await compute(_processImage, originalBytes);

      if (compressedBytes == null) {
        return null;
      }

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final tempFilePath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}temp_resized_$timestamp.jpg';
      final tempFile = File(tempFilePath);
      await tempFile.writeAsBytes(compressedBytes, flush: true);

      final request = http.MultipartRequest('POST', _predictUri)
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            tempFile.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      request.fields['danger_threshold'] = dangerThreshold.toString();
      request.fields['reference_depth'] = referenceDepth.toString();

      return await _sendAndParse(request);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(ApiErrorType.unknown, e.toString());
    }
  }

  Future<PredictionResponse?> predictFromBytes(
    Uint8List imageBytes, {
    String filename = 'frame.jpg',
    double dangerThreshold = 1.5,
    double referenceDepth = 1.0,
  }) async {
    try {
      final request = http.MultipartRequest('POST', _predictUri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            imageBytes,
            filename: filename,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      request.fields['danger_threshold'] = dangerThreshold.toString();
      request.fields['reference_depth'] = referenceDepth.toString();

      return await _sendAndParse(request);
    } catch (_) {
      return null;
    }
  }

  Future<PredictionResponse?> _sendAndParse(
    http.MultipartRequest request,
  ) async {
    try {
      final streamedResponse = await _client
          .send(request)
          .timeout(_requestTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        print('🔥 [API Server Error] 서버 응답 코드 에러: ${response.statusCode}');
        print('🔥 응답 본문: ${response.body}');
        throw ApiException(
          ApiErrorType.serverError,
          '상태코드: ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || !decoded.containsKey('display_objects')) {
        print('🔥 [API Parse Error] JSON이 예상된 형태(Map with "display_objects")가 아닙니다.');
        throw ApiException(ApiErrorType.parseError, '잘못된 JSON 형식');
      }

      return PredictionResponse.fromJson(decoded);
    } on TimeoutException {
      throw ApiException(ApiErrorType.timeout, '서버 응답 지연');
    } on SocketException {
      throw ApiException(ApiErrorType.noInternet, '네트워크 연결 끊김');
    } catch (e) {
      print('🔥 [API Send/Parse Error] _sendAndParse 실패: $e');
      if (e is ApiException) rethrow;
      throw ApiException(ApiErrorType.unknown, e.toString());
    }
  }

  // updateCalibration removed as it is now handled locally via SharedPreferences

  void dispose() {
    _client.close();
  }
}

// 최상단 레벨에 배치해야 compute 함수가 독립된 Isolate에서 정상 작동합니다.
Uint8List? _processImage(Uint8List imageBytes) {
  try {
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) return null;
    final resizedImage = img.copyResize(decodedImage, width: 640);
    return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 70));
  } catch (e) {
    return null;
  }
}
