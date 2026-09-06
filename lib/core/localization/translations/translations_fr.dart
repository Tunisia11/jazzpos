import 'package:flutter/widgets.dart';
import '../app_localizations.dart';

class AppLocalizationsFr extends AppLocalizations {
  @override
  Locale get locale => const Locale('fr');

  // --- Common & Actions ---
  @override
  String get appTitle => 'JAZZ POS';
  @override
  String get appSubtitle => 'Point de Vente & Gestion Prêt-à-Porter';
  @override
  String get back => 'Retour';
  @override
  String get cancel => 'Annuler';
  @override
  String get save => 'Enregistrer';
  @override
  String get delete => 'Supprimer';
  @override
  String get archive => 'Archiver';
  @override
  String get edit => 'Modifier';
  @override
  String get add => 'Ajouter';
  @override
  String get close => 'Fermer';
  @override
  String get confirm => 'Confirmer';
  @override
  String get refresh => 'Actualiser';
  @override
  String get search => 'Rechercher';
  @override
  String get filter => 'Filtrer';
  @override
  String get all => 'Tous';
  @override
  String get none => 'Aucun';
  @override
  String get actions => 'Actions';
  @override
  String get status => 'Statut';
  @override
  String get reference => 'Référence';
  @override
  String get type => 'Type';
  @override
  String get date => 'Date';
  @override
  String get time => 'Heure';
  @override
  String get quantity => 'Quantité';
  @override
  String get price => 'Prix';
  @override
  String get costPrice => 'Prix de revient';
  @override
  String get sellingPrice => 'Prix de vente';
  @override
  String get total => 'Total';
  @override
  String get subtotal => 'Sous-total';
  @override
  String get discount => 'Remise';
  @override
  String get barcode => 'Code-barres';
  @override
  String get sku => 'Référence SKU';
  @override
  String get category => 'Catégorie';
  @override
  String get notes => 'Remarques';
  @override
  String get print => 'Imprimer';
  @override
  String get export => 'Exporter';
  @override
  String get importAction => 'Importer';
  @override
  String get success => 'Succès';
  @override
  String get error => 'Erreur';
  @override
  String get warning => 'Attention';
  @override
  String get info => 'Information';
  @override
  String get loading => 'Chargement...';
  @override
  String get processing => 'Traitement en cours...';
  @override
  String get yes => 'Oui';
  @override
  String get no => 'Non';
  @override
  String get requiredField => 'Ce champ est requis';
  @override
  String get invalidValue => 'Valeur invalide';
  @override
  String get duplicateSku => 'Cette référence SKU existe déjà';
  @override
  String get duplicateBarcode =>
      'Ce code-barres est déjà utilisé par un autre article';

  // --- Navigation & Shell ---
  @override
  String get navPos => 'Caisse (POS)';
  @override
  String get navCatalog => 'Articles & Tailles';
  @override
  String get navInventory => 'Stocks & Inventaire';
  @override
  String get navPurchasing => 'Achats & Réception';
  @override
  String get navReturns => 'Retours & Échanges';
  @override
  String get navLabels => 'Étiquettes Code-Barres';
  @override
  String get navShifts => 'Caisse & Z-Report';
  @override
  String get navReports => 'Rapports Financiers';
  @override
  String get navSettings => 'Paramètres & Matériel';
  @override
  String get collapseMenu => 'Réduire le menu';
  @override
  String get expandMenu => 'Agrandir le menu';
  @override
  String get lockRegister => 'Verrouiller la caisse';
  @override
  String get logoutSession => 'Déconnexion session';
  @override
  String get roleOwner => 'Propriétaire';
  @override
  String get roleManager => 'Responsable';
  @override
  String get roleCashier => 'Caissier';
  @override
  String get roleInventory => 'Gestionnaire Stock';

