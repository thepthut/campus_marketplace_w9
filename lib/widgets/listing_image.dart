import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// แสดงรูปสินค้าได้ทั้ง 2 แบบ
/// - URL ปกติ (สินค้าจาก Fake Store API) → Image.network
/// - Data URL "data:image/jpeg;base64,..." (ประกาศที่โพสต์ผ่าน Firestore) → Image.memory
class ListingImage extends StatelessWidget {
  final String imageUrl;
  final double size;
  final IconData fallbackIcon;

  const ListingImage({
    super.key,
    required this.imageUrl,
    this.size = 48,
    this.fallbackIcon = Icons.broken_image,
  });

  // แคชผลถอดรหัส base64 ไว้ ไม่ต้องถอดใหม่ทุกครั้งที่เลื่อนรายการ
  static final Map<String, Uint8List> _decodedCache = {};

  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext context, Object error, StackTrace? stackTrace) =>
        Icon(fallbackIcon);

    if (imageUrl.startsWith('data:image')) {
      try {
        final bytes = _decodedCache.putIfAbsent(
          imageUrl,
          () => base64Decode(imageUrl.substring(imageUrl.indexOf(',') + 1)),
        );
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: fallback,
        );
      } catch (_) {
        return Icon(fallbackIcon);
      }
    }

    return Image.network(
      imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: fallback,
    );
  }
}
