import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../customer/domain/entities/product_entity.dart';
import '../../../customer/presentation/providers/catalog_providers.dart';
import '../providers/vendor_providers.dart';

/// Add mode when [existingProduct] is null, edit mode otherwise. Image
/// upload goes straight to the `products` Supabase Storage bucket
/// (public read, vendor-scoped write — see storage migration 0004)
/// rather than pretending with a local file path that would break
/// the moment the vendor reinstalls the app.
class AddEditProductScreen extends ConsumerStatefulWidget {
  final ProductEntity? existingProduct;
  const AddEditProductScreen({super.key, this.existingProduct});

  @override
  ConsumerState<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends ConsumerState<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _sizeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _depositController;
  late final TextEditingController _discountController;
  late final TextEditingController _stockController;

  String? _categoryId;
  String? _imageUrl;
  Uint8List? _pickedImageBytes;
  bool _uploading = false;
  bool _saving = false;

  bool get _isEditing => widget.existingProduct != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _nameController = TextEditingController(text: p?.name ?? '');
    _brandController = TextEditingController(text: p?.brand ?? '');
    _sizeController = TextEditingController(text: p?.sizeLiters.toString() ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _priceController = TextEditingController(text: p?.price.toString() ?? '');
    _depositController = TextEditingController(text: p?.depositAmount.toString() ?? '0');
    _discountController = TextEditingController(text: p?.discountPercent.toString() ?? '0');
    _stockController = TextEditingController(text: p?.stockQuantity.toString() ?? '');
    _categoryId = p?.categoryId;
    _imageUrl = p?.imageUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _sizeController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    _discountController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _pickedImageBytes = bytes);
    }
  }

  Future<String?> _uploadImageIfNeeded(String vendorId) async {
    if (_pickedImageBytes == null) return _imageUrl;
    setState(() => _uploading = true);
    try {
      final path = '$vendorId/${const Uuid().v4()}.jpg';
      await SupabaseConfig.client.storage.from(SupabaseConfig.bucketProducts).uploadBinary(
            path,
            _pickedImageBytes!,
            fileOptions: const sb.FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return SupabaseConfig.client.storage.from(SupabaseConfig.bucketProducts).getPublicUrl(path);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final vendor = await ref.read(myVendorProvider.future);
    final imageUrl = await _uploadImageIfNeeded(vendor.id);

    final name = _nameController.text.trim();
    final brand = _brandController.text.trim().isEmpty ? null : _brandController.text.trim();
    final size = double.parse(_sizeController.text.trim());
    final description = _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
    final price = double.parse(_priceController.text.trim());
    final deposit = double.tryParse(_depositController.text.trim()) ?? 0;
    final discount = double.tryParse(_discountController.text.trim()) ?? 0;
    final stock = int.parse(_stockController.text.trim());

    final repo = ref.read(vendorRepositoryProvider);
    final result = _isEditing
        ? await repo.updateProduct(ProductEntity(
            id: widget.existingProduct!.id,
            vendorId: vendor.id,
            vendorName: vendor.businessName ?? '',
            vendorRating: widget.existingProduct!.vendorRating,
            categoryId: _categoryId,
            name: name,
            brand: brand,
            sizeLiters: size,
            description: description,
            imageUrl: imageUrl,
            price: price,
            depositAmount: deposit,
            discountPercent: discount,
            stockQuantity: stock,
            averageDeliveryMinutes: widget.existingProduct!.averageDeliveryMinutes,
            rating: widget.existingProduct!.rating,
            isAvailable: widget.existingProduct!.isAvailable,
          ))
        : await repo.createProduct(
            vendorId: vendor.id,
            categoryId: _categoryId,
            name: name,
            brand: brand,
            sizeLiters: size,
            description: description,
            imageUrl: imageUrl,
            price: price,
            depositAmount: deposit,
            discountPercent: discount,
            stockQuantity: stock,
          );

    if (!mounted) return;
    setState(() => _saving = false);

    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (_) {
        ref.invalidate(vendorProductsProvider);
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Product' : 'Add Product')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ImagePicker(pickedImageBytes: _pickedImageBytes, existingUrl: _imageUrl, onTap: _pickImage),
            const SizedBox(height: 20),
            AppTextField(
              controller: _nameController,
              label: 'Product Name',
              hint: 'e.g. Nestlé Pure Life 19L',
              validator: (v) => Validators.required(v, field: 'Name'),
            ),
            const SizedBox(height: 16),
            AppTextField(controller: _brandController, label: 'Brand (optional)'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _sizeController,
                    label: 'Size (Liters)',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => Validators.positiveNumber(v, field: 'Size'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _stockController,
                    label: 'Stock Quantity',
                    keyboardType: TextInputType.number,
                    validator: (v) => Validators.positiveNumber(v, field: 'Stock'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox(),
              data: (categories) => DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                hint: const Text('Category'),
                items: categories
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _descriptionController,
              label: 'Description (optional)',
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _priceController,
                    label: 'Price (Rs.)',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => Validators.positiveNumber(v, field: 'Price'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _depositController,
                    label: 'Bottle Deposit (Rs.)',
                    hint: 'Optional, customer opts in',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _discountController,
              label: 'Discount % (optional)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: _isEditing ? 'Save Changes' : 'Add Product',
              isLoading: _saving || _uploading,
              onPressed: _save,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _ImagePicker extends StatelessWidget {
  final Uint8List? pickedImageBytes;
  final String? existingUrl;
  final VoidCallback onTap;
  const _ImagePicker({required this.pickedImageBytes, required this.existingUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: pickedImageBytes != null
            ? Image.memory(pickedImageBytes!, fit: BoxFit.cover, width: double.infinity)
            : existingUrl != null
                ? Image.network(existingUrl!, fit: BoxFit.cover, width: double.infinity)
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_a_photo_outlined, color: AppColors.textTertiary, size: 32),
                        SizedBox(height: 8),
                        Text('Add product photo', style: TextStyle(color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
      ),
    );
  }
}