  // --- POS / Checkout ---
  @override
  String get register => 'Caisse';
  @override
  String get registerOpen => 'Caisse Ouverte';
  @override
  String get registerClosed => 'Caisse Fermée';
  @override
  String get clickToOpenRegister => 'Cliquez pour ouvrir la caisse';
  @override
  String get openRegisterTitle => 'Ouvrir une session de caisse';
  @override
  String get initialCashFloat => 'Fond de caisse initial (TND)';
  @override
  String get openRegisterAction => 'Ouvrir la caisse';
  @override
  String get suspendedSales => 'Ventes en attente (F6)';
  @override
  String get openCashDrawer => 'Tiroir-caisse (F10)';
  @override
  String get drawerKickSuccess => 'Ouverture du tiroir-caisse déclenchée';
  @override
  String get searchProductOrBarcode =>
      'Rechercher un article ou scanner un code-barres...';
  @override
  String get allCategories => 'Tous les articles';
  @override
  String get cart => 'Panier';
  @override
  String get cartEmpty => 'Le panier est vide';
  @override
  String get cartEmptySubtitle =>
      'Scannez un code-barres ou sélectionnez un article dans le catalogue.';
  @override
  String get clearCart => 'Vider le panier';
  @override
  String get clearCartConfirm =>
      'Voulez-vous vraiment vider tout le panier en cours ?';
  @override
  String get holdSale => 'Mettre en attente (F6)';
  @override
  String get holdSaleSuccess => 'Vente mise en attente avec succès';
  @override
  String get resumeSale => 'Reprendre la vente';
  @override
  String get payAction => 'Encaisser (F12)';
  @override
  String get paymentTitle => 'Règlement de la vente';
  @override
  String get paymentMethod => 'Mode de paiement';
  @override
  String get paymentCash => 'Espèces';
  @override
  String get paymentCard => 'Carte Bancaire (TPE)';
  @override
  String get paymentSplit => 'Paiement Mixte';
  @override
  String get paymentCheck => 'Chèque';
  @override
  String get tenderedAmount => 'Montant reçu';
  @override
  String get changeDue => 'Monnaie à rendre';
  @override
  String get exactAmount => 'Montant exact';
  @override
  String get completeSale => 'Valider & Imprimer le ticket';
  @override
  String get saleSuccess => 'Vente enregistrée avec succès';
  @override
  String get printReceipt => 'Imprimer le ticket';
  @override
  String get receiptPreview => 'Aperçu du ticket';
  @override
  String get barcodeScannedSuccess => 'Article ajouté';
  @override
  String get barcodeNotFound => 'Aucun article trouvé pour ce code-barres';
  @override
  String nArticles(int count) => '$count article${count > 1 ? 's' : ''}';
  @override
  String itemsInCart(int count) =>
      '$count article${count > 1 ? 's' : ''} au panier';
  @override
  String get quickBills => 'Billets rapides :';
  @override
  String get validatePayment => 'Valider Paiement (Entrée)';
  @override
  String get insufficientAmount => 'Montant reçu insuffisant';
  @override
  String get invalidSplit => 'Répartition mixte invalide';
  @override
  String get noActiveShift => 'Aucune session de caisse ouverte !';
  @override
  String get invalidUserSession => 'Session utilisateur invalide';
  @override
  String get noSuspendedSales => 'Aucune vente en attente';
  @override
  String get resumeThisSale => 'Reprendre cette vente';
  @override
  String get replaceCart => 'Remplacer le panier';
  @override
  String get cartNotEmptyTitle => 'Panier actuel non vide';
  @override
  String get cartNotEmptyBody =>
      'Le panier actuel contient des articles. Si vous reprenez cette vente en attente, le panier en cours sera remplacé. Voulez-vous continuer ?';
  @override
  String get deleteSuspendedSaleTitle => 'Supprimer la vente en attente';
  @override
  String deleteSuspendedSaleBody(String name) =>
      'Êtes-vous sûr de vouloir supprimer définitivement "$name" ?';
  @override
  String get unnamedSale => 'Vente sans nom';

