import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // static: GoogleSignIn.initialize() เรียกได้ครั้งเดียวต่อแอป
  // แต่หน้าจอต่าง ๆ สร้าง AuthService() ใหม่ทุกครั้ง จึงต้องแชร์สถานะนี้ร่วมกัน
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static bool _googleReady = false;

  User? get currentUser => _auth.currentUser;

  Future<void> signUp({required String email, required String password}) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw Exception(_translateErrorCode(e.code));
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw Exception(_translateErrorCode(e.code));
    }
  }

  Future<void> signOut() async {
    try {
      // ออกจาก Google ด้วย เพื่อให้ครั้งหน้ากดปุ่ม Google แล้วได้เลือกบัญชีใหม่
      if (_googleReady) {
        try {
          await _googleSignIn.signOut();
        } catch (_) {
          // ผู้ใช้ที่ล็อกอินด้วย Email อาจไม่มีบัญชี Google ค้างอยู่ — ไม่ต้องทำอะไร
        }
      }
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw Exception(_translateErrorCode(e.code));
    }
  }

  Future<void> _ensureGoogleReady() async {
    if (_googleReady) return;
    // initialize() ต้องเรียกครั้งเดียวก่อนใช้งานเมธอดอื่นของ GoogleSignIn เสมอ
    await _googleSignIn.initialize();
    _googleReady = true;
  }

  Future<void> signInWithGoogle() async {
    try {
      await _ensureGoogleReady();

      // authenticate() เปิดหน้าต่างให้ผู้ใช้เลือกบัญชี Google (แทนที่ signIn() ในเวอร์ชันเก่า)
      final googleUser = await _googleSignIn.authenticate();

      // idToken ได้แบบ synchronous จาก authentication ของบัญชีที่ล็อกอินแล้ว
      final idToken = googleUser.authentication.idToken;

      // accessToken ต้องขอเพิ่มผ่าน authorizationClient แยกต่างหาก
      final authorization =
          await googleUser.authorizationClient.authorizationForScopes(['email']);

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: authorization?.accessToken,
      );

      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw Exception(_translateErrorCode(e.code));
    }
  }

  /// แปล error code ของ Firebase เป็นข้อความภาษาไทย (ห้ามให้ Error ดิบหลุดไปถึงผู้ใช้)
  String _translateErrorCode(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'อีเมลนี้ถูกใช้สมัครสมาชิกไปแล้ว กรุณาเข้าสู่ระบบแทน';
      case 'weak-password':
        return 'รหัสผ่านสั้นเกินไป ต้องมีอย่างน้อย 6 ตัวอักษร';
      case 'invalid-email':
        return 'รูปแบบอีเมลไม่ถูกต้อง';
      case 'invalid-credential':
        return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง หรือข้อมูลยืนยันตัวตนจาก Google หมดอายุ กรุณาลองใหม่';
      case 'user-not-found':
      case 'wrong-password':
        return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
      case 'user-disabled':
        return 'บัญชีนี้ถูกระงับการใช้งาน';
      case 'too-many-requests':
        return 'ลองเข้าสู่ระบบหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่';
      case 'network-request-failed':
        return 'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อ';
      case 'operation-not-allowed':
        return 'ยังไม่ได้เปิดใช้งานวิธีเข้าสู่ระบบนี้ใน Firebase Console';
      case 'account-exists-with-different-credential':
        return 'อีเมลนี้เคยสมัครด้วยวิธีอื่นไว้แล้ว กรุณาเข้าสู่ระบบด้วยวิธีเดิม';
      default:
        return 'เกิดข้อผิดพลาดในการยืนยันตัวตน ($code)';
    }
  }
}
