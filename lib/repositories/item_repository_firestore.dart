import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/item.dart';
import 'item_repository.dart';

class ItemRepositoryFirestore implements ItemRepository {
  final FirebaseFirestore _firestore;

  ItemRepositoryFirestore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _items => _firestore.collection('items');

  /// อ่านทุกเอกสารใน Collection items ครั้งเดียว (เหมือน ItemRepositoryApi.getItems())
  @override
  Future<List<Item>> getItems() async {
    final snapshot = await _items.get();
    return snapshot.docs.map((doc) => Item.fromFirestore(doc)).toList();
  }

  /// เขียนประกาศใหม่ลง Collection items (Firestore สร้าง doc id ให้อัตโนมัติ)
  Future<void> postItem(Item item) async {
    // ตอนไม่มีเน็ต Firestore จะ "เก็บคิวไว้ส่งทีหลัง" แทนที่จะแจ้ง Error
    // ซึ่งจะทำให้กดโพสต์ซ้ำแล้วได้ประกาศเบิ้ล จึงเช็กกับเซิร์ฟเวอร์ก่อนว่าเชื่อมต่อได้จริง
    try {
      await _items
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    await _items.add(item.toFirestore());
  }

  /// ฟังเฉพาะประกาศของผู้ขายคนนี้แบบ Real-time (.snapshots() ไม่ใช่ .get())
  Stream<List<Item>> watchMyListings(String sellerId) {
    return _items
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Item.fromFirestore(doc)).toList());
  }
}