  // --- Catalog & Products ---
  @override
  String get productsTitle => 'Catalogue & Articles';
  @override
  String get newProduct => 'Nouvel article';
  @override
  String get editProduct => 'Modifier l\'article';
  @override
  String get deleteProduct => 'Supprimer l\'article';
  @override
  String get productName => 'Désignation de l\'article';
  @override
  String get variantDescription => 'Variante / Taille';
  @override
  String get size => 'Taille';
  @override
  String get color => 'Couleur';
  @override
  String get minStockAlert => 'Seuil d\'alerte stock';
  @override
  String get currentStock => 'Stock actuel';
  @override
  String get stock => 'Stock';
  @override
  String get activeProducts => 'Articles Actifs';
  @override
  String get archivedProducts => 'Articles Archivés';
  @override
  String get archiveProductConfirm =>
      'Voulez-vous vraiment archiver cet article ? Il ne sera plus proposé sur la caisse.';
  @override
  String get deleteProductConfirmTitle => 'Supprimer ce produit ?';
  @override
  String get deleteProductConfirmBody =>
      'Cette action retirera le produit du catalogue et de l\'inventaire actif tout en préservant l\'historique comptable et les ventes antérieures.';
  @override
  String get productSavedSuccess => 'Article enregistré avec succès';
  @override
  String get productArchivedSuccess => 'Article archivé avec succès';
  @override
  String get productDeletedSuccess => 'Article supprimé avec succès';
  @override
  String get addOrEditPhoto => 'Ajouter / Modifier la photo';
  @override
  String get chooseImage => 'Choisir une image';
  @override
  String get removePhoto => 'Supprimer la photo';
  @override
  String get photoUpdatedSuccess => 'Photo mise à jour avec succès';
  @override
  String get noImage => 'Aucune photo';
  @override
  String get matrixGenerator =>
      'Générateur de matrice Tailles & Couleurs (Prêt-à-Porter)';
  @override
  String get generateVariants => 'Générer les déclinaisons';
  @override
  String get selectSizes => '1. Sélectionnez les Tailles :';
  @override
  String get selectColors => '2. Sélectionnez les Couleurs :';
  @override
  String get bulkPrice => 'Prix en masse';
  @override
  String get bulkStock => 'Stock initial en masse';
  @override
  String get active => 'Actif';
  @override
  String get initialStock => 'Stock Init.';
  @override
  String get generalInfo => 'Informations Générales de l\'Article';
  @override
  String get secondaryName => 'Nom secondaire / Arabe (optionnel)';
  @override
  String get skuPrefix => 'Code / Préfixe SKU';
  @override
  String get defaultCost => 'Coût d\'Achat Défaut (TND)';
  @override
  String get defaultPrice => 'Prix de Vente Défaut (TND)';
  @override
  String get taxRate => 'Taux TVA';
  @override
  String get noProductsFound => 'Aucun article trouvé dans le catalogue';
  @override
  String get createFirstProduct => 'Créer le premier article';
  @override
  String get atLeastOneVariant =>
      'Veuillez générer au moins une variante active pour ce vêtement';

