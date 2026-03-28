import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum VideoRenderStatus { idle, queued, rendering, ready, failed }

class VideoRenderState {
  final VideoRenderStatus status;
  final String? jobId;
  final String? outputUrl;
  final String? error;

  const VideoRenderState({
    this.status = VideoRenderStatus.idle,
    this.jobId,
    this.outputUrl,
    this.error,
  });

  VideoRenderState copyWith({
    VideoRenderStatus? status,
    String? jobId,
    String? outputUrl,
    String? error,
  }) =>
      VideoRenderState(
        status: status ?? this.status,
        jobId: jobId ?? this.jobId,
        outputUrl: outputUrl ?? this.outputUrl,
        error: error ?? this.error,
      );

  bool get isLoading =>
      status == VideoRenderStatus.queued ||
      status == VideoRenderStatus.rendering;
}

class VideoRenderNotifier extends Notifier<VideoRenderState> {
  static const _pollIntervalSeconds = 3;
  static const _maxPollAttempts = 20;

  Timer? _pollTimer;
  int _pollAttempts = 0;

  @override
  VideoRenderState build() => const VideoRenderState();

  Future<void> triggerWorkoutVideo({
    required String compositionId,
    required Map<String, dynamic> inputProps,
  }) async {
    state = const VideoRenderState(status: VideoRenderStatus.queued);
    _pollAttempts = 0;

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Not authenticated');

      final response = await Supabase.instance.client.functions.invoke(
        'video-render-trigger',
        body: {'compositionId': compositionId, 'inputProps': inputProps},
      );

      if (response.status != 200) {
        throw Exception('Trigger failed: ${response.data}');
      }

      final jobId = response.data['jobId'] as String;
      state = state.copyWith(jobId: jobId);
      _startPolling(jobId);
    } catch (e) {
      state = state.copyWith(
        status: VideoRenderStatus.failed,
        error: e.toString(),
      );
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: _pollIntervalSeconds),
      (_) => _poll(jobId),
    );
  }

  Future<void> _poll(String jobId) async {
    _pollAttempts++;
    if (_pollAttempts >= _maxPollAttempts) {
      _pollTimer?.cancel();
      state = state.copyWith(
        status: VideoRenderStatus.failed,
        error: 'Render timed out',
      );
      return;
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'video-status',
        queryParameters: {'jobId': jobId},
        method: HttpMethod.get,
      );

      if (response.status != 200) return;

      final data = response.data as Map<String, dynamic>;
      final statusStr = data['status'] as String?;

      switch (statusStr) {
        case 'ready':
          _pollTimer?.cancel();
          state = state.copyWith(
            status: VideoRenderStatus.ready,
            outputUrl: data['output_url'] as String?,
          );
        case 'failed':
          _pollTimer?.cancel();
          state = state.copyWith(
            status: VideoRenderStatus.failed,
            error: 'Render failed',
          );
        case 'rendering':
          state = state.copyWith(status: VideoRenderStatus.rendering);
        default:
          break;
      }
    } catch (_) {
      // Network blip — keep polling
    }
  }

  void reset() {
    _pollTimer?.cancel();
    _pollAttempts = 0;
    state = const VideoRenderState();
  }
}

final videoRenderNotifierProvider =
    NotifierProvider<VideoRenderNotifier, VideoRenderState>(
  VideoRenderNotifier.new,
);
