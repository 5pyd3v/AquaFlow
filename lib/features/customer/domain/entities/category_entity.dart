import 'package:equatable/equatable.dart';

class CategoryEntity extends Equatable {
  final String id;
  final String name;
  final String? iconName;
  final int sortOrder;

  const CategoryEntity({
    required this.id,
    required this.name,
    this.iconName,
    required this.sortOrder,
  });

  @override
  List<Object?> get props => [id, name, iconName, sortOrder];
}
