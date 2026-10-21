import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/platform/app_paths.dart';

typedef _PlaySoundC = Int32 Function(Pointer<Utf16> pszSound, IntPtr hmod, Uint32 fdwSound);
typedef _PlaySoundDart = int Function(Pointer<Utf16> pszSound, int hmod, int fdwSound);

/// Service providing crisp, low-latency audio feedback for touch, numpad, and POS actions.
/// Uses native winmm PlaySoundW on Windows and afplay on macOS with SystemSound fallback.
class SoundEffectService {
  static final SoundEffectService instance = SoundEffectService._();
  SoundEffectService._();

  bool _enabled = true;
  bool get isEnabled => _enabled;
  set isEnabled(bool value) {
    _enabled = value;
    PosLogger.instance.info('SoundService', 'Sound effects ${value ? "enabled" : "disabled"}');
  }

  bool _initialized = false;
  final Map<String, File> _cachedSoundFiles = {};
  _PlaySoundDart? _winmmPlaySound;
  DynamicLibrary? _winmmLib;

  /// Win32 PlaySound flags:
  /// SND_ASYNC (0x0001) - play asynchronously without blocking
  /// SND_NODEFAULT (0x0002) - silence if file missing
  /// SND_FILENAME (0x00020000) - pszSound is a file path
  static const int _winSndFlags = 0x0001 | 0x0002 | 0x00020000;

  /// Initialize sound files and native audio bindings lazily
  Future<void> initialize() async {
    if (_initialized) return;

    // 1. Initialize Windows winmm binding if on Windows
    if (!kIsWeb && Platform.isWindows) {
      try {
        _winmmLib = DynamicLibrary.open('winmm.dll');
        _winmmPlaySound = _winmmLib!.lookupFunction<_PlaySoundC, _PlaySoundDart>('PlaySoundW');
      } catch (e) {
        PosLogger.instance.warning('SoundService', 'winmm.dll initialization failed: $e');
      }
    }

    // 2. Pre-generate and cache sound WAV files
    try {
      final soundDir = Directory(p.join(AppPaths.instance.tempDir.path, 'pos_sounds'));
      if (!await soundDir.exists()) {
        await soundDir.create(recursive: true);
      }

      _cachedSoundFiles['key_tap'] = await _writeWavIfMissing(
        soundDir,
        'key_tap.wav',
        _generateToneWav(frequency: 1450, durationSeconds: 0.035, volume: 0.35),
      );

      _cachedSoundFiles['button_tap'] = await _writeWavIfMissing(
        soundDir,
        'button_tap.wav',
        _generateToneWav(frequency: 1200, durationSeconds: 0.025, volume: 0.30),
      );

      _cachedSoundFiles['backspace'] = await _writeWavIfMissing(
        soundDir,
        'backspace.wav',
        _generateToneWav(frequency: 850, durationSeconds: 0.040, volume: 0.35),
      );

      _cachedSoundFiles['clear'] = await _writeWavIfMissing(
        soundDir,
        'clear.wav',
        _generateToneWav(frequency: 650, durationSeconds: 0.045, volume: 0.35),
      );

      _cachedSoundFiles['success'] = await _writeWavIfMissing(
        soundDir,
        'success.wav',
        _generateDualToneWav(freq1: 1300, dur1: 0.040, freq2: 1800, dur2: 0.080, volume: 0.40),
      );

      _cachedSoundFiles['error'] = await _writeWavIfMissing(
        soundDir,
        'error.wav',
        _generateToneWav(frequency: 380, durationSeconds: 0.120, volume: 0.45),
      );

      _initialized = true;
      PosLogger.instance.info('SoundService', 'SoundEffectService initialized with ${_cachedSoundFiles.length} sound assets.');
    } catch (e) {
      PosLogger.instance.warning('SoundService', 'Failed to generate sound cache: $e');
    }
  }

  Future<File> _writeWavIfMissing(Directory dir, String filename, Uint8List bytes) async {
    final file = File(p.join(dir.path, filename));
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }

  /// Play audio feedback for a numpad digit (0-9, 00, .)
  void playKeyTap() {
    _playSound('key_tap', fallback: SystemSoundType.click);
  }

  /// Play audio feedback for a standard UI button tap
  void playButtonTap() {
    _playSound('button_tap', fallback: SystemSoundType.click);
  }

  /// Play audio feedback for backspace
  void playBackspace() {
    _playSound('backspace', fallback: SystemSoundType.click);
  }

  /// Play audio feedback for clear (C)
  void playClear() {
    _playSound('clear', fallback: SystemSoundType.click);
  }

  /// Play audio feedback for successful validation or checkout
  void playSuccess() {
    _playSound('success', fallback: SystemSoundType.click);
  }

  /// Play audio feedback for rejection or validation error
  void playError() {
    _playSound('error', fallback: SystemSoundType.alert);
  }

  void _playSound(String soundKey, {SystemSoundType? fallback}) {
    if (!_enabled) return;

    // Trigger universal Flutter system sound immediately
    if (fallback != null) {
      try {
        SystemSound.play(fallback);
      } catch (_) {}
    }

    if (kIsWeb) return;

    // Ensure initialization is started in background
    if (!_initialized) {
      initialize().then((_) {
        _dispatchNativePlay(soundKey);
      });
      return;
    }

    _dispatchNativePlay(soundKey);
  }

  bool suppressProcessSpawnForTesting = false;

