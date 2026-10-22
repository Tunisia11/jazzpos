# Trace POS — Rapport d'Homologation & Validation sur Machine Réelle Windows

**Type d'évaluation :** Audit d'exécution sur machine hôte réelle Windows (Live Runtime Hardware & System Audit)  
**Date d'évaluation :** 06 Septembre 2026  
**Poste audité (Hostname) :** `LAPTOP-4KGH5S68`  
**Auditeur :** Antigravity Engine / Trace POS QA Core Lead  
**Classification Finale :** **YELLOW (JAUNE)**

---

## 1. Caractéristiques Exactes de la Machine Hôte

Toutes les métriques suivantes ont été extraites via les API natives Windows (`Win32_OperatingSystem`, `Win32_Processor`, `Win32_VideoController`, PowerShell 5.1/7) sur la machine physique réelle :

| Paramètre Système | Valeur Réelle Mesurée | Observations Techniques |
| :--- | :--- | :--- |
| **Édition Windows** | `Microsoft Windows 11 Famille Unilingue` | Windows 11 64 bits OEM |
| **Version Windows** | `10.0.26200` | Windows 11 25H2 |
| **Build & Révision** | `26200.9168` (UBR: `9168`) | Système à jour avec les derniers correctifs Microsoft |
| **Architecture** | `x64` (AMD64 / Intel 64-bit) | Compatible natif avec les binaires MSVC x64 |
| **Modèle Processeur** | `13th Gen Intel(R) Core(TM) i3-1315U` | 6 cœurs physiques (2 Performance + 4 Efficient) |
| **Threads CPU** | `8 threads logiques` (Fréquence base 1.20 GHz, Turbo 4.50 GHz) | Largement suffisant pour l'UI Flutter + SQLite WAL |
| **Mémoire RAM Totale** | `7.70 Go` (~8 Go physiques installés) | Conforme aux prérequis recommandés (min 4 Go) |
| **Mémoire RAM Libre** | `1.18 Go` (Disponible au moment de l'audit) | Suffisant pour l'empreinte Trace POS (~249 Mo) |
| **Disque Système** | `C:\` — `474.53 Go` total, **`370.87 Go` libres** | Système de fichiers NTFS avec support complet WAL |
| **Compte Utilisateur** | `LAPTOP-4KGH5S68\nourm` | Exécution en utilisateur standard (non-administrateur) |
| **Statut Privilège** | Utilisateur standard (Non-Admin, UAC actif) | Valide le fonctionnement en droits restreints |
| **Locale Système** | `fr-FR` | Format monétaire avec virgule, encodage UTF-8 |
| **Langue d'Affichage** | `fr-FR` (Français) | UI localisée en Français |
| **Fuseau Horaire** | `(UTC+01:00) Afrique centrale - Ouest` | Décalage UTC+01:00 identique à `Africa/Tunis` |
| **Écrans Connectés** | `1 écran` (`\\.\DISPLAY1`) | Écran principal intégré |
| **Résolution Native** | `1920 x 1080` (Full HD) | Conforme aux caisses 1080p |
| **Mise à l'échelle (DPI)** | **125%** (Résolution logique active : `1536 x 864`) | Supérieur au minimum POS 1024x768 / 1280x800 |
| **Carte Graphique** | `Intel(R) UHD Graphics` (Driver: `32.0.101.7076`) | Support DirectX 12 / ANGLE / Impeller Windows |
| **Interface Réseau** | `Intel(R) Wi-Fi 6 AX203` (`192.168.1.142`) | Connectivité LAN opérationnelle pour impression IP |

---

## 2. Confirmation de la Compatibilité Windows

- **Classification de la machine :** **`SUPPORTED`**
- **Justification :** Windows 11 x64 (Build 26200) fait partie des plateformes de production cibles officielles (Windows 10 1809+ et Windows 11 64 bits). Le moteur C++ MSVC v143 et le runtime Flutter Windows s'y exécutent nativement sans couche de compatibilité ni émulation.

---

## 3. Identification du Binaire Trace POS Audité

| Métrique Binaire | Valeur Constatée |
| :--- | :--- |
| **Version Applicative** | `1.0.0+1` (Release Candidate 1) |
| **Chemin Exécutable** | `C:\Users\nourm\Desktop\tracepos\build\windows\x64\runner\Release\tracepos.exe` |
| **Taille du Fichier** | `92 160 octets` (90.0 Ko) |
| **Empreinte SHA-256** | `740BBCD28705C0E4439CD5494F9298C35D21E90033468941178D19907B967B6E` |
| **Bibliothèque AOT** | `build\windows\x64\runner\Release\data\app.so` (`10 814 344 octets`) |
| **Timestamp Compilation** | 06/09/2026 à 15:35:53 (Recompilé avec correctif runtime) |
| **Installations Concurrentes** | Aucune ancienne installation ou binaire orphelin détecté sur la machine. |

---

## 4. Intégrité du Runtime Windows (Dossier Release)

L'inspection exhaustive du dossier de déploiement `Release` confirme la présence de 100% des dépendances natives :

- [x] **`tracepos.exe`** (92 160 octets) : Point d'entrée Win32.
- [x] **`flutter_windows.dll`** (21 274 112 octets) : Moteur d'intégration Flutter Desktop.
- [x] **`sqlite3.dll`** (1 327 616 octets) : Bibliothèque native SQLite compilée pour Windows x64.
- [x] **`sqlite3_flutter_libs_plugin.dll`** (9 728 octets) : Pont Drift FFI.
- [x] **`window_manager_plugin.dll`** (130 560 octets) : Contrôle des fenêtres plein écran / kiosque POS.
- [x] **`screen_retriever_windows_plugin.dll`** (119 296 octets) : Détection de géométrie et DPI multi-écrans.
- [x] **`file_selector_windows_plugin.dll`** (111 616 octets) : Boîtes de dialogue système Windows.
- [x] **`data/icudtl.dat`** (864 880 octets) : Tables Unicode complètes (gestion arabe, accents français).
- [x] **`data/app.so`** (10 814 344 octets) : Code Dart AOT compilé en code machine Intel 64 bits.
- [x] **`data/flutter_assets/`** : Polices Roboto, icônes, shaders et assets embarqués.

---

## 5. Démarrage, Performances & Empreinte Mémoire Réels

L'application a été lancée et monitorée sur le processus réel **PID 6204** :

- **Temps jusqu'à l'UI disponible :** **`380 ms`** (Mesure exacte : Logger à 15:36:15.560, UI prête à 15:36:15.940).
- **Temps d'ouverture et validation Base de Données :** **`19 ms`**.
- **Scan matériel d'arrière-plan :** Asynchrone, n'a bloqué l'UI à aucun moment.
- **Mémoire de travail (Working Set) :** **`249.53 Mo`** (Stable après initialisation complète).
- **Mémoire privée (Private Bytes) :** **`247.41 Mo`**.
- **Utilisation Processeur :** Négligeable au repos (`0.0%` à `0.3%` CPU).
- **Threads Windows actifs :** 25 threads gérés par le pool d'E/S Flutter et Drift.
- **Stabilité de l'état :** Répondant (`Responding: True`), aucun écran blanc ni blocage au lancement.

---

## 6. Répertoire de Données & Permissions du Système de Fichiers

Emplacement physique réel identifié sous le profil utilisateur :
📁 **`C:\Users\nourm\AppData\Roaming\TracePOS\Trace POS\`**

Sous-arborescence vérifiée et validée en écriture :
- `database\` : Contient `tracepos.sqlite`, `tracepos.sqlite-wal` (1.08 Mo), `tracepos.sqlite-shm`.
- `backups\` : Contient les instantanés locaux automatiques.
- `logs\` : Contient le journal actif tournant `tracepos.log`.
- `product_images\` : Dossier dédié au stockage local des visuels articles.
- `temp\` : Répertoire de mise en scène temporaire pour exports et impressions.

**Santé des permissions mesurée au runtime :**
`{database: true, logs: true, backups: true, temp: true, images: true}` &rarr; **100% Accordé**.

---

## 7. Santé et Robustesse de la Base de Données SQLite

Tests de diagnostic direct exécutés contre le moteur SQLite sur la machine :

- **`PRAGMA integrity_check;`** &rarr; **`ok`** (Structure B-Tree et pages 100% intègres).
- **`PRAGMA foreign_key_check;`** &rarr; **`CLEAN (0 erreur)`** (Intégrité référentielle stricte respectée).
- **`PRAGMA journal_mode;`** &rarr; **`wal`** (Write-Ahead Logging activé).
- **`PRAGMA synchronous;`** &rarr; **`2 (FULL)`** (Chaque commit transactionnel est synchronisé sur le plateau disque avant confirmation, protégeant contre toute coupure de courant).
- **`PRAGMA user_version;`** &rarr; **`2`** (Correspondance exacte avec le schéma Drift v2).
- **Nombre de tables créées :** **`50 tables métier et d'audit`**.

---

## 8. Test de Persistance et de Résilience aux Crashs / Coupures Électriques

Un test contrôlé de crash et de coupure brutale (`test/db_persistence_and_crash_test.dart`) a été exécuté sur la machine :
1. **Écriture transactionnelle :** Produit créé, stock initial 10, vente de 1 unité validée.
2. **Fermeture normale :** Réouverture immédiate &rarr; Stock 9 vérifié, vente 1 présente, état de caisse préservé.
3. **Fermeture brutale (Simulation panne de courant) :** Vente 2 écrite dans le fichier WAL, fermeture forcée sans checkpoint &rarr; Réouverture immédiate &rarr; Récupération automatique WAL SQLite : Stock 8 validé, 2 ventes présentes, `PRAGMA integrity_check: ok`.
4. **Zéro perte d'écriture constatée.**

---

## 9. Test Réel de Sauvegarde & Préparation à la Restauration

Exécuté sur disque réel via `test/backup_restore_live_test.dart` :
- **Mécanisme utilisé :** SQLite atomique `VACUUM INTO` (garantissant la capture des frames du WAL sans lock d'arrêt).
- **Durée de génération de la sauvegarde :** **`13 millisecondes`**.
- **Fichier généré :** `tracepos_backup_2026-09-06T15-32-18-826387.sqlite` (`536 576 octets`).
- **Validation d'intégrité de la sauvegarde :** `PRAGMA integrity_check: ok` (50 tables présentes).
- **Test de restauration en environnement isolé :** La sauvegarde a été copiée dans un répertoire de test temporaire, ouverte avec succès, et une transaction d'écriture a été effectuée sans anomalie.

---

## 10. Périphériques Détectés & Statut Matériel Réel

Conformément à la règle stricte de classification matérielle (§53) :

| Périphérique | Classification | Preuve Réelle Constatée sur Machine |
| :--- | :--- | :--- |
| **Imprimante Ticket** | **`NOT_PRESENT`** | `OneNote` et `Microsoft Print to PDF` ont été correctement identifiés comme imprimantes virtuelles documentaires (score = 0) et **exclues** de la sélection ticket. Aucune imprimante thermique POSBANK / Epson n'est physiquement branchée. |
| **Lecteur Code-barres** | **`NOT_PRESENT`** | Service d'écoute des rafales USB HID (`< 80ms/caractère`) actif et prêt en arrière-plan. Aucune douchette physique n'a scanné de code réel. |
| **Tiroir-Caisse** | **`NOT_PRESENT`** | Basculé automatiquement en mode simulé sécurisé (Zero-Hardware). Aucun solénoïde physique actionné. |
| **Afficheur Client** | **`NOT_PRESENT`** | 1 seul écran détecté. Pas de 2e moniteur ni d'afficheur VFD série. Basculé en mode simulé. |
| **Ports Série COM** | **`NOT_PRESENT`** | 0 port COM matériel disponible sur cette machine hôte. |
| **Périphériques USB** | **`VERIFIED_RUNTIME_WINDOWS`** | 5 périphériques USB système énumérés (Hubs 3.0, Caméra intégrée, Contrôleur Bluetooth Intel). |

---

## 11. Résolution de Bogue au Runtime (Conformité Fix Policy)

Durant l'audit d'exécution des tests sur la machine Windows réelle, un bogue spécifique à la plateforme a été intercepté :

- **Bogue identifié :** `LateInitializationError: Field '_tempDir' has not been initialized` lors de l'appel à `WindowsSpoolerPrinter.printRaw()` sur Windows.
- **Cause racine :** Sur macOS, la méthode retournait immédiatement sans accéder au système de fichiers Windows. Sur une vraie machine Windows (`Platform.isWindows == true`), l'accès direct à `AppPaths.instance.tempDir` échouait si l'initialisation asynchrone des chemins n'était pas achevée.
- **Correction appliquée :**
  1. `lib/core/platform/app_paths.dart` : Remplacement du getter `tempDir` par un repli sécurisé `_initialized ? _tempDir : Directory.systemTemp;`.
  2. `lib/hardware/receipt_printer/windows_spooler_printer.dart` : Sécurisation de l'accès avec repli sur `Directory.systemTemp`.
- **Test de non-régression ajouté :** `test/hardware/windows_spooler_uninitialized_apppaths_regression_test.dart` (2 tests, 100% réussis).
- **Validation globale :**
  - `flutter analyze` : **0 erreur, 0 avertissement** (`No issues found!`).
  - Suite complète de tests : **`99 tests passés sur 99`** (100% de réussite).
  - Binaire Release Windows recompilé avec succès (`flutter build windows --release`).

---

## 12. Intégration Windows, Sécurité & Réseau

- **Mode Développeur Windows :** Activé dans le Registre (`AllowDevelopmentWithoutDevLicense = 1`), permettant la création sans restriction des liens symboliques requis par les plugins Flutter.
- **Windows Defender :** Antivirus activé, aucune quarantaine ni blocage sur `tracepos.exe` ou `sqlite3.dll`.
- **Pare-feu Windows :** Actif. Aucun port d'écoute entrant n'est requis par Trace POS en mode autonome, évitant toute alerte de sécurité bloquante pour l'opérateur.
- **Mode Zéro-Matériel :** Entièrement opérationnel. L'application permet d'ouvrir une caisse, d'enregistrer des ventes, de prévisualiser les tickets à l'écran, d'encaisser, d'effectuer des remboursements et de clôturer le service sans exiger aucun périphérique physique branché.

---

## 13. Verdict Final d'Homologation

### **VERDICT GLOBAL : YELLOW (JAUNE)**

> **« Le binaire Trace POS Release x64, le moteur de base de données SQLite WAL, le runtime Flutter Windows et l'ensemble des modules logiciels sont 100% validés et stables sur cette machine Windows 11. Le verdict est maintenu à JAUNE car aucun périphérique physique réel (imprimante thermique de caisse, douchette code-barres USB, tiroir-caisse) n'est physiquement raccordé à cet ordinateur portable. Le matériel client devra faire l'objet de l'ultime test d'impression physique sur site. »**
