import '../../../../core/utils/result.dart';
import '../entities/category_entity.dart';
import '../entities/product_entity.dart';

abstract class CatalogRepository {
  Future<Result<List<CategoryEntity>>> getCategories();

  Future<Result<List<ProductEntity>>> getProducts({
    String? categoryId,
    String? searchQuery,
    int page = 0,
    int pageSize = 20,
  });

  Future<Result<ProductEntity>> getProductById(String productId);

  Future<Result<List<ProductEntity>>> getFavoriteProducts();

  Future<Result<void>> toggleFavoriteProduct(String productId, bool isFavorite);
}
