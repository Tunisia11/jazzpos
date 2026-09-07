import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows Authenticode Code Signing Pipeline Tests', () {
    final projectRoot = Directory.current.path;

    test('1. Security: .gitignore strictly excludes code signing secrets and private keys', () {
      final gitignoreFile = File('$projectRoot/.gitignore');
      expect(gitignoreFile.existsSync(), isTrue, reason: '.gitignore must exist');

      final content = gitignoreFile.readAsStringSync();
      expect(content, contains('*.pfx'), reason: 'PFX private keys must be ignored');
      expect(content, contains('*.p12'), reason: 'PKCS#12 keys must be ignored');
      expect(content, contains('*.key'), reason: 'Private keys must be ignored');
      expect(content, contains('secrets/'), reason: 'Secrets directory must be ignored');
      expect(content, contains('credentials*.json'), reason: 'Credential JSON files must be ignored');
      expect(content, contains('!windows/signing/signing_config.template.json'),
          reason: 'Template configuration must remain committed');
    });

    test('2. Configuration: windows/signing/signing_config.template.json is valid schema', () {
      final templateFile = File('$projectRoot/windows/signing/signing_config.template.json');
      expect(templateFile.existsSync(), isTrue, reason: 'Signing configuration template must exist');

      final json = jsonDecode(templateFile.readAsStringSync()) as Map<String, dynamic>;
      expect(json['signMode'], isNotNull);
      expect(json['general'], isNotNull);
      expect(json['general']['fileDigestAlgorithm'], equals('SHA256'));
      expect(json['general']['timestampDigestAlgorithm'], equals('SHA256'));
      expect(json['general']['timestampUrl'], contains('timestamp'));

      expect(json['trustedSigning'], isNotNull);
      expect(json['pfx'], isNotNull);
      expect(json['certStore'], isNotNull);
    });

    test('3. Pipeline Orchestrator: scripts/build_and_sign_release.ps1 enforces Authenticode standards', () {
      final scriptFile = File('$projectRoot/scripts/build_and_sign_release.ps1');
      expect(scriptFile.existsSync(), isTrue, reason: 'build_and_sign_release.ps1 must exist');

      final scriptText = scriptFile.readAsStringSync();

      // SHA-256 Authenticode enforcement
      expect(scriptText, contains('/fd'), reason: 'Must specify /fd for digest');
      expect(scriptText, contains('SHA256'), reason: 'Must enforce SHA-256 digest');

      // RFC 3161 Timestamping enforcement
      expect(scriptText, contains('/tr'), reason: 'Must specify RFC 3161 timestamp server');
      expect(scriptText, contains('/td'), reason: 'Must specify timestamp digest algorithm');
      expect(scriptText, contains('http://timestamp.digicert.com'), reason: 'DigiCert RFC 3161 timestamp URL');

      // Verification tools
      expect(scriptText, contains('Get-AuthenticodeSignature'), reason: 'PowerShell Authenticode verification');
      expect(scriptText, contains('verify'), reason: 'SignTool verification');

      // Tamper-resistance test
      expect(scriptText, contains('HashMismatch'), reason: 'Tamper detection must check HashMismatch');

      // Artifact outputs
      expect(scriptText, contains('SHA256SUMS.txt'), reason: 'Must generate SHA256SUMS.txt');
      expect(scriptText, contains('CODE_SIGNING_REPORT.md'), reason: 'Must generate CODE_SIGNING_REPORT.md');

      // Report sections
      expect(scriptText, contains('Executable:'), reason: 'Report must include Executable');
      expect(scriptText, contains('Publisher:'), reason: 'Report must include Publisher');
      expect(scriptText, contains('Signature:'), reason: 'Report must include Signature');
      expect(scriptText, contains('Timestamp:'), reason: 'Report must include Timestamp');
      expect(scriptText, contains('Verification:'), reason: 'Report must include Verification');
      expect(scriptText, contains('SHA-256:'), reason: 'Report must include SHA-256 section');
    });

    test('4. Checksums: dist/SHA256SUMS.txt contains valid SHA-256 entries', () {
      final checksumFile = File('$projectRoot/dist/SHA256SUMS.txt');
      if (checksumFile.existsSync()) {
        final lines = checksumFile.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
        expect(lines.isNotEmpty, isTrue);
        for (final line in lines) {
          final parts = line.split(RegExp(r'\s+\*'));
          expect(parts.length, equals(2), reason: 'Format must be: <hash> *<filename>');
          expect(parts[0].length, equals(64), reason: 'SHA-256 hex string must be 64 characters');
          expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(parts[0]), isTrue,
              reason: 'SHA-256 must contain only lowercase hex characters');
        }
      }
    });

    test('5. Release Report: release_audit/CODE_SIGNING_REPORT.md is well-formed', () {
      final reportFile = File('$projectRoot/release_audit/CODE_SIGNING_REPORT.md');
      if (reportFile.existsSync()) {
        final content = reportFile.readAsStringSync();
        expect(content, contains('Executable:'));
        expect(content, contains('Publisher:'));
        expect(content, contains('Signature:'));
        expect(content, contains('Timestamp:'));
        expect(content, contains('Verification:'));
        expect(content, contains('SHA-256'));
        expect(content, contains('Tamper Resistance'));
      }
    });
  });
}
