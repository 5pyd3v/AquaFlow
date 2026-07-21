import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/customer_wallet_repository.dart';
import '../../domain/entities/wallet_entity.dart';

final customerWalletRepositoryProvider =
    Provider<CustomerWalletRepository>((ref) => CustomerWalletRepository());

final customerWalletSummaryProvider =
    FutureProvider.autoDispose<CustomerWalletSummaryEntity>((ref) async {
  final result = await ref.read(customerWalletRepositoryProvider).getWalletSummary();
  return result.fold((f) => throw f, (d) => d);
});
