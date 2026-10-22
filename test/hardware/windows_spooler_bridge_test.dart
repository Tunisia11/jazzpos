import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/platform/process_utils.dart';
import 'package:tracepos/hardware/models/hardware_status.dart';
import 'package:tracepos/hardware/receipt_printer/windows_raw_print_bridge.dart';
import 'package:tracepos/hardware/receipt_printer/windows_spooler_printer.dart';

void main() {
  for(final name in ['EPSON TM-T20III','POS-80',r'Caisse $1',"John's Printer",r'\\SHOP-PC\Receipt Printer','Caisse Élégance "été"']) {
    test('Safe data transport and validated queued job: $name',() async {
      final printer=WindowsSpoolerPrinter(name:name,processRunner:(exe,args,{timeout=const Duration(seconds:3)}) async {
        final data=base64Decode(args.last);
        final script=String.fromCharCodes(List.generate(data.length~/2,(i)=>data[i*2] | data[i*2+1]<<8));
        final encoded=RegExp("FromBase64String\\('([^']+)'\\)").firstMatch(script)!.group(1)!;
        final payload=jsonDecode(utf8.decode(base64Decode(encoded)));
        expect(payload['queueName'],name);
        expect(script, isNot(contains('= "$name"')));
        expect(await File(payload['filePath']).readAsBytes(),[27,64]);
        return ProcessResult(1,0,jsonEncode({'success':true,'jobId':123,'bytesWritten':2,'queueName':name,'delivery':'queued'}),'');
      });
      await printer.printRaw(Uint8List.fromList([27,64]));
      expect(printer.lastJobId,123); expect(printer.lastSpoolJobs,hasLength(1));
    });
  }
  for(final failure in ['OpenPrinterW','StartDocPrinterW','StartPagePrinter','WritePrinter','Partial WritePrinter','EndPagePrinter','EndDocPrinter','ClosePrinter','TIMEOUT']) {
    test('Failure is never submitted success: $failure',() async {
      final printer=WindowsSpoolerPrinter(name:'POS',processRunner:(exe,args,{timeout=const Duration(seconds:3)}) async=>ProcessResult(1,1,jsonEncode({'success':false,'error':failure}),''));
      await expectLater(printer.printRaw(Uint8List.fromList([1,2])),throwsException);
      expect(printer.lastJobId,isNull); expect(printer.lastSpoolJobs,isEmpty);
    });
  }
  for(final output in ['', 'JOB_SUBMITTED', '{"success":true,"jobId":0}', '{"success":true,"jobId":1,"bytesWritten":1,"queueName":"POS","delivery":"queued"}']) {
    test('Exit zero cannot override invalid result: $output',()async {
      final printer=WindowsSpoolerPrinter(name:'POS',processRunner:(exe,args,{timeout=const Duration(seconds:3)}) async=>ProcessResult(1,0,output,''));
      await expectLater(printer.printRaw(Uint8List.fromList([1,2])),throwsException);
    });
  }
  for(final status in [HardwareStatus.missing,HardwareStatus.queueExists,HardwareStatus.ready,HardwareStatus.offline,HardwareStatus.paused,HardwareStatus.error]) {
    test('Queue status $status is preserved',()async {
      final printer=WindowsSpoolerPrinter(name:'POS',processRunner:(exe,args,{timeout=const Duration(seconds:3)}) async=>ProcessResult(1,0,jsonEncode({'success':true,'exists':status!=HardwareStatus.missing,'status':status.value}),''));
      expect(await printer.connect(),status==HardwareStatus.ready); expect(printer.status,status);
    });
  }
  test('Empty status is unknown',()async {
    final printer=WindowsSpoolerPrinter(name:'POS',processRunner:(exe,args,{timeout=const Duration(seconds:3)}) async=>ProcessResult(1,0,'',''));
    expect(await printer.connect(),false); expect(printer.status,HardwareStatus.unknown);
  });
  test('Native bridge checks completion and uses Unicode DWORD API',(){
    expect(WindowsRawPrintBridge.printBody,contains('static extern uint StartDocPrinterW'));
    for(final step in ['StartPagePrinter','EndPagePrinter','EndDocPrinter']) {expect(WindowsRawPrintBridge.printBody,contains('Check($step(handle)'));}
    expect(WindowsRawPrintBridge.printBody,contains('written != bytes.Length'));
    expect(WindowsRawPrintBridge.printBody,contains('!ClosePrinter(handle)'));
  });
  test('Timeout kills child before delayed file write',()async {
    final dir=await Directory.systemTemp.createTemp('trace_timeout_');
    try {
      final marker=File('${dir.path}/late');
      final executable=Platform.isWindows?'powershell':'/bin/sh';
      final args=Platform.isWindows?['-NoProfile','-Command',"Start-Sleep -Seconds 2; Set-Content -LiteralPath '${marker.path}' -Value late"]:['-c','sleep 2; touch "\$1"','--',marker.path];
      final result=await ProcessUtils.safeRun(executable,args,timeout:const Duration(milliseconds:100));
      expect(result.exitCode,-1); expect(result.stderr,contains('TIMEOUT'));
      await Future<void>.delayed(const Duration(milliseconds:2200));
      expect(await marker.exists(),false);
    } finally {await dir.delete(recursive:true);}
  });
}
