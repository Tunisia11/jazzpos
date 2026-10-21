#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

constexpr const wchar_t kSingleInstanceMutexName[] = L"Local\\JazzPOS_SingleInstance_Mutex";

bool ActivateExistingWindow() {
  // Check for window with a brief retry loop in case primary instance is launching
  for (int i = 0; i < 6; ++i) {
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
    ::Sleep(100);
  }
  return false;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE hMutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (hMutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // A primary instance is already running. Try activating its window.
    ActivateExistingWindow();
    // Safely exit second instance. Never terminate an existing healthy process.
    ::CloseHandle(hMutex);
    return EXIT_SUCCESS;
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