  // --- Stocks & Inventory ---
  @override
  String get stockLevelsTitle => 'Niveaux de stock par article';
  @override
  String get stockByArticle => 'Stock disponible';
  @override
  String get stockTransfer => 'Transférer';
  @override
  String get inStock => 'En stock';
  @override
  String get lowStock => 'Stock faible';
  @override
  String get outOfStock => 'Rupture';
  @override
  String get negativeStock => 'Stock négatif';
  @override
  String get manualStockAuditWarning =>
      'La modification directe de la quantité ajustera le stock physique et créera un mouvement tracé et audité.';
  @override
  String get stockAdjustmentReason =>
      'Ajustement manuel depuis la fiche produit';
  @override
  String get stockCountTitle => 'Inventaire Physique & Comptage';
  @override
  String get initiateCount => 'Démarrer une session de comptage';
  @override
  String get scanOrTypeBarcode => 'Scanner un article ou saisir son code...';
  @override
  String get countedQty => 'Qté Comptée';
  @override
  String get expectedQty => 'Qté Théorique';
  @override
  String get varianceQty => 'Écart d\'inventaire';
  @override
  String get totalPiecesCounted => 'Total Pièces Comptées';
  @override
  String get itemsWithVariance => 'Articles en Écart';
  @override
  String get varianceValue => 'Valeur de l\'Écart';
  @override
  String get validateAndApplyAudit => 'Valider & Appliquer les écarts';
  @override
  String get countCompletedSuccess =>
      'Session d\'inventaire clôturée avec succès';
  @override
  String get stockMovementsHistory => 'Historique des mouvements (Audit)';
  @override
  String get startInventory => 'Lancer un inventaire';
  @override
  String get noMovementsRecorded => 'Aucun mouvement de stock enregistré';
  @override
  String get sourceLocation => 'Emplacement Source';
  @override
  String get destinationLocation => 'Emplacement Destination';
  @override
  String get transferQuantity => 'Quantité à transférer';
  @override
  String get transferReason => 'Motif du transfert';
  @override
  String get atLeastTwoLocationsRequired =>
      'Au moins deux emplacements de stock sont requis';
  @override
  String get manual => 'Manuel';
  @override
  String get transferSuccessful => 'Transfert effectué avec succès !';
  @override
  String get productActions => 'Actions article';
  @override
  String get deleteProductPrompt =>
      'Cette action supprimera le produit du catalogue.';
  @override
  String get protectedHistoryNote =>
      'Remarque : L\'historique des ventes, encaissements et mouvements de stock passés reste intégralement protégé et préservé.';
  @override
  String get filterArticlesPrompt =>
      'Filtrer les articles par nom, SKU ou code-barres...';
  @override
  String get noArticlesFoundInInventory =>
      'Aucun article trouvé dans l\'inventaire';

  // --- Purchasing & Receiving ---
  @override
  String get purchaseOrdersTitle => 'Achats & Commandes Fournisseurs';
  @override
  String get goodsReceivingTitle => 'Réception de Marchandises';
  @override
  String get newPurchaseOrder => 'Nouvelle commande';
  @override
  String get supplier => 'Fournisseur';
  @override
  String get orderReference => 'Réf. commande';
  @override
  String get expectedDelivery => 'Livraison prévue';
  @override
  String get receiveGoods => 'Réceptionner le bon';
  @override
  String get receivingCompleted => 'Réception enregistrée avec succès';
  @override
  String get noOrdersRecorded => 'Aucune commande ou réception enregistrée';
  @override
  String get registerSupplierReceipt => 'Enregistrer une réception fournisseur';
  @override
  String get invoiceOrDeliveryNote => 'N° Bon Livraison / Facture';
  @override
  String get addArticles => 'Ajouter des articles';
  @override
  String get qtyReceived => 'Qté Reçue';
  @override
  String get qtyDamaged => 'Défectueux';
  @override
  String get validateReceiving => 'Valider la réception';
  @override
  String get noArticlesInReceiving =>
      'Aucun article dans cette réception.\nSélectionnez ou scannez des articles à droite.';
  @override
  String get selectSupplierPrompt => 'Veuillez sélectionner un fournisseur';
  @override
  String get addAtLeastOneArticlePrompt =>
      'Veuillez ajouter au moins un article reçu';
  @override
  String get receivingSavedSuccess =>
      'Réception de marchandises enregistrée avec succès !';

