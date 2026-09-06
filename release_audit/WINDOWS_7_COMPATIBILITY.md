# JAZZ POS — Évaluation Technique de Compatibilité Windows 7

**Document de Référence Technique & Audit de Déploiement**  
**Date :** 06 Septembre 2026  
**Auteur :** Antigravity Engine / JAZZ POS Core Engineering Team  
**Statut Officiel :** **CONCLUSION C — SYSTÈME NON SUPPORTÉ (UNSUPPORTED)**

---

## 1. Contexte & Objectif

Dans le cadre des déploiements sur site de JAZZ POS chez des commerçants de prêt-à-porter en Tunisie, le matériel de caisse rencontré est extrêmement hétérogène (terminaux tactiles tout-en-un POSBANK Apexa G, AnyPOS, clones industriels, PC reconditionnés). Certains terminaux anciens fonctionnent encore sous Windows 7 Édition Intégrale / Professionnel (x86 ou x64).

Ce document consigne l'évaluation technique approfondie de la faisabilité, de la stabilité et des risques associés à l'exécution du build de production JAZZ POS (Flutter 3.38 / Dart 3.x / Drift SQLite) sous Windows 7.

---

## 2. Analyse des Couches Logicielles & Dépendances

### 2.1 Moteur Flutter Desktop & Dart 3.x
* **Politique officielle Flutter / Google :** Le support de Windows 7 et Windows 8/8.1 a été officiellement déprécié puis abandonné dans les versions modernes de Flutter (Dart 3+).
* **APIs Win32 manquantes :**
  * `Per-Monitor DPI Awareness V2` (`SetProcessDpiAwarenessContext`) : Non disponible nativement sous Windows 7 sans mises à jour KB spécifiques.
  * `DirectWrite & Direct2D` : Les moteurs de rendu de texte modernes s'appuient sur les fonctionnalités DirectWrite introduites avec DirectX 11.1 / Windows 8+, causant des artefacts ou des plantages d'initialisation sur Windows 7 SP1 brut.
  * **Appels de synchronisation d'E/S asynchrones (`IOCP`) & Threads :** Le runtime Dart utilise des primitives noyau Win32 modernes (`CreateThreadPoolWork`, etc.) absentes des versions non patchées de `kernel32.dll`.

### 2.2 Moteur de Données SQLite, Drift & Dart FFI
* **Liaison dynamique FFI (`sqlite3.dll`) :** La bibliothèque SQLite 3.45+ compilée pour Windows x64 s'appuie sur le Universal C Runtime (`ucrtbase.dll`).
* **Universal C Runtime (UCRT) :** Sous Windows 7, l'UCRT n'est pas intégré d'origine dans le système d'exploitation. Il nécessite l'installation préalable de la mise à jour Microsoft KB2999226 et du Service Pack 1. Sans cela, le lancement de l'application échoue immédiatement avec l'erreur :
  ```
  Impossible de démarrer le programme car il manque api-ms-win-crt-runtime-l1-1-0.dll sur votre ordinateur.
  ```
* **Intégrité transactionnelle & VACUUM INTO :** La commande SQLite `VACUUM INTO` requiert des fonctions de verrouillage de fichiers atomiques fiables. Les anciens systèmes de fichiers ou pilotes NTFS non mis à jour sous Windows 7 présentent un risque accru de corruption lors de coupures franches d'alimentation électrique sur les terminaux POS.

### 2.3 Rendu Typographique de l'Arabe (Uniscribe vs ESC/POS Raster)
* **Faiblesse d'Uniscribe sous Windows 7 :** Les tables de ligature OpenType pour la langue arabe (utilisée sur les tickets fiscaux tunisiens et les noms d'articles en arabe) souffrent de bugs de déconnexion de glyphes sous Windows 7.
* **Solution robuste JAZZ POS :** Pour contourner ce problème, JAZZ POS intègre un moteur de rasterisation logicielle autonome (`ReceiptRasterizer`) convertissant les textes arabes et logos en bitmaps 1-bit (`GS v 0`). Bien que l'impression thermique ESC/POS soit ainsi totalement immunisée contre les défauts de Windows 7, l'interface graphique Flutter elle-même reste vulnérable aux anomalies de rendu de polices.

