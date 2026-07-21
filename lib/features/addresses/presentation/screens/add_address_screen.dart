import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../domain/entities/address_entity.dart';
import '../providers/address_providers.dart';

class AddAddressScreen extends ConsumerStatefulWidget {
  const AddAddressScreen({super.key});

  @override
  ConsumerState<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends ConsumerState<AddAddressScreen> {
  static const _defaultCenter = LatLng(33.7551, 72.2831);

  GoogleMapController? _mapController;
  LatLng _center = _defaultCenter;
  bool _resolving = false;
  bool _saving = false;
  bool _loadingLocation = true;

  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _searchController = TextEditingController();
  AddressLabel _selectedLabel = AddressLabel.home;

  Timer? _searchDebounce;
  List<geocoding.Location> _searchResults = [];
  bool _searching = false;
  bool _showSearchResults = false;

  @override
  void initState() {
    super.initState();
    _useCurrentLocation();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _addressController.dispose();
    _landmarkController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    try {
      final position = await LocationService.instance.getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);
      setState(() {
        _center = target;
        _loadingLocation = false;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      await _reverseGeocode(target);
    } catch (e) {
      setState(() => _loadingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _resolving = true);
    try {
      final placemarks =
          await geocoding.placemarkFromCoordinates(point.latitude, point.longitude);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = [p.street, p.subLocality, p.locality, p.administrativeArea]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        setState(() {
          _addressController.text = parts;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _resolving = false);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      _searchAddress(value.trim());
    });
  }

  Future<void> _searchAddress(String query) async {
    setState(() => _searching = true);
    try {
      final locations = await geocoding.locationFromAddress(query);
      if (mounted) {
        setState(() {
          _searchResults = locations;
          _showSearchResults = locations.isNotEmpty;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _showSearchResults = false;
          _searching = false;
        });
      }
    }
  }

  void _selectSearchResult(geocoding.Location location) {
    final target = LatLng(location.latitude, location.longitude);
    setState(() {
      _center = target;
      _showSearchResults = false;
      _searchController.clear();
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    _reverseGeocode(target);
  }

  Future<void> _save() async {
    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter or confirm the address'), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _saving = true);
    final result = await ref.read(addressListProvider.notifier).addAddress(
          label: _selectedLabel,
          fullAddress: _addressController.text.trim(),
          latitude: _center.latitude,
          longitude: _center.longitude,
          landmark: _landmarkController.text.trim().isEmpty ? null : _landmarkController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (_) => Navigator.of(context).pop(true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Address')),
      body: Column(
        children: [
          SizedBox(
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _center, zoom: 16),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_center != _defaultCenter) {
                      controller.animateCamera(CameraUpdate.newLatLngZoom(_center, 16));
                    }
                  },
                  onCameraMove: (position) => _center = position.target,
                  onCameraIdle: () => _reverseGeocode(_center),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
                const Icon(Icons.location_pin, size: 40, color: AppColors.primary),
                // Search bar overlay
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search for a location...',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchResults = [];
                                            _showSearchResults = false;
                                          });
                                        },
                                      )
                                    : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                      if (_showSearchResults)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          constraints: const BoxConstraints(maxHeight: 150),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final loc = _searchResults[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.location_on_outlined, size: 18, color: AppColors.primary),
                                title: Text(
                                  '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                onTap: () => _selectSearchResult(loc),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                // Current location button
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'my_location',
                    backgroundColor: Colors.white,
                    onPressed: _useCurrentLocation,
                    child: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 20),
                  ),
                ),
                if (_resolving || _loadingLocation)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 6),
                          Text(
                            _loadingLocation ? 'Getting location...' : 'Resolving...',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: _addressController,
                    label: 'Full address',
                    hint: 'Will auto-fill from pin',
                    maxLines: 2,
                    validator: (v) => Validators.required(v, field: 'Address'),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _landmarkController,
                    label: 'Landmark (optional)',
                    hint: 'Near XYZ',
                  ),
                  const SizedBox(height: 20),
                  Text('Save as', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: AddressLabel.values.map((label) {
                      final isSelected = label == _selectedLabel;
                      return ChoiceChip(
                        label: Text(label.display),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _selectedLabel = label),
                        selectedColor: AppColors.primary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(label: 'Save Address', isLoading: _saving, onPressed: _save),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
