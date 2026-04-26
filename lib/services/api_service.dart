import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;

import '../models/detection_result.dart';

class ApiService {
  // 컴퓨터의 Wi-Fi IP 주소로 변경하여 스마트폰에서 접속 가능하도록 설정
  static const String serverBaseUrl = 'http://192.168.150.130:8001';
  static const Duration _requestTimeout = Duration(seconds: 5);

  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  Uri get _predictUri => Uri.parse('$serverBaseUrl/predict/objects-distance');
  Uri get _calibrationUri => Uri.parse('$serverBaseUrl/calibration');

  Future<List<DetectionResult>?> predictFromXFilePath(String imagePath) async {
    try {
      final originalFile = File(imagePath);
      final originalBytes = await originalFile.readAsBytes();

      // 무거운 이미지 처리 작업을 Isolate(백그라운드 스레드)로 분리하여 UI 멈춤 현상(과부하) 방지
      final compressedBytes = await compute(_processImage, originalBytes);

      if (compressedBytes == null) {
        print('🔥 [Image Process Error] 이미지 처리 실패');
        return null;
      }

      final originalSizeKb = originalBytes.length / 1024;
      final compressedSizeKb = compressedBytes.length / 1024;
      print(
        '📦 [Image Compress (Isolate)] ${originalSizeKb.toStringAsFixed(1)}KB -> ${compressedSizeKb.toStringAsFixed(1)}KB',
      );

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

      return await _sendAndParse(request);
    } catch (e) {
      // 💡 어떤 에러 때문에 터졌는지 터미널에 빨간 글씨로 출력!
      print('🔥 [API Request Error] predictFromXFilePath 실패: $e');
      return null;
    }
  }

  Future<List<DetectionResult>?> predictFromBytes(
    Uint8List imageBytes, {
    String filename = 'frame.jpg',
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

      return await _sendAndParse(request);
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<DetectionResult>?> _sendAndParse(
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
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || !decoded.containsKey('objects')) {
        print('🔥 [API Parse Error] JSON이 예상된 형태(Map with "objects")가 아닙니다.');
        return null;
      }

      final objectsList = decoded['objects'] as List;

      return objectsList
          .whereType<Map>()
          .map((item) => DetectionResult.fromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      // 타임아웃이나 파싱 에러 등을 모두 여기서 잡아서 출력
      print('🔥 [API Send/Parse Error] _sendAndParse 실패: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateCalibration({
    required double p1Rel,
    required double p1M,
    required double p2Rel,
    required double p2M,
  }) async {
    try {
      final response = await _client
          .post(
            _calibrationUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'p1_rel': p1Rel,
              'p1_m': p1M,
              'p2_rel': p2Rel,
              'p2_m': p2M,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        print('🔥 [Calibration Error] 상태코드: ${response.statusCode}');
        print('🔥 응답 본문: ${response.body}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        print('🔥 [Calibration Parse Error] 응답이 Map 형태가 아닙니다.');
        return null;
      }
      return decoded;
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } on FormatException {
      return null;
    } catch (e) {
      print('🔥 [Calibration Request Error] updateCalibration 실패: $e');
      return null;
    }
  }

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
