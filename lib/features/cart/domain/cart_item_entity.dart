import 'package:equatable/equatable.dart';
import '../../customer/domain/entities/product_entity.dart';

/// Cart lives entirely client-side (Riverpod state) until checkout,
/// where it's translated into `orders` + `order_items` rows in one
/// transaction via the orders repository. This mirrors how every
/// food-delivery app works — no reason to round-trip to the DB on
/// every quantity tap.
class CartItemEntity extends Equatable {
  final ProductEntity product;
  final int quantity;

  const CartItemEntity({required this.product, required this.quantity});

  double get lineTotal => product.discountedPrice * quantity;
  double get lineDeposit => product.depositAmount * quantity;

  CartItemEntity copyWith({int? quantity}) =>
      CartItemEntity(product: product, quantity: quantity ?? this.quantity);

  @override
  List<Object?> get props => [product, quantity];
}
