#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <tlhelp32.h>

#include "flutter_window.h"
#include "utils.h"

constexpr const wchar_t kSingleInstanceMutexName[] = L"Local\\JazzPOS_SingleInstance_Mutex";

bool ActivateExistingWindow() {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
  if (hwnd != nullptr) {
    if (::IsIconic(hwnd)) {
      ::ShowWindow(hwnd, SW_RESTORE);
    } else {
      ::ShowWindow(hwnd, SW_SHOW);
    }
    ::SetForegroundWindow(hwnd);
    ::BringWindowToTop(hwnd);
    return true;
  }
  return false;
}

void TerminateGhostInstances() {
  DWORD currentPid = ::GetCurrentProcessId();
  HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return;

  PROCESSENTRY32W entry;
  entry.dwSize = sizeof(entry);

  if (::Process32FirstW(snapshot, &entry)) {
    do {
      if (entry.th32ProcessID != currentPid &&
          (_wcsicmp(entry.szExeFile, L"jazzpos.exe") == 0 ||
           _wcsicmp(entry.szExeFile, L"Trace POS.exe") == 0)) {
        HANDLE hProc = ::OpenProcess(PROCESS_TERMINATE, FALSE, entry.th32ProcessID);
        if (hProc != nullptr) {
          ::TerminateProcess(hProc, 0);
          ::CloseHandle(hProc);
        }
      }
    } while (::Process32NextW(snapshot, &entry));
  }

  ::CloseHandle(snapshot);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE hMutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (hMutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (ActivateExistingWindow()) {
      ::CloseHandle(hMutex);
      return EXIT_SUCCESS;
    }
    // If no existing window was found, the running process is a ghost/zombie without UI.
    // Terminate ghost instances and take over to ensure the user is never locked out.
    ::CloseHandle(hMutex);
    hMutex = nullptr;
    TerminateGhostInstances();
    ::Sleep(200);
    hMutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"jazzpos", origin, size)) {
    if (hMutex != nullptr) {
      ::ReleaseMutex(hMutex);
      ::CloseHandle(hMutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (hMutex != nullptr) {
    ::ReleaseMutex(hMutex);
    ::CloseHandle(hMutex);
  }

  ::ExitProcess(EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
