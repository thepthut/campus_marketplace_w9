import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// ⚠️ ปรับจากใบงาน: Firebase Storage บังคับให้อัปเกรดเป็นแผน Blaze (ต้องผูกบัตร)
/// จึงเก็บรูปแบบย่อขนาด (JPEG ราว 50-150 KB) เป็น Data URL ไว้ในเอกสาร Firestore แทน
///
/// คงชื่อคลาสและเมธอด uploadListingImage(File, String) ไว้ตามใบงาน
/// หน้าจออื่นจึงไม่ต้องแก้อะไร — ถ้าวันหลังเปลี่ยนไปใช้ Firebase Storage จริง
/// แก้แค่ไฟล์นี้ไฟล์เดียว (ข้อดีของการแยก Service ออกมา)
class StorageService {
  /// Firestore จำกัดขนาดเอกสารไว้ที่ 1 MB จึงต้องให้รูปเล็กกว่านี้มาก
  static const int _maxDataUrlLength = 700000;

  /// "อัปโหลด" รูปประกาศ แล้วคืนค่าเป็น URL ที่ใช้แสดงรูปได้ (Data URL)
  /// [onProgress] รับค่า 0.0 - 1.0 สำหรับแสดง Progress Indicator
  Future<String> uploadListingImage(
    File imageFile,
    String sellerId, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.1);
    final bytes = await imageFile.readAsBytes();
    onProgress?.call(0.4);

    // ย่อรูปใน Isolate แยก เพื่อไม่ให้หน้าจอค้างระหว่างประมวลผล
    final dataUrl = await Isolate.run(() => _compressToDataUrl(bytes));
    onProgress?.call(1.0);
    return dataUrl;
  }

  static String _compressToDataUrl(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('ไม่สามารถอ่านไฟล์รูปภาพได้');
    }
    final oriented = img.bakeOrientation(decoded); // หมุนรูปตามข้อมูล EXIF ของกล้อง

    // ลองย่อทีละขั้นจนขนาดเล็กพอจะเก็บใน Firestore ได้
    const attempts = [(600, 70), (450, 60), (320, 50)];
    for (final (width, quality) in attempts) {
      final resized =
          oriented.width > width ? img.copyResize(oriented, width: width) : oriented;
      final jpg = img.encodeJpg(resized, quality: quality);
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpg)}';
      if (dataUrl.length <= _maxDataUrlLength) return dataUrl;
    }
    throw Exception('รูปภาพมีขนาดใหญ่เกินไป กรุณาเลือกรูปอื่น');
  }
}
