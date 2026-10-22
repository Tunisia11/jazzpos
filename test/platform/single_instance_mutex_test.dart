// ignore_for_file: depend_on_referenced_packages
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef CreateMutexC = IntPtr Function(
  Pointer<Void> lpMutexAttributes,
  Int32 bInitialOwner,
  Pointer<Utf16> lpName,
);
typedef CreateMutexDart = int Function(
  Pointer<Void> lpMutexAttributes,
  int bInitialOwner,
  Pointer<Utf16> lpName,
);

typedef GetLastErrorC = Uint32 Function();
typedef GetLastErrorDart = int Function();

typedef CloseHandleC = Int32 Function(IntPtr hObject);
typedef CloseHandleDart = int Function(int hObject);

void main() {
  test('Single-instance named mutex logic in main.cpp is present', () {
    final mainCpp = File('windows/runner/main.cpp');
    expect(mainCpp.existsSync(), isTrue);
    final content = mainCpp.readAsStringSync();
    expect(content.contains('kSingleInstanceMutexName'), isTrue);
    expect(content.contains('CreateMutexW'), isTrue);
    expect(content.contains('ERROR_ALREADY_EXISTS'), isTrue);
    expect(content.contains('ActivateExistingWindow'), isTrue);
  });

  test('Windows Win32 Named Mutex creates and detects duplicate instance', () {
    if (!Platform.isWindows) return;

    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final createMutex = kernel32
        .lookupFunction<CreateMutexC, CreateMutexDart>('CreateMutexW');
    final getLastError = kernel32
        .lookupFunction<GetLastErrorC, GetLastErrorDart>('GetLastError');
    final closeHandle = kernel32
        .lookupFunction<CloseHandleC, CloseHandleDart>('CloseHandle');

    final mutexName =
        'Local\\TracePOS_Test_SingleInstance_${DateTime.now().millisecondsSinceEpoch}'
            .toNativeUtf16();

    // 1. First instance acquires mutex
    final hMutex1 = createMutex(nullptr, 1, mutexName);
    expect(hMutex1, isNot(0));
    final err1 = getLastError();
    expect(err1, isNot(183)); // 183 = ERROR_ALREADY_EXISTS

    // 2. Second instance attempts to acquire the same named mutex
    final hMutex2 = createMutex(nullptr, 1, mutexName);
    final err2 = getLastError();
    expect(err2, equals(183)); // MUST return ERROR_ALREADY_EXISTS (183)

    // Cleanup
    if (hMutex2 != 0) closeHandle(hMutex2);
    if (hMutex1 != 0) closeHandle(hMutex1);
    calloc.free(mutexName);
  });
}
