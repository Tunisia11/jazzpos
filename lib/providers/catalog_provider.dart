import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/catalog_service.dart';
import 'app_providers.dart';

class CatalogState {
  final String searchQuery;
  final String? selectedCategoryId;
  final List<VariantSearchResult> variants;
  final List<Category> categories;
  final bool isLoading;

  /// True when the result hit the load limit, so the real total is larger.
  final bool isTruncated;

  const CatalogState({
    this.searchQuery = '',
    this.selectedCategoryId,
    this.variants = const [],
    this.categories = const [],
    this.isLoading = false,
    this.isTruncated = false,
  });

  CatalogState copyWith({
    String? searchQuery,
    String? selectedCategoryId,
    bool clearCategory = false,
    List<VariantSearchResult>? variants,
    List<Category>? categories,
    bool? isLoading,
    bool? isTruncated,
  }) {
    return CatalogState(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId: clearCategory
          ? null
          : (selectedCategoryId ?? this.selectedCategoryId),
      variants: variants ?? this.variants,
      categories: categories ?? this.categories,
      isLoading: isLoading ?? this.isLoading,
      isTruncated: isTruncated ?? this.isTruncated,
    );
  }
}

class CatalogNotifier extends StateNotifier<CatalogState> {
  /// Variants loaded for the POS grid. A result of exactly this size means
  /// more exist, and the UI shows "N+" instead of a wrong total.
  static const int loadLimit = 300;

  final CatalogService catalogService;
  final AppDatabase db;
  int _requestId = 0;

  CatalogNotifier(this.catalogService, this.db) : super(const CatalogState()) {
    refresh();
  }

  /// Loads variants for the current search + category. Only the newest
  /// request may update the state, so quick switching never shows stale data.
  Future<void> _load({bool reloadCategories = false}) async {
    final id = ++_requestId;
    state = state.copyWith(isLoading: true);
    try {
      final categories = reloadCategories
          ? await db.select(db.categories).get()
          : null;
      final variants = await catalogService.searchVariants(
        state.searchQuery,
        limit: loadLimit,
        categoryId: state.selectedCategoryId,
      );
      if (id != _requestId) return;
      state = state.copyWith(
        categories: categories,
        variants: variants,
        isLoading: false,
        isTruncated: variants.length >= loadLimit,
      );
    } catch (e) {
      if (id != _requestId) return;
      PosLogger.instance.warning('Catalog', 'Could not load catalog: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Reload everything, e.g. after a sale or stock change.
  Future<void> refresh() => _load(reloadCategories: true);

  Future<void> search(String query) {
    state = state.copyWith(searchQuery: query);
    return _load();
  }

  /// Selecting the active category again, or null ("All"), clears the filter.
  Future<void> selectCategory(String? categoryId) {
    final clear = categoryId == null || state.selectedCategoryId == categoryId;
    state = state.copyWith(
      selectedCategoryId: clear ? null : categoryId,
      clearCategory: clear,
    );
    return _load();
  }
}

final catalogNotifierProvider =
    StateNotifierProvider<CatalogNotifier, CatalogState>((ref) {
      return CatalogNotifier(
        ref.watch(catalogServiceProvider),
        ref.watch(databaseProvider),
      );
    });
