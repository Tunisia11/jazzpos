class PrinterQueuePolicy {
  static bool isVirtual(String name) => RegExp(r'print to pdf|onenote|\bfax\b|\bxps\b|pdfcreator|pdf24|adobe pdf|microsoft.*document', caseSensitive:false).hasMatch(name);
  static bool looksLikeLabel(String name) => RegExp(r'zebra|zdesigner|zd420|gk420|godex|\btsc\b|label|etiquette|étiquette',caseSensitive:false).hasMatch(name);
}
