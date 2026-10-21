import 'dart:convert';

/// Only base64 JSON (data) is inserted; queue names never become PowerShell code.
class WindowsRawPrintBridge {
  static List<String> arguments(Map<String,Object?> request, {required bool print}) {
    final command = script(request, print:print);
    final bytes = command.codeUnits.expand((unit)=>[unit & 255, unit >> 8]).toList();
    return ['-NoProfile','-NonInteractive','-EncodedCommand',base64Encode(bytes)];
  }
  static String script(Map<String, Object?> request, {required bool print}) {
    final payload = base64Encode(utf8.encode(jsonEncode(request)));
    return '''
\$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(\$false)
try {
  \$request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payload')) | ConvertFrom-Json
${print ? printBody : statusBody}
} catch {
  @{success=\$false; error=\$_.Exception.Message; delivery='unknown'} | ConvertTo-Json -Compress
  exit 1
}
''';
  }

  static const statusBody = r'''
  $queues = @(Get-CimInstance Win32_Printer | Where-Object { $_.Name -eq $request.queueName })
  if ($queues.Count -eq 0) {
    @{success=$true; exists=$false; status='MISSING'} | ConvertTo-Json -Compress
  } else {
    $p = $queues[0]
    $state = 'QUEUE_EXISTS'
    if ($p.WorkOffline -eq $true -or $p.ExtendedPrinterStatus -eq 7) { $state = 'OFFLINE' }
    elseif ($p.ExtendedPrinterStatus -eq 8) { $state = 'PAUSED' }
    elseif ($p.ExtendedPrinterStatus -eq 9 -or $p.DetectedErrorState -gt 2 -or $p.ExtendedDetectedErrorState -gt 2) { $state = 'ERROR' }
    elseif ($p.ExtendedPrinterStatus -in @(3,4,5,10,12,13) -and $p.DetectedErrorState -eq 2) { $state = 'READY' }
    @{success=$true; exists=$true; status=$state} | ConvertTo-Json -Compress
  }
  exit 0
''';

  static const printBody = r'''
  $code = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class TraceRawPrinter {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public class DOC_INFO_1 {
    [MarshalAs(UnmanagedType.LPWStr)] public string pDocName = "Trace POS Receipt";
    [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile = null;
    [MarshalAs(UnmanagedType.LPWStr)] public string pDatatype = "RAW";
  }
  [DllImport("winspool.drv", EntryPoint="OpenPrinterW", ExactSpelling=true, SetLastError=true, CharSet=CharSet.Unicode)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool OpenPrinterW(string name, out IntPtr handle, IntPtr defaults);
  [DllImport("winspool.drv", EntryPoint="StartDocPrinterW", ExactSpelling=true, SetLastError=true, CharSet=CharSet.Unicode)]
  static extern uint StartDocPrinterW(IntPtr handle, uint level, [In] DOC_INFO_1 doc);
  [DllImport("winspool.drv", ExactSpelling=true, SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool StartPagePrinter(IntPtr handle);
  [DllImport("winspool.drv", ExactSpelling=true, SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool WritePrinter(IntPtr handle, [In] byte[] bytes, uint count, out uint written);
  [DllImport("winspool.drv", ExactSpelling=true, SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool EndPagePrinter(IntPtr handle);
  [DllImport("winspool.drv", ExactSpelling=true, SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool EndDocPrinter(IntPtr handle);
  [DllImport("winspool.drv", ExactSpelling=true, SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool AbortPrinter(IntPtr handle);
  [DllImport("winspool.drv", ExactSpelling=true, SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool ClosePrinter(IntPtr handle);
  static void Check(bool ok, string step) {
    if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error(), step);
  }
  public static uint Send(string name, byte[] bytes) {
    IntPtr handle;
    Check(OpenPrinterW(name, out handle, IntPtr.Zero), "OpenPrinterW");
    uint jobId = 0;
    bool completed = false;
    Exception failure = null;
    try {
      jobId = StartDocPrinterW(handle, 1, new DOC_INFO_1());
      Check(jobId > 0, "StartDocPrinterW");
      Check(StartPagePrinter(handle), "StartPagePrinter job=" + jobId);
      uint written;
      Check(WritePrinter(handle, bytes, (uint)bytes.Length, out written), "WritePrinter job=" + jobId);
      if (written != bytes.Length) throw new Exception("Partial WritePrinter job=" + jobId + " bytes=" + written + "/" + bytes.Length);
      Check(EndPagePrinter(handle), "EndPagePrinter job=" + jobId);
      Check(EndDocPrinter(handle), "EndDocPrinter job=" + jobId);
      completed = true;
    } catch (Exception ex) { failure = ex; }
    finally {
      if (jobId > 0 && !completed && !AbortPrinter(handle)) {
        failure = new Exception((failure == null ? "" : failure.Message) + "; AbortPrinter failed: " + Marshal.GetLastWin32Error());
      }
      if (!ClosePrinter(handle)) {
        failure = new Exception((failure == null ? "" : failure.Message) + "; ClosePrinter failed: " + Marshal.GetLastWin32Error() + " job=" + jobId);
      }
    }
    if (failure != null) throw failure;
    return jobId;
  }
}
'@
  Add-Type -TypeDefinition $code -ErrorAction Stop
  $bytes = [IO.File]::ReadAllBytes($request.filePath)
  $jobId = [TraceRawPrinter]::Send($request.queueName, $bytes)
  if ($jobId -le 0) { throw 'Invalid native job ID' }
  @{success=$true; jobId=$jobId; bytesWritten=$bytes.Length; queueName=$request.queueName; delivery='queued'} | ConvertTo-Json -Compress
  exit 0
''';
}