  // --- Returns & Exchanges ---
  @override
  String get returnsExchangesTitle => 'Retours & Échanges de Vêtements';
  @override
  String get searchReceiptPrompt =>
      'Saisir le N° du ticket ou scanner le code-barres du ticket...';
  @override
  String get returnMode => 'Retour simple (Remboursement)';
  @override
  String get exchangeMode => 'Échange de taille / article';
  @override
  String get returnConditionSellable => 'Article en parfait état (Revenable)';
  @override
  String get returnConditionDamaged => 'Article défectueux / Endommagé';
  @override
  String get returnReason => 'Motif du retour';
  @override
  String get replacementItem => 'Article de remplacement';
  @override
  String get refundDueCustomer => 'Montant à rembourser au client';
  @override
  String get customerOwes => 'Montant restant dû par le client';
  @override
  String get netDifferenceZero => 'Échange équivalent (différence 0.000 TND)';
  @override
  String get completeReturnAction => 'Confirmer le retour';
  @override
  String get completeExchangeAction => 'Confirmer l\'échange';
  @override
  String get returnSuccess => 'Retour traité avec succès';
  @override
  String get exchangeSuccess => 'Échange finalisé avec succès';
  @override
  String get openRegisterSessionFirst =>
      'Veuillez d\'abord ouvrir une session de caisse';
  @override
  String get selectArticleToReturnPrompt =>
      'Veuillez sélectionner au moins un article à retourner';
  @override
  String get selectReplacementArticlePrompt =>
      'Veuillez sélectionner un article de remplacement';
  @override
  String get searchReceipt => 'RECHERCHER TICKET';
  @override
  String ticketNotFound(String receipt) =>
      'Aucun ticket trouvé pour "$receipt"';
  @override
  String get purchasedItemsToReturn => 'Articles achetés à retourner :';
  @override
  String get refundDetails => 'Détails du Remboursement';
  @override
  String get amountToRefund => 'Montant à Rembourser :';
  @override
  String get refundMethod => 'Mode de Remboursement :';
  @override
  String get paymentStoreCredit => 'Avoir Magasin';
  @override
  String get searchTicketPlaceholder =>
      'Saisissez le numéro de ticket ou scannez le ticket de caisse';
  @override
  String get priceDifference => 'Différence de Prix :';
  @override
  String get selectNewReplacementArticle =>
      'Sélectionner le nouvel article de remplacement :';
  @override
  String get returnReasonSize => 'Taille non adaptée';
  @override
  String get returnReasonDefault => 'Retour article';
  @override
  String get exchangeReasonDefault => 'Échange vêtement (taille / modèle)';
  @override
  String returnSuccessWithNumber(String number) =>
      'Retour #$number validé avec succès !';
  @override
  String exchangeSuccessWithDiff(String diff) =>
      'Échange validé ! Différence : $diff';

  // --- Labels ---
  @override
  String get labelStudioTitle => 'Studio d\'Étiquettes Code-Barres';
  @override
  String get selectProductForLabel =>
      'Sélectionner un article pour l\'étiquette';
  @override
  String get labelDimensions => 'Format de l\'étiquette (mm)';
  @override
  String get printCopies => 'Nombre d\'exemplaires';
  @override
  String get printLabelsAction => 'Imprimer les étiquettes';
  @override
  String get labelsSentSuccess =>
      'Étiquettes envoyées à l\'imprimante avec succès';
  @override
  String get labelRollFormat => 'Format du rouleau d\'étiquettes (mm)';
  @override
  String get formatJewelryAccessories => '40 x 25 mm (Bijoux / Accessoires)';
  @override
  String get formatStandardApparel => '40 x 30 mm (Standard Prêt-à-Porter)';
  @override
  String get formatLarge => '50 x 30 mm (Grand format)';
  @override
  String get formatCardboardTag => '60 x 40 mm (Carton / Cartonnette)';
  @override
  String get byStockCount => 'Selon Stock';
  @override
  String nLabels(int count) => '$count étiquette(s)';
  @override
  String get realThermalLabelPreview => 'Aperçu Réel de l\'Étiquette Thermique';
  @override
  String get selectArticleToPreview =>
      'Veuillez sélectionner un article pour visualiser l\'étiquette';
  @override
  String selectedFormat(int w, int h) => 'Format sélectionné : $w x $h mm';
  @override
  String labelsSentToPrinter(int count) =>
      '$count étiquette(s) envoyée(s) à l\'imprimante TSPL/ZPL';
  @override
  String printError(String error) => 'Erreur d\'impression: $error';

