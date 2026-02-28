import 'package:equatable/equatable.dart';

class FavoriteItem extends Equatable {
  final String id;
  final String userId;
  final String productId;
  final String productName;
  final String brand;
  final double price;
  final String imageUrl;
  final String? purchaseUrl;
  final String category;
  final DateTime createdAt;

  const FavoriteItem({
    required this.id,
    required this.userId,
    required this.productId,
    required this.productName,
    required this.brand,
    required this.price,
    required this.imageUrl,
    this.purchaseUrl,
    required this.category,
    required this.createdAt,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      brand: json['brand'] as String,
      price: (json['price'] as num).toDouble(),
      imageUrl: json['image_url'] as String,
      purchaseUrl: (() {
        final dynamic rawUrl =
            json['purchase_url'] ?? json['purchaseUrl'] ?? json['url'];
        if (rawUrl == null) return null;
        final trimmed = rawUrl.toString().trim();
        return trimmed.isEmpty ? null : trimmed;
      })(),
      category: json['category'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'product_id': productId,
      'product_name': productName,
      'brand': brand,
      'price': price,
      'image_url': imageUrl,
      'purchase_url': purchaseUrl,
      'category': category,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        productId,
        productName,
        brand,
        price,
        imageUrl,
        purchaseUrl,
        category,
        createdAt,
      ];
}
