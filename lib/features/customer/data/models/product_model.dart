import '../../domain/entities/product_entity.dart';

/// Maps a Supabase row from `products` joined with `vendors(business_name, rating)`
/// e.g.:
/// ```
/// select('*, vendors(business_name, rating)')
/// ```
class ProductModel extends ProductEntity {
  const ProductModel({
    required super.id,
    required super.vendorId,
    required super.vendorName,
    required super.vendorRating,
    super.categoryId,
    required super.name,
    super.brand,
    required super.sizeLiters,
    super.description,
    super.imageUrl,
    required super.price,
    required super.depositAmount,
    required super.discountPercent,
    required super.stockQuantity,
    required super.averageDeliveryMinutes,
    required super.rating,
    required super.isAvailable,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final vendor = json['vendors'] as Map<String, dynamic>?;
    return ProductModel(
      id: json['id'] as String,
      vendorId: json['vendor_id'] as String,
      vendorName: vendor?['business_name'] as String? ?? 'Vendor',
      vendorRating: (vendor?['rating'] as num?)?.toDouble() ?? 5.0,
      categoryId: json['category_id'] as String?,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      sizeLiters: (json['size_liters'] as num).toDouble(),
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      price: (json['price'] as num).toDouble(),
      depositAmount: (json['deposit_amount'] as num?)?.toDouble() ?? 0,
      discountPercent: (json['discount_percent'] as num?)?.toDouble() ?? 0,
      stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 0,
      averageDeliveryMinutes: (json['average_delivery_minutes'] as num?)?.toInt() ?? 45,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      isAvailable: json['is_available'] as bool? ?? true,
    );
  }
}