  // --- Shifts & Z-Report ---
  @override
  String get shiftManagementTitle => 'Gestion de Caisse & Z-Report';
  @override
  String get activeShiftInfo => 'Session de caisse en cours';
  @override
  String get openedAt => 'Ouverte à';
  @override
  String get cashInDrawer => 'Espèces théoriques en caisse';
  @override
  String get payInAction => 'Entrée de caisse (Appoint)';
  @override
  String get payOutAction => 'Sortie de caisse (Dépense)';
  @override
  String get payInTitle => 'Entrée d\'espèces en caisse';
  @override
  String get payOutTitle => 'Sortie d\'espèces de la caisse';
  @override
  String get reasonLabel => 'Motif / Justification';
  @override
  String get closeRegisterTitle => 'Clôture de Caisse & Z-Report';
  @override
  String get countCashAction => 'Compter & Clôturer la caisse';
  @override
  String get countedCash => 'Espèces réelles comptées';
  @override
  String get calculatedCash => 'Espèces attendues';
  @override
  String get cashDifference => 'Écart de caisse';
  @override
  String get printZReport => 'Imprimer le ticket Z';
  @override
  String get registerClosedSuccess =>
      'Caisse clôturée avec succès. Ticket Z généré.';
  @override
  String get openRegisterShift => 'Ouvrir la session de caisse';
  @override
  String get enterInitialCashFloat =>
      'Saisissez le fond de caisse initial (TND) :';
  @override
  String get payInCash => 'Entrée d\'espèces (Appoint)';
  @override
  String get payOutCash => 'Sortie d\'espèces (Prélèvement / Dépense)';
  @override
  String get amountTnd => 'Montant (TND)';
  @override
  String get reasonOrProof => 'Motif / Justificatif *';
  @override
  String get payInReasonExample => 'ex: Monnaie pièces';
  @override
  String get payOutReasonExample => 'ex: Dépense pressing / Prélèvement gérant';
  @override
  String get validateMovement => 'Valider le mouvement';
  @override
  String get standardShiftCloseNote => 'Clôture de caisse standard';
  @override
  String get shiftClosedZReportSuccess =>
      'Session de caisse clôturée avec succès (Z-Report généré)';
  @override
  String get refreshTotals => 'Actualiser les totaux';
  @override
  String get registerCurrentlyClosed => 'Caisse Actuellement Fermée';
  @override
  String get registerTerminal => 'Poste';
  @override
  String get openRegisterSessionAction => 'OUVRIR LA SESSION DE CAISSE';
  @override
  String shiftOpenedAt(String time) => 'Session ouverte à $time';
  @override
  String get cashSales => 'Ventes en Espèces (+):';
  @override
  String get cardSales => 'Ventes par Carte Bancaire:';
  @override
  String get cashRefunds => 'Remboursements Espèces (-):';
  @override
  String get manualCashIn => 'Entrées manuelles espèces (+):';
  @override
  String get manualCashOut => 'Sorties manuelles / Dépôt (-):';
  @override
  String get expectedCashBalance => 'SOLDE ESPÈCES ATTENDU EN CAISSE :';
  @override
  String get blindCountTitle => 'Comptage Réel & Clôture (Z-Report)';
  @override
  String get enterCountedCashPrompt =>
      'Saisissez le montant total d\'espèces compté physiquement dans le tiroir :';
  @override
  String get closeRegisterZReportAction => 'CLÔTURER LA CAISSE (Z-REPORT)';

