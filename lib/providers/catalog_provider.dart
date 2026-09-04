import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'app_providers.dart';

class CatalogState {
  final String searchQuery;
  final String? selectedCategoryId;
  final List<VariantSearchResult> variants;
  final List<Category> categories;
  final bool isLoading;

  const CatalogState({
    this.searchQuery = '',
    this.selectedCategoryId,
    this.variants = const [],
    this.categories = const [],
    this.isLoading = false,
  });

  CatalogState copyWith({
    String? searchQuery,
    String? selectedCategoryId,
    bool clearCategory = false,
    List<VariantSearchResult>? variants,
    List<Category>? categories,
    bool? isLoading,
  }) {
    return CatalogState(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId: clearCategory ? null : (selectedCategoryId ?? this.selectedCategoryId),
      variants: variants ?? this.variants,
      categories: categories ?? this.categories,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class CatalogNotifier extends StateNotifier<CatalogState> {
  final CatalogService catalogService;
  final AppDatabase db;

  CatalogNotifier(this.catalogService, this.db) : super(const CatalogState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final categories = await db.select(db.categories).get();
    final variants = await catalogService.searchVariants(state.searchQuery);
    state = state.copyWith(
      categories: categories,
      variants: variants,
      isLoading: false,
    );
  }

  Future<void> search(String query) async {
    state = state.copyWith(searchQuery: query, isLoading: true);
    final variants = await catalogService.searchVariants(query);
    state = state.copyWith(variants: variants, isLoading: false);
  }

  void selectCategory(String? categoryId) {
    if (state.selectedCategoryId == categoryId) {
      state = state.copyWith(clearCategory: true);
    } else {
      state = state.copyWith(selectedCategoryId: categoryId);
    }
  }
}

final catalogNotifierProvider = StateNotifierProvider<CatalogNotifier, CatalogState>((ref) {
  return CatalogNotifier(
    ref.watch(catalogServiceProvider),
    ref.watch(databaseProvider),
  );
});
