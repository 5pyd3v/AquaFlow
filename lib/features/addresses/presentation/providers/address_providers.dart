import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/result.dart';
import '../../data/repositories/address_repository_impl.dart';
import '../../domain/entities/address_entity.dart';
import '../../domain/repositories/address_repository.dart';

final addressRepositoryProvider = Provider<AddressRepository>((ref) {
  return AddressRepositoryImpl();
});

/// Cached address list, refreshed via `ref.invalidate` after add/delete
/// so every screen referencing it (checkout, address book) stays in sync.
final addressListProvider =
    AsyncNotifierProvider<AddressListController, List<AddressEntity>>(
        AddressListController.new);

class AddressListController extends AsyncNotifier<List<AddressEntity>> {
  @override
  Future<List<AddressEntity>> build() async {
    final result = await ref.read(addressRepositoryProvider).getAddresses();
    return result.fold((failure) => throw failure, (data) => data);
  }

  Future<Result<AddressEntity>> addAddress({
    required AddressLabel label,
    required String fullAddress,
    required double latitude,
    required double longitude,
    String? landmark,
    bool setAsDefault = false,
  }) async {
    final result = await ref.read(addressRepositoryProvider).addAddress(
          label: label,
          fullAddress: fullAddress,
          latitude: latitude,
          longitude: longitude,
          landmark: landmark,
          setAsDefault: setAsDefault,
        );
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> deleteAddress(String addressId) async {
    final result = await ref.read(addressRepositoryProvider).deleteAddress(addressId);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> setDefault(String addressId) async {
    final result = await ref.read(addressRepositoryProvider).setDefaultAddress(addressId);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }
}

/// The address selected for the current checkout session (transient,
/// not persisted) — defaults to whichever address is flagged default.
final selectedAddressIdProvider = StateProvider<String?>((ref) => null);
