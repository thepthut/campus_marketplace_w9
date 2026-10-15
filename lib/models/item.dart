import 'package:cloud_firestore/cloud_firestore.dart';

class Item {
  final int id;
  final String title;
  final double price;
  final String description;
  final String category;
  final String imageUrl;

  /// uid ของผู้ขาย — null สำหรับสินค้าจาก Fake Store API (ไม่มีผู้ขายจริง)
  final String? sellerId;

  /// id เอกสารใน Firestore (เป็น String) — null สำหรับสินค้าจาก API
  final String? docId;

  const Item({
    required this.id,
    required this.title,
    required this.price,
    required this.description,
    required this.category,
    required this.imageUrl,
    this.sellerId,
    this.docId,
  });

  /// true = สินค้าที่นักศึกษาโพสต์จริงผ่าน Firestore
  bool get isFromFirestore => docId != null;

  factory Item.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final title = json['title'] as String;
    final price = (json['price'] as num).toDouble();
    final description = json['description'] as String;
    final category = json['category'] as String;
    final imageUrl = json['image'] as String; // key 'image' ไม่ตรงกับชื่อ field imageUrl

    return Item(
      id: id,
      title: title,
      price: price,
      description: description,
      category: category,
      imageUrl: imageUrl,
    );
  }

  /// แปลงเป็น Map สำหรับเขียนลง Firestore (key ตรงกับชื่อ field)
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'price': price,
      'description': description,
      'category': category,
      'imageUrl': imageUrl,
      'sellerId': sellerId,
    };
  }

  /// สร้าง Item จากเอกสาร Firestore พร้อมใส่ doc.id เป็น id ของ Item
  factory Item.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Item(
      // doc.id ของ Firestore เป็น String แต่ field id เดิมเป็น int (ตะกร้า/Favorites ใช้อยู่)
      // จึงแปลง doc.id เป็นตัวเลขที่คงที่เสมอ และเก็บ doc.id ตัวจริงไว้ใน docId
      id: _stableIntId(doc.id),
      docId: doc.id,
      title: data['title'] as String? ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      description: data['description'] as String? ?? '',
      category: data['category'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      sellerId: data['sellerId'] as String?,
    );
  }

  /// แปลง String เป็น int แบบได้ค่าเดิมทุกครั้ง (FNV-1a) และไม่ชนกับ id 1-20 ของ Fake Store API
  static int _stableIntId(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 1000000 + hash;
  }
}
