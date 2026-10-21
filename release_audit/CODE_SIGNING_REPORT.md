# JAZZ POS (Trace POS) - Windows Code Signing & Release Audit Report

Generated: 2026-09-07 16:40:36 +01:00
Signing Mode: test-simulated
Require Signature: False

## Executable
Executable: jazzpos.exe
Publisher: CN=JAZZ POS Automated Test Signer, O=Virex Test, C=TN
Signature: UnknownError (Une chaîne de certificats a été traitée mais s’est terminée par un certificat racine qui n’est pas approuvé par le fournisseur d’approbation)
Timestamp: Valid RFC 3161 (CN=DigiCert SHA256 RSA4096 Timestamp Responder 2026 1, O="DigiCert, Inc.", C=US)
Verification: PASSED

## Installer
Installer: Trace-POS-Setup-x64.exe
Publisher: CN=JAZZ POS Automated Test Signer, O=Virex Test, C=TN
Signature: UnknownError (Une chaîne de certificats a été traitée mais s’est terminée par un certificat racine qui n’est pas approuvé par le fournisseur d’approbation)
Timestamp: Valid RFC 3161 (CN=DigiCert SHA256 RSA4096 Timestamp Responder 2026 1, O="DigiCert, Inc.", C=US)
Verification: PASSED

## SHA-256
07cc4b38d335ccd2b624d9b09e652b9e0857da4a463b6d1249e6e22cc08c5de8 *jazzpos.exe
78c8a38f649e7e6bfa8ce826bd98fafc1a8efab567d2d9d92ceafe31a60b47c5 *Trace-POS-Setup-x64.exe
0337822fcb4424852179100950d381c9d52846438d8cc6b072b93cf709060fc7 *JAZZ-POS-Setup-x64.exe

## Tamper Resistance
Tamper Verification Test: PASSED (Tampering invalidates Authenticode signature with HashMismatch)

## SmartScreen & Production Guidance
> [!WARNING]
> This build used a **Test-Simulated Certificate** (8415135BDA024D8E3C0717A0BAE781D41F8CB4C8).
> Windows Defender SmartScreen **will continue to warn** on client PCs until signed with a trusted commercial certificate (Microsoft Trusted Signing or public CA EV/OV).
> See [docs/WINDOWS_CODE_SIGNING_GUIDE.md](../docs/WINDOWS_CODE_SIGNING_GUIDE.md) for full onboarding instructions.
