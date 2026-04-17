import 'package:flutter/material.dart';

import '../services/api_service.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _dRelController = TextEditingController();

  double? _p1Rel;
  double? _p2Rel;
  bool _isSubmitting = false;
  String _statusMessage = '현재 상대 깊이(d_rel)를 입력하고 1m/3m 버튼을 순서대로 눌러주세요.';

  @override
  void dispose() {
    _dRelController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  void _savePoint1() {
    final value = double.tryParse(_dRelController.text.trim());
    if (value == null || value <= 0) {
      setState(() {
        _statusMessage = '유효한 d_rel 값을 입력해 주세요. (예: 0.82)';
      });
      return;
    }
    setState(() {
      _p1Rel = value;
      _statusMessage = '1m 지점이 저장되었습니다. 이제 3m 지점으로 이동해 값을 입력하세요.';
    });
  }

  Future<void> _savePoint2AndApply() async {
    final value = double.tryParse(_dRelController.text.trim());
    if (value == null || value <= 0) {
      setState(() {
        _statusMessage = '유효한 d_rel 값을 입력해 주세요. (예: 0.31)';
      });
      return;
    }
    if (_p1Rel == null) {
      setState(() {
        _statusMessage = '먼저 [1m 저장] 버튼을 눌러주세요.';
      });
      return;
    }

    setState(() {
      _p2Rel = value;
      _isSubmitting = true;
      _statusMessage = '보정값을 서버에 적용하는 중입니다...';
    });

    final result = await _apiService.updateCalibration(
      p1Rel: _p1Rel!,
      p1M: 1.0,
      p2Rel: _p2Rel!,
      p2M: 3.0,
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      if (result == null) {
        _statusMessage = '보정 실패: 서버 연결을 확인해 주세요.';
        return;
      }
      final a = result['A'];
      final b = result['B'];
      _statusMessage = '보정 완료! A=$a, B=$b';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('거리 보정 설정')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '1) 1m 지점에서 d_rel 입력 후 [1m 저장]\n'
              '2) 3m 지점에서 d_rel 입력 후 [3m 저장 + 보정 적용]',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _dRelController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '현재 상대 깊이 d_rel',
                border: OutlineInputBorder(),
                hintText: '예: 0.82',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _savePoint1,
              child: Text(_p1Rel == null ? '1m 저장' : '1m 저장됨 ($_p1Rel)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _savePoint2AndApply,
              child: Text(
                _isSubmitting ? '보정 적용 중...' : '3m 저장 + 보정 적용',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 14, color: Colors.lightGreenAccent),
            ),
          ],
        ),
      ),
    );
  }
}
