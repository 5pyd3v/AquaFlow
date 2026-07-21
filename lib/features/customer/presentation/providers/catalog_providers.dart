import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/catalog_repository.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepositoryImpl();
});

final categoriesProvider = FutureProvider<List<CategoryEntity>>((ref) async {
  final result = await ref.read(catalogRepositoryProvider).getCategories();
  return result.fold((failure) => throw failure, (data) => data);
});

/// Currently-selected category filter on the home/catalog screen. Null
/// means "All".
final selectedCategoryIdProvider = StateProvider<String?>((ref) => null);

/// Debounced search text driving the product grid.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Paginated product feed — re-fetches whenever category or search
/// query changes (both are watched). Refreshed when the customer
/// navigates back to the Shop tab to ensure vendor-added products
/// appear without manual pull-to-refresh.
final productListProvider =
    AsyncNotifierProvider<ProductListController, List<ProductEntity>>(ProductListController.new);

class ProductListController extends AsyncNotifier<List<ProductEntity>> {
  int _page = 0;
  bool _hasMore = true;
  static const _pageSize = 20;

  @override
  Future<List<ProductEntity>> build() async {
    // Re-run automatically when either filter changes.
    ref.watch(selectedCategoryIdProvider);
    ref.watch(searchQueryProvider);
    _page = 0;
    _hasMore = true;
    return _fetchPage(0);
  }

  Future<List<ProductEntity>> _fetchPage(int page) async {
    final categoryId = ref.read(selectedCategoryIdProvider);
    final query = ref.read(searchQueryProvider);
    final result = await ref.read(catalogRepositoryProvider).getProducts(
          categoryId: categoryId,
          searchQuery: query,
          page: page,
          pageSize: _pageSize,
        );
    return result.fold((failure) => throw failure, (data) {
      _hasMore = data.length == _pageSize;
      return data;
    });
  }

  bool get hasMore => _hasMore;

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;
    final current = state.valueOrNull ?? [];
    _page += 1;
    final nextPage = await _fetchPage(_page);
    state = AsyncData([...current, ...nextPage]);
  }

  Future<void> refresh() async {
    _page = 0;
    _hasMore = true;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchPage(0));
  }
}

final favoriteProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final result = await ref.read(catalogRepositoryProvider).getFavoriteProducts();
  return result.fold((failure) => throw failure, (data) => data);
});

final favoriteProductIdsProvider = Provider<Set<String>>((ref) {
  final favorites = ref.watch(favoriteProductsProvider).valueOrNull ?? [];
  return favorites.map((p) => p.id).toSet();
});
