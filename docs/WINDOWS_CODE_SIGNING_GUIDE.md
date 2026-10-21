# JAZZ POS (Trace POS) — Windows Code Signing & SmartScreen Guide

This guide details the production code-signing architecture for **JAZZ POS (Trace POS)** on Windows 10 and 11.

---

## 1. Understanding Microsoft Defender SmartScreen

When users download and run an unsigned or untrusted `.exe` on Windows, Microsoft Defender SmartScreen displays:

```
Windows a protégé votre ordinateur
Microsoft Defender SmartScreen a empêché le démarrage d'une application non reconnue.
L'exécution de cette application peut mettre votre ordinateur en danger.
```

### Why SmartScreen Appears
- **Lack of Publisher Identity**: Windows cannot cryptographically verify who created the binary or whether it was altered since creation.
- **No Accumulated Reputation**: SmartScreen uses a reputation-based telemetry engine. Even if an executable has zero malware signatures, an unknown binary without verifiable identity has zero reputation.

### Why Self-Signed Certificates DO NOT Work
> [!WARNING]
> Generating a self-signed certificate on your local machine and signing the binary **does not solve SmartScreen**.
> Windows inspects the certificate root against the **Microsoft Trusted Root Certificate Program**. A self-signed root is untrusted by default on all client PCs, triggering the exact same warning or a certificate trust failure.

### The Only Two Production Solutions
1. **Microsoft Trusted Signing** (formerly *Azure Trusted Signing* / *Microsoft Artifact Signing*) — **Recommended**.
2. **Commercial Extended Validation (EV) or Organization Validation (OV) Certificate** from a publicly trusted CA (DigiCert, Sectigo, Certum).

---

## 2. Recommended Solution: Microsoft Trusted Signing

Microsoft Trusted Signing is Microsoft's official cloud-native code signing service. It is designed specifically for Windows developers, is faster and more cost-effective than legacy USB dongles, and establishes immediate SmartScreen trust.

### Benefits:
- **Direct Microsoft Integration**: Instant recognition by Windows Defender and SmartScreen.
- **No Physical Hardware Dongle**: Cloud-based HSM managed by Microsoft.
- **Cost-effective**: ~$9.99/month (vs $400–$700/year for physical EV USB tokens).
- **Native SignTool Integration**: Supported directly in Windows SDK `signtool.exe` via `/dlib` and `/dmdf`.

### Step-by-Step Onboarding for the Repository Owner:

