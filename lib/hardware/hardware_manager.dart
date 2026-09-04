import 'dart:io';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'barcode_scanner/barcode_scanner_interface.dart';
import 'barcode_scanner/fake_barcode_scanner.dart';
import 'barcode_scanner/keyboard_barcode_scanner.dart';
import 'cash_drawer/cash_drawer_interface.dart';
import 'cash_drawer/fake_cash_drawer.dart';
import 'cash_drawer/printer_kick_cash_drawer.dart';
import 'customer_display/customer_display_interface.dart';
import 'customer_display/fake_customer_display.dart';
import 'label_printer/fake_label_printer.dart';
import 'label_printer/label_document.dart';
import 'label_printer/label_printer_interface.dart';
import 'receipt_printer/fake_receipt_printer.dart';
import 'receipt_printer/receipt_document.dart';
import 'receipt_printer/receipt_printer_interface.dart';

/// Centralized Hardware Manager coordinating peripheral POS devices.
/// Provides seamless switching between real hardware and macOS simulators.
class HardwareManager {
  static final HardwareManager instance = HardwareManager._();
  HardwareManager._();

  late ReceiptPrinter receiptPrinter;
  late LabelPrinter labelPrinter;
  late BarcodeScanner barcodeScanner;
  late CashDrawer cashDrawer;
  late CustomerDisplay customerDisplay;

  bool _isInitialized = false;

  void initialize({
    ReceiptPrinter? customReceiptPrinter,
    LabelPrinter? customLabelPrinter,
    BarcodeScanner? customBarcodeScanner,
    CashDrawer? customCashDrawer,
    CustomerDisplay? customCustomerDisplay,
  }) {
    if (_isInitialized) return;

    // Use provided custom or fallback to simulated for macOS testing
    receiptPrinter = customReceiptPrinter ?? FakeReceiptPrinter();
    labelPrinter = customLabelPrinter ?? FakeLabelPrinter();

    // On desktop, default to USB HID keyboard scanner or fake scanner
    barcodeScanner = customBarcodeScanner ?? (Platform.isMacOS ? FakeBarcodeScanner() : KeyboardBarcodeScanner());
    barcodeScanner.startListening();

    cashDrawer = customCashDrawer ?? (customReceiptPrinter != null ? PrinterKickCashDrawer(printer: receiptPrinter) : FakeCashDrawer());
    customerDisplay = customCustomerDisplay ?? FakeCustomerDisplay();

    _isInitialized = true;
    PosLogger.instance.info('Hardware', 'Hardware Manager initialized. Target OS: ${Platform.operatingSystem}');
  }

  /// Print test receipt
  Future<void> testReceiptPrinter() async {
    final doc = ReceiptDocument(
      storeName: 'JAZZ POS TEST',
      storeAddress: 'Test Terminal, Avenue Habib Bourguiba, Tunis',
      storePhone: '+216 71 000 000',
      fiscalId: '00012345/A/M/000',
      receiptNumber: 'TEST-0001',
      dateTime: DateTime.now(),
      cashierName: 'Admin',
      registerCode: 'REG-01',
      lines: [
        const ReceiptLineItem(
          productName: 'T-Shirt Basic Coton',
          variantDescription: 'Noir / L',
          sku: 'TSH-BLK-L',
          barcode: '200123456789',
          quantity: 1,
          unitPrice: Money.fromMillimes(39900),
          total: Money.fromMillimes(39900),
        ),
      ],
      subtotal: const Money.fromMillimes(39900),
      discount: Money.zero,
      tax: Money.zero,
      total: const Money.fromMillimes(39900),
      payments: [
        const ReceiptPaymentItem(
          method: 'CASH',
          amount: Money.fromMillimes(39900),
          tendered: Money.fromMillimes(50000),
          change: Money.fromMillimes(10100),
        ),
      ],
      footerMessage: 'Hardware diagnostics test successful!',
    );

    await receiptPrinter.printReceipt(doc);
  }

  /// Print test label
  Future<void> testLabelPrinter() async {
    const doc = LabelDocument(
      storeName: 'JAZZ POS',
      productName: 'Chemise Slim Coton',
      brandName: 'Jazz Collection',
      color: 'Bleu Ciel',
      size: '42',
      sku: 'CHM-BLU-42',
      barcode: '200987654321',
      price: Money.fromMillimes(89900),
      oldPrice: Money.fromMillimes(120000),
      copies: 1,
    );

    await labelPrinter.printLabel(doc);
  }

  /// Test cash drawer kick
  Future<void> testCashDrawer() async {
    await cashDrawer.openDrawer();
  }

  /// Test customer display
  Future<void> testCustomerDisplay() async {
    await customerDisplay.showWelcome();
  }
}