  // --- Reports ---
  @override
  String get reportsTitle => 'Rapports & Statistiques Financières';
  @override
  String get salesAndMarginTab => 'Ventes & Marge Brute';
  @override
  String get sizePerformanceTab => 'Performance des Tailles';
  @override
  String get stockValuationTab => 'Valorisation du Stock';
  @override
  String get periodToday => 'Aujourd\'hui';
  @override
  String get periodWeek => '7 derniers jours';
  @override
  String get periodMonth => '30 derniers jours';
  @override
  String get totalSales => 'Chiffre d\'affaires brut';
  @override
  String get grossMargin => 'Marge brute réalisée';
  @override
  String get marginRate => 'Taux de marge';
  @override
  String get totalTransactions => 'Nombre de transactions';
  @override
  String get averageBasket => 'Panier moyen';
  @override
  String get totalCostValue => 'Valeur stock au coût';
  @override
  String get totalRetailValue => 'Valeur stock à la vente';
  @override
  String get potentialProfit => 'Plus-value potentielle';
  @override
  String get analysisPeriod => 'Période d\'analyse :';
  @override
  String get netSalesRevenue => 'Chiffre d\'Affaires Net';
  @override
  String get purchaseCostGoods => 'Coût d\'Achat Marchandises';
  @override
  String get financialDetailPeriod => 'Détail Financier de la Période';
  @override
  String get totalCompletedSalesCount => 'Nombre total de ventes clôturées';
  @override
  String get grantedDiscounts => 'Remises accordées (-)';
  @override
  String get refundsAndReturns => 'Remboursements et retours (-)';
  @override
  String get actualNetSales => 'Chiffre d\'Affaires Net Réel';
  @override
  String get costOfGoodsSold => 'Coût des marchandises vendues (COGS)';
  @override
  String get netGrossProfit => 'Bénéfice Brut Net';
  @override
  String get paymentMethodBreakdown => 'Répartition par Mode de Paiement';
  @override
  String get noPaymentsInPeriod => 'Aucun paiement sur la période';
  @override
  String get noSalesForSizeAnalysis =>
      'Aucune vente enregistrée sur cette période pour analyser les tailles';
  @override
  String get salesByGarmentSize => 'Ventes par Taille de Vêtement';
  @override
  String get sizeDemandInsight =>
      'Identifiez les tailles les plus demandées pour optimiser vos réassorts :';
  @override
  String nPieces(int count) => '$count pièces';
  @override
  String get lowStockAlertsCount => 'Alertes Stock Faible (≤ 2)';
  @override
  String get outOfStockArticlesCount => 'Articles en Rupture (0)';
  @override
  String get totalUnitsInStock => 'Pièces Totales en Stock';

  // --- Settings ---
  @override
  String get settingsTitle => 'Paramètres & Configuration';
  @override
  String get tabGeneral => 'GÉNÉRAL & LANGUE';
  @override
  String get tabHardware => 'MATÉRIEL POS';
  @override
  String get tabBackup => 'SAUVEGARDE & INTÉGRITÉ';
  @override
  String get tabImportExport => 'IMPORT / EXPORT CSV';
  @override
  String get languageSection => 'Langue de l\'application';
  @override
  String get selectLanguage => 'Choisir la langue d\'affichage';
  @override
  String get languageFr => 'Français (Défaut)';
  @override
  String get languageAr => 'العربية (RTL)';
  @override
  String get languageEn => 'English';
  @override
  String get storeSection => 'Informations de la Boutique';
  @override
  String get companyName => 'Raison sociale';
  @override
  String get storeName => 'Nom du point de vente';
  @override
  String get fiscalId => 'Matricule Fiscal / Code TVA';
  @override
  String get phone => 'Téléphone';
  @override
  String get address => 'Adresse';
  @override
  String get printerThermal => 'Imprimante Ticket de Caisse (ESC/POS)';
  @override
  String get printerLabel => 'Imprimante Étiquettes (TSPL / ZPL)';
  @override
  String get customerDisplay => 'Afficheur Client (VFD / LCD)';
  @override
  String get testPrinter => 'Imprimer ticket test';
  @override
  String get testLabelPrinter => 'Imprimer étiquette test';
  @override
  String get testCustomerDisplay => 'Tester afficheur client';
  @override
  String get testCashDrawer => 'Ouvrir tiroir-caisse';
  @override
  String get backupDatabase => 'Créer une sauvegarde SQLite atomique';
  @override
  String get databaseIntegrity => 'Contrôle d\'intégrité de la base';
  @override
  String get runDiagnostics => 'Lancer le diagnostic';
  @override
  String get backupSuccess => 'Sauvegarde SQLite créée avec succès !';
  @override
  String get diagnosticsPass =>
      'Base de données intègre. Aucune anomalie détectée.';
  @override
  String get importCsv => 'Importer le catalogue (CSV)';
  @override
  String get exportCsv => 'Exporter le catalogue (CSV)';

