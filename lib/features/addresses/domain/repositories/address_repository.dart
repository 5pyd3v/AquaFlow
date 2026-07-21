import '../../../../core/utils/result.dart';
import '../entities/address_entity.dart';

abstract class AddressRepository {
  Future<Result<List<AddressEntity>>> getAddresses();

  Future<Result<AddressEntity>> addAddress({
    required AddressLabel label,
    required String fullAddress,
    required double latitude,
    required double longitude,
    String? landmark,
    bool setAsDefault = false,
  });

  Future<Result<void>> updateAddress(AddressEntity address);

  Future<Result<void>> deleteAddress(String addressId);

  Future<Result<void>> setDefaultAddress(String addressId);
}
