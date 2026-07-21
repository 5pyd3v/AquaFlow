import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../customer/domain/entities/product_entity.dart';
import '../../domain/cart_item_entity.dart';

/// One active cart per vendor is enforced here — mixing bottles from
/// two different vendors into a single delivery doesn't make sense
/// operationally (two separate pickups), so adding a product from a
/// different vendor prompts the UI to clear the cart first.
class CartState {
  final String? vendorId;
  final List<CartItemEntity> items;

  const CartState({this.vendorId, this.items = const []});

  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
  double get subtotal => items.fold(0, (sum, item) => sum + item.lineTotal);
  double get depositTotal => items.fold(0, (sum, item) => sum + item.lineDeposit);
  bool get isEmpty => items.isEmpty;

  CartState copyWith({String? vendorId, List<CartItemEntity>? items}) {
    return CartState(vendorId: vendorId ?? this.vendorId, items: items ?? this.items);
  }
}

final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Returns false (and leaves state untouched) if adding this product
  /// would mix vendors — caller should confirm-and-clear first via
  /// [clearAndAdd].
  bool addProduct(ProductEntity product, {int quantity = 1}) {
    if (state.vendorId != null && state.vendorId != product.vendorId && state.items.isNotEmpty) {
      return false;
    }

    final existingIndex = state.items.indexWhere((i) => i.product.id == product.id);
    final updatedItems = [...state.items];

    if (existingIndex >= 0) {
      updatedItems[existingIndex] =
          updatedItems[existingIndex].copyWith(quantity: updatedItems[existingIndex].quantity + quantity);
    } else {
      updatedItems.add(CartItemEntity(product: product, quantity: quantity));
    }

    state = state.copyWith(vendorId: product.vendorId, items: updatedItems);
    return true;
  }

  void clearAndAdd(ProductEntity product, {int quantity = 1}) {
    state = CartState(vendorId: product.vendorId, items: [CartItemEntity(product: product, quantity: quantity)]);
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    final updatedItems = state.items
        .map((item) => item.product.id == productId ? item.copyWith(quantity: quantity) : item)
        .toList();
    state = state.copyWith(items: updatedItems);
  }

  void removeProduct(String productId) {
    final updatedItems = state.items.where((item) => item.product.id != productId).toList();
    state = updatedItems.isEmpty ? const CartState() : state.copyWith(items: updatedItems);
  }

  int quantityOf(String productId) {
    final match = state.items.where((i) => i.product.id == productId);
    return match.isEmpty ? 0 : match.first.quantity;
  }

  void clear() => state = const CartState();
}
