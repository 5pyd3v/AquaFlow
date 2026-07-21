import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  final sb.SupabaseClient _client;
  CatalogRepositoryImpl({sb.SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  @override
  Future<Result<List<CategoryEntity>>> getCategories() async {
    try {
      final rows = await _client
          .from(SupabaseConfig.categories)
          .select()
          .eq('is_active', true)
          .order('sort_order');
      final categories = (rows as List)
          .map((row) => CategoryModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(categories);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  /// Returns the vendor_id the signed-in customer is linked to, or null
  /// if there's no session / no linked vendor. Customers only ever see
  /// their own vendor's catalog.
  Future<String?> _customerVendorId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from(SupabaseConfig.customers)
        .select('vendor_id')
        .eq('profile_id', userId)
        .maybeSingle();
    return row?['vendor_id'] as String?;
  }

  @override
  Future<Result<List<ProductEntity>>> getProducts({
    String? categoryId,
    String? searchQuery,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      // Scope the catalog to the customer's own vendor. Without a linked
      // vendor there's nothing to show — return an empty list rather than
      // every vendor's products.
      final vendorId = await _customerVendorId();
      if (vendorId == null) {
        return const Success([]);
      }

      var query = _client
          .from(SupabaseConfig.products)
          .select('*, vendors(business_name, rating)')
          .eq('is_available', true)
          .eq('vendor_id', vendorId);

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        query = query.ilike('name', '%${searchQuery.trim()}%');
      }

      final from = page * pageSize;
      final to = from + pageSize - 1;

      final rows = await query.order('created_at', ascending: false).range(from, to);

      final products = (rows as List)
          .map((row) => ProductModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(products);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<ProductEntity>> getProductById(String productId) async {
    try {
      final row = await _client
          .from(SupabaseConfig.products)
          .select('*, vendors(business_name, rating)')
          .eq('id', productId)
          .single();
      return Success(ProductModel.fromJson(row));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<ProductEntity>>> getFavoriteProducts() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return const Success([]);

      final rows = await _client
          .from(SupabaseConfig.favorites)
          .select('product_id, products(*, vendors(business_name, rating))')
          .eq('customer_profile_id', userId)
          .not('product_id', 'is', null);

      final products = (rows as List)
          .where((row) => row['products'] != null)
          .map((row) => ProductModel.fromJson(row['products'] as Map<String, dynamic>))
          .toList();
      return Success(products);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> toggleFavoriteProduct(String productId, bool isFavorite) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in to do that.'));
      }
      if (isFavorite) {
        await _client.from(SupabaseConfig.favorites).insert({
          'customer_profile_id': userId,
          'product_id': productId,
        });
      } else {
        await _client
            .from(SupabaseConfig.favorites)
            .delete()
            .eq('customer_profile_id', userId)
            .eq('product_id', productId);
      }
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }
}
