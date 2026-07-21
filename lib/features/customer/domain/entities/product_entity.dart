import 'package:equatable/equatable.dart';

/// Domain representation of a single sellable water product (a
/// vendor's SKU), matching `products` joined with a bit of `vendors`
/// context needed for display (name, rating, distance).
class ProductEntity extends Equatable {
  final String id;
  final String vendorId;
  final String vendorName;
  final double vendorRating;
  final String? categoryId;
  final String name;
  final String? brand;
  final double sizeLiters;
  final String? description;
  final String? imageUrl;
  final double price;
  final double depositAmount;
  final double discountPercent;
  final int stockQuantity;
  final int averageDeliveryMinutes;
  final double rating;
  final bool isAvailable;

  const ProductEntity({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    required this.vendorRating,
    this.categoryId,
    required this.name,
    this.brand,
    required this.sizeLiters,
    this.description,
    this.imageUrl,
    required this.price,
    required this.depositAmount,
    required this.discountPercent,
    required this.stockQuantity,
    required this.averageDeliveryMinutes,
    required this.rating,
    required this.isAvailable,
  });

  double get discountedPrice =>
      discountPercent > 0 ? price - (price * discountPercent / 100) : price;

  bool get hasDiscount => discountPercent > 0;
  bool get inStock => stockQuantity > 0 && isAvailable;

  @override
  List<Object?> get props => [
        id,
        vendorId,
        vendorName,
        vendorRating,
        categoryId,
        name,
        brand,
        sizeLiters,
        description,
        imageUrl,
        price,
        depositAmount,
        discountPercent,
        stockQuantity,
        averageDeliveryMinutes,
        rating,
        isAvailable,
      ];
}