  // --- Auth & Access ---
  @override
  String get loginTitle => 'Connexion Caisse';
  @override
  String get selectUser => 'Sélectionnez votre compte';
  @override
  String get enterPin => 'Saisissez votre code PIN (4 chiffres)';
  @override
  String get invalidPin => 'Code PIN incorrect';
  @override
  String get screenLocked => 'Session Verrouillée';
  @override
  String get unlockAction => 'Déverrouiller';
  @override
  String get managerOverrideTitle => 'Autorisation Responsable Requise';
  @override
  String get managerOverrideReason =>
      'Cette action nécessite l\'approbation d\'un Responsable ou Propriétaire';
  @override
  String get authorizeAction => 'Autoriser';
  @override
  String get welcomeTitle => 'Bienvenue sur JazzPOS';
  @override
  String get noUsersConfigured =>
      'Aucun compte configuré. Lancez l\'assistant de configuration initiale.';
  @override
  String get launchSetupWizard => 'Lancer la configuration';
  @override
  String get posAppSubtitle => 'Système Point de Vente Prêt-à-Porter';
  @override
  String get setupWizardButton => 'Assistant d\'installation / Ajout';
  @override
  String pinForUser(String name) => 'Code PIN de $name';
  @override
  String get selectUserRequired => 'Veuillez sélectionner un utilisateur';
  @override
  String get enterPinRequired => 'Veuillez saisir votre code PIN';
  @override
  String get loginAction => 'CONNEXION';
  @override
  String activeSession(String name, String role) =>
      'Session active : $name ($role)';
  @override
  String get switchCashier => 'Changer de caissier';
  @override
  String get managerEmergencyUnlock => 'Déblocage Manager';
  @override
  String get managerOverrideUnlockTitle =>
      'Déverrouillage d\'urgence de la caisse';
  @override
  String get managerPinInvalid => 'Code PIN responsable invalide';
  @override
  String get selectVariantSubtitle => 'Sélectionnez la taille et la couleur';
  @override
  String unitsInStock(int count) => '$count en stock';
  @override
  String get receiptPreviewTitle => 'Aperçu Ticket de Caisse';
  @override
  String get receiptPreviewDuplicate => 'Aperçu Ticket (Duplicata)';
  @override
  String get receiptPrintSuccess => 'Ticket envoyé à l\'imprimante avec succès';
  @override
  String receiptPrintError(String error) => 'Erreur d\'impression : $error';
  @override
  String get reprintAction => 'Réimprimer';
  @override
  String get printingInProgress => 'Impression en cours...';

  // --- Formatting Helpers ---
  @override
  String get currencySymbol => 'TND';

  @override
  String categoryName(String rawName) {
    switch (rawName.trim().toLowerCase()) {
      case 'hauts & chemises':
      case 'tops & shirts':
      case 'قمصان وبلوزات':
        return 'Hauts & Chemises';
      case 'pantalons & jeans':
      case 'pants & jeans':
      case 'سراويل وجينز':
        return 'Pantalons & Jeans';
      case 'robes & ensembles':
      case 'dresses & sets':
      case 'فساتين وأطقم':
        return 'Robes & Ensembles';
      case 'vestes & manteaux':
      case 'jackets & coats':
      case 'سترات ومعاطف':
        return 'Vestes & Manteaux';
      case 'accessoires':
      case 'accessories':
      case 'إكسسوارات':
        return 'Accessoires';
      case 'chaussures':
      case 'shoes':
      case 'أحذية':
        return 'Chaussures';
      case 'hommes':
      case 'men':
      case 'رجال':
        return 'Hommes';
      case 'femmes':
      case 'women':
      case 'نساء':
        return 'Femmes';
      case 'enfants':
      case 'children':
      case 'أطفال':
        return 'Enfants';
      default:
        return rawName;
    }
  }

  @override
  String formatCurrency(double amount) => '${amount.toStringAsFixed(3)} TND';
  @override
  String formatStock(int count) => '$count pièce${count > 1 ? 's' : ''}';
}