  void _dispatchNativePlay(String soundKey) {
    if (suppressProcessSpawnForTesting || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      final file = _cachedSoundFiles[soundKey];
      if (file == null || !file.existsSync()) return;

      if (Platform.isWindows && _winmmPlaySound != null) {
        final pathUtf16 = file.path.toNativeUtf16();
        try {
          _winmmPlaySound!(pathUtf16, 0, _winSndFlags);
        } finally {
          malloc.free(pathUtf16);
        }
      } else if (Platform.isMacOS) {
        // macOS background audio playback
        Process.run('afplay', ['-v', '0.35', file.path]).catchError((_) => ProcessResult(0, 0, '', ''));
      } else if (Platform.isLinux) {
        Process.run('paplay', [file.path]).catchError((_) => ProcessResult(0, 0, '', ''));
      }
    } catch (e) {
      // Non-fatal, never crash the POS for audio
      debugPrint('Audio playback error: $e');
    }
  }

  /// Synthesize a clean, mono 16-bit PCM WAV audio buffer
  static Uint8List _generateToneWav({
    required double frequency,
    required double durationSeconds,
    double volume = 0.4,
    int sampleRate = 22050,
  }) {
    final numSamples = (sampleRate * durationSeconds).round();
    final byteData = ByteData(44 + numSamples * 2);

    // RIFF Header
    byteData.setUint8(0, 0x52); // R
    byteData.setUint8(1, 0x49); // I
    byteData.setUint8(2, 0x46); // F
    byteData.setUint8(3, 0x46); // F
    byteData.setUint32(4, 36 + numSamples * 2, Endian.little);
    byteData.setUint8(8, 0x57);  // W
    byteData.setUint8(9, 0x41);  // A
    byteData.setUint8(10, 0x56); // V
    byteData.setUint8(11, 0x45); // E

    // 'fmt ' Sub-chunk
    byteData.setUint8(12, 0x66); // f
    byteData.setUint8(13, 0x6D); // m
    byteData.setUint8(14, 0x74); // t
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // chunk size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little);  // PCM format (1)
    byteData.setUint16(22, 1, Endian.little);  // Mono (1 channel)
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    byteData.setUint16(32, 2, Endian.little);  // Block align
    byteData.setUint16(34, 16, Endian.little); // 16 bits per sample

    // 'data' Sub-chunk
    byteData.setUint8(36, 0x64); // d
    byteData.setUint8(37, 0x61); // a
    byteData.setUint8(38, 0x74); // t
    byteData.setUint8(39, 0x61); // a
    byteData.setUint32(40, numSamples * 2, Endian.little);

    // Smooth envelope: 3ms fade in, 10ms fade out to avoid speaker clicks
    final attackSamples = (sampleRate * 0.003).round().clamp(1, numSamples);
    final releaseSamples = (sampleRate * 0.010).round().clamp(1, numSamples);

    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      double envelope = 1.0;
      if (i < attackSamples) {
        envelope = i / attackSamples;
      } else if (i >= numSamples - releaseSamples) {
        envelope = (numSamples - i) / releaseSamples;
      }

      final t = i / sampleRate;
      final sample = (sin(2 * pi * frequency * t) * 32767 * volume * envelope).round();
      byteData.setInt16(offset, sample.clamp(-32768, 32767), Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  /// Synthesize a two-tone ascending chime
  static Uint8List _generateDualToneWav({
    required double freq1,
    required double dur1,
    required double freq2,
    required double dur2,
    double volume = 0.4,
    int sampleRate = 22050,
  }) {
    final samples1 = (sampleRate * dur1).round();
    final samples2 = (sampleRate * dur2).round();
    final totalSamples = samples1 + samples2;
    final byteData = ByteData(44 + totalSamples * 2);

    // RIFF Header
    byteData.setUint8(0, 0x52);
    byteData.setUint8(1, 0x49);
    byteData.setUint8(2, 0x46);
    byteData.setUint8(3, 0x46);
    byteData.setUint32(4, 36 + totalSamples * 2, Endian.little);
    byteData.setUint8(8, 0x57);
    byteData.setUint8(9, 0x41);
    byteData.setUint8(10, 0x56);
    byteData.setUint8(11, 0x45);

    // 'fmt ' Sub-chunk
    byteData.setUint8(12, 0x66);
    byteData.setUint8(13, 0x6D);
    byteData.setUint8(14, 0x74);
    byteData.setUint8(15, 0x20);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);

    // 'data' Sub-chunk
    byteData.setUint8(36, 0x64);
    byteData.setUint8(37, 0x61);
    byteData.setUint8(38, 0x74);
    byteData.setUint8(39, 0x61);
    byteData.setUint32(40, totalSamples * 2, Endian.little);

    int offset = 44;
    // Tone 1
    final attack1 = (sampleRate * 0.003).round().clamp(1, samples1);
    final release1 = (sampleRate * 0.005).round().clamp(1, samples1);
    for (int i = 0; i < samples1; i++) {
      double envelope = 1.0;
      if (i < attack1) {
        envelope = i / attack1;
      } else if (i >= samples1 - release1) {
        envelope = (samples1 - i) / release1;
      }
      final t = i / sampleRate;
      final sample = (sin(2 * pi * freq1 * t) * 32767 * volume * envelope).round();
      byteData.setInt16(offset, sample.clamp(-32768, 32767), Endian.little);
      offset += 2;
    }

    // Tone 2
    final attack2 = (sampleRate * 0.003).round().clamp(1, samples2);
    final release2 = (sampleRate * 0.015).round().clamp(1, samples2);
    for (int i = 0; i < samples2; i++) {
      double envelope = 1.0;
      if (i < attack2) {
        envelope = i / attack2;
      } else if (i >= samples2 - release2) {
        envelope = (samples2 - i) / release2;
      }
      final t = i / sampleRate;
      final sample = (sin(2 * pi * freq2 * t) * 32767 * volume * envelope).round();
      byteData.setInt16(offset, sample.clamp(-32768, 32767), Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }
}