#### Step 1: Azure Subscription & Resource Provider
1. Log in to the [Azure Portal](https://portal.azure.com/).
2. Under **Subscriptions**, select your active subscription.
3. Navigate to **Resource Providers**, search for `Microsoft.CodeSigning`, and click **Register**.

#### Step 2: Create a Trusted Signing Account
1. In Azure Portal, search for **Trusted Signing Accounts** and click **Create**.
2. Choose your Resource Group and Region (e.g., `West Europe` or `East US`).
3. Set your account name (e.g., `TracePOSSigningAccount`).

#### Step 3: Complete Identity Validation
1. Inside your Trusted Signing account, navigate to **Identity Validation**.
2. Click **New Identity Validation**:
   - **Organization**: Provide your company registration documents, business email, and Dun & Bradstreet (D-U-N-S) number.
   - **Individual**: Provide government photo ID and address verification through Microsoft’s verification partner.
3. Once validated (typically 1–3 business days), status will change to **Completed**.

#### Step 4: Create a Certificate Profile
1. Under your Trusted Signing account, select **Certificate Profiles**.
2. Click **Create**:
   - Profile Type: **Public Trust** (for customer-facing software).
   - Select your approved Identity Validation.
3. Save the profile name (e.g., `TracePOSPublicProfile`).

#### Step 5: Configure Local Machine & CI/CD
1. Download the `Azure.CodeSigning.Dlib.dll` (distributed via the NuGet package `Microsoft.Trusted.Signing.Client`).
2. Create your local metadata configuration file: `windows/signing/metadata.json` (already gitignored):
   ```json
   {
     "Endpoint": "https://weu.codesigning.azure.net/",
     "CodeSigningAccountName": "TracePOSSigningAccount",
     "CertificateProfileName": "TracePOSPublicProfile",
     "CorrelationId": "trace-pos-v1.0.0"
   }
   ```
3. Set the environment variables:
   - `AZURE_TRUSTED_SIGNING_DLIB_PATH=C:\tools\Azure.CodeSigning.Dlib.dll`
   - `AZURE_TRUSTED_SIGNING_METADATA_PATH=C:\Users\...\windows\signing\metadata.json`

---

## 3. Alternative Solution: Commercial EV Hardware Token / PFX

If you purchase an EV Code Signing certificate from DigiCert, Sectigo, or Certum:

Since June 2023, the CA/Browser Forum mandates that private keys must reside on **FIPS 140-2 Level 2** hardware (e.g., SafeNet eToken 5110) or a compliant Cloud HSM (DigiCert KeyLocker).

### Using with USB Hardware Dongle:
1. Plug the USB token into the build machine.
2. Install the token middleware (e.g., SafeNet Authentication Client).
3. Find your certificate SHA-1 thumbprint:
   ```powershell
   Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert
   ```
4. Run the release pipeline passing the thumbprint:
   ```powershell
   .\scripts\build_and_sign_release.ps1 -Mode cert-store -CertThumbprint "YOUR_THUMBPRINT_HERE" -RequireSignature
   ```

---

## 4. Pipeline Usage & Execution

The orchestrator script is [`scripts/build_and_sign_release.ps1`](file:///C:/Users/nourm/Desktop/jazzpos/scripts/build_and_sign_release.ps1).

### Execution Commands:

#### A. Production Signed Release (Strict):
```powershell
# Fails immediately if signing or verification fails
.\scripts\build_and_sign_release.ps1 -RequireSignature
```

#### B. Development Build (Local / Fast):
```powershell
# Compiles binaries and installer without requiring certificates or internet timestamping
.\scripts\build_and_sign_release.ps1 -Mode skip
```
*Alternatively, developers can continue using standard Flutter commands:*
```bash
flutter build windows --release
```

#### C. Testing & Pipeline Validation Mode:
```powershell
# Tests the complete pipeline, signing, RFC 3161 timestamping, installer packaging,
# tamper-detection verification, and release report generation using a local test certificate:
.\scripts\build_and_sign_release.ps1 -TestMode -SkipFlutterBuild
```

---

## 5. Security & Git Safeguards

- **Never Commit Secrets**: Private keys (`*.pfx`, `*.p12`, `*.key`), certificate passwords, and cloud tokens are strictly excluded in [`.gitignore`](file:///C:/Users/nourm/Desktop/jazzpos/.gitignore).
- **Environment Variables Supported**:
  - `JAZZPOS_SIGN_MODE`
  - `JAZZPOS_SIGN_PFX_PATH`
  - `JAZZPOS_SIGN_PFX_PASSWORD`
  - `JAZZPOS_SIGN_CERT_SHA1`
  - `AZURE_TRUSTED_SIGNING_DLIB_PATH`
  - `AZURE_TRUSTED_SIGNING_METADATA_PATH`
  - `JAZZPOS_REQUIRE_SIGNING`

---

## 6. Verification Checklist

Every official release executes:
1. **SHA-256 Digest**: Authenticode signed with SHA-256 (`/fd SHA256`).
2. **RFC 3161 Timestamp**: Countersigned by DigiCert (`/tr http://timestamp.digicert.com /td SHA256`) so signatures remain valid even after the certificate expires.
3. **Dual Verification**: Validated via both Windows SDK `signtool.exe verify /pa /v /tw` and PowerShell `Get-AuthenticodeSignature`.
4. **Tamper Test**: Proves that modifying a single byte in the executable invalidates the signature (`HashMismatch`).
5. **Release Checksums**: SHA-256 hash list emitted to `dist/SHA256SUMS.txt`.
6. **Audit Report**: Audit log generated at `release_audit/CODE_SIGNING_REPORT.md`.