### 2.4 Pilotes Matériels & Périphériques POS (USB / COM / Spooler)
* **Pilotes USB PnP / Virtual COM :** Les puces USB-Série courantes sur les caisses POSBANK (Prolific PL2303, FTDI, CH340, Silicon Labs CP210x) requièrent sous Windows 7 l'installation manuelle de pilotes signés avec désactivation de l'obligation de signature SHA-2 (mise à jour KB4474419 obligatoire).
* **Service Spooler Windows :** Le service `spoolsv.exe` de Windows 7 ne prend pas en charge certaines commandes de bypass RAW récentes gérées nativement par Windows 10/11 Spooler API v4.

---

## 3. Matrice de Compatibilité Technique

| Composant | Windows 10 / 11 (x64) | Windows 7 SP1 (x64 avec KB) | Windows 7 Initial / 32-bit |
| :--- | :---: | :---: | :---: |
| **Flutter 3.38 Desktop Engine** | ✅ Supporté (Cible Principale) | ⚠️ Échecs DLL fréquents | ❌ Échec critique immédiat |
| **Drift / SQLite 3 FFI** | ✅ Supporté | ⚠️ Requiert VC++ 2015-2022 & KB2999226 | ❌ Échec UCRT / DllNotFound |
| **Spooler Impression Directe (RAW)** | ✅ Supporté | ⚠️ Support partiel | ⚠️ Instable |
| **Écoute Clavier Scanner (<80ms)** | ✅ Supporté | ✅ Supporté | ✅ Supporté |
| **Affichage Second Écran (Client)** | ✅ Supporté | ⚠️ Problèmes multi-DPI | ❌ Non supporté |
| **Stabilité Globale sur Caisse POS** | **100% Production-Grade** | **Instable / Risque Défaillance** | **Totalement Inopérant** |

---

## 4. Conclusion & Décision d'Architecture

### **CONCLUSION RETENUE : OPTION C — NON SUPPORTÉ (UNSUPPORTED)**

Le build principal de production `JAZZ-POS-Setup-x64.exe` cible officiellement et exclusivement **Windows 10 et Windows 11 (64-bit)**.

Windows 7 est classé comme **Système d'Exploitation Non Supporté** pour les motifs suivants :
1. **Risque d'interruption de vente :** Les plantages aléatoires du runtime graphique Flutter et les blocages FFI sur Windows 7 sont incompatibles avec l'exigence de disponibilité continue d'une caisse enregistreuse.
2. **Fin de support Microsoft :** Windows 7 ne reçoit plus de correctifs de sécurité depuis janvier 2020.
3. **Pérennité des données financières :** La sécurité des écritures comptables et des sauvegardes atomiques ne peut être formellement garantie sur un système d'exploitation obsolète.

---

## 5. Protocole de Sécurité Opérateur sur le Terrain

Si l'installateur JAZZ POS ou l'exécutable est lancé sur un terminal sous Windows 7 ou Windows 8 :

1. **Détection Non-Destructive Immédiate :**
   * Au démarrage de l'application, le service `EnvironmentDiagnosticsService` analyse les numéros de version majeurs du noyau Windows (`osVersion.major < 10` ou `osBuild < 17763`).
2. **Écran d'Avertissement Dédié (`UnsupportedOsScreen`) :**
   * L'application affiche un écran rouge d'alerte explicite informant l'opérateur que le système d'exploitation est obsolète.
   * **Règle absolue : Aucune donnée locale n'est altérée, supprimée ou déplacée.**
3. **Choix Opérateur :**
   * **Recommandation forte :** Quitter l'application et mettre à niveau la machine vers Windows 10/11 x64, ou utiliser un build de compatibilité rétrograde dédié.
   * **Bypass exceptionnel :** Un bouton *"Continuer malgré tout (Mode Dégradé)"* permet à l'opérateur d'accéder au système sous sa propre responsabilité en cas d'urgence opérationnelle immédiate.
