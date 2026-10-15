import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/item.dart';
import '../repositories/item_repository_firestore.dart';
import '../repositories/listing_draft_repository.dart';
import '../services/storage_service.dart';

class MyDraftsPage extends StatefulWidget {
  final ListingDraftRepository repository;
  const MyDraftsPage({super.key, required this.repository});

  @override
  State<MyDraftsPage> createState() => _MyDraftsPageState();
}

class _MyDraftsPageState extends State<MyDraftsPage> {
  late Future<List<ListingDraftRow>> _draftsFuture;

  // ร่างที่กำลังโพสต์อยู่ (null = ไม่มี) และความคืบหน้าการอัปโหลด 0.0 - 1.0
  int? _postingDraftId;
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _draftsFuture = widget.repository.getAllDrafts();
  }

  void _reload() {
    setState(() {
      _draftsFuture = widget.repository.getAllDrafts();
    });
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _delete(ListingDraftRow draft) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.deleteDraft(draft.id);
      _reload();
      messenger.showSnackBar(SnackBar(content: Text('ลบร่าง "${draft.title}" แล้ว')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('ลบไม่สำเร็จ: $e')));
    }
  }

  /// Dialog ถามราคา (ร่างไม่มีราคาเก็บไว้) — คืนค่า null ถ้ากดยกเลิก
  Future<double?> _askPrice(ListingDraftRow draft) {
    final controller = TextEditingController();
    String? errorText;
    return showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final price = double.tryParse(controller.text.trim());
            if (price == null || price <= 0) {
              setDialogState(() => errorText = 'กรุณากรอกราคาเป็นตัวเลขที่มากกว่า 0');
              return;
            }
            Navigator.pop(context, price);
          }

          return AlertDialog(
            title: const Text('ตั้งราคาขาย'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(draft.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'ราคา (บาท)',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
              FilledButton(onPressed: submit, child: const Text('โพสต์ขาย')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _postForReal(ListingDraftRow draft) async {
    final messenger = ScaffoldMessenger.of(context);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      messenger.showSnackBar(const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนโพสต์ขาย')));
      return;
    }

    final imageFile = File(draft.imagePath);
    if (!imageFile.existsSync()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ไม่พบไฟล์รูปของร่างนี้ในเครื่องแล้ว กรุณาสร้างร่างใหม่')),
      );
      return;
    }

    // 1) ถามราคาก่อนเสมอ
    final price = await _askPrice(draft);
    if (price == null || !mounted) return;

    setState(() {
      _postingDraftId = draft.id;
      _uploadProgress = 0;
    });

    try {
      // 2) อัปโหลดรูปขึ้น Storage ก่อน แล้วรอรับ Download URL
      final imageUrl = await StorageService().uploadListingImage(
        imageFile,
        user.uid,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );

      // 3) ได้ URL แล้วค่อยสร้าง Item และเขียนลง Firestore
      final item = Item(
        id: 0, // Firestore สร้าง doc id ให้เอง ค่านี้ไม่ได้ถูกบันทึก
        title: draft.title,
        price: price,
        description: draft.description,
        category: draft.category,
        imageUrl: imageUrl,
        sellerId: user.uid,
      );
      await ItemRepositoryFirestore().postItem(item);

      // 4) โพสต์สำเร็จ → ลบร่างออกจาก Local Database แล้วรีเฟรชรายการ (กันโพสต์ซ้ำ)
      await widget.repository.deleteDraft(draft.id);
      if (!mounted) return;
      _reload();
      messenger.showSnackBar(
        SnackBar(content: Text('โพสต์ขาย "${draft.title}" เรียบร้อยแล้ว')),
      );
    } on FirebaseException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_translateFirebaseError(e))));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('โพสต์ไม่สำเร็จ: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _postingDraftId = null;
        });
      }
    }
  }

  String _translateFirebaseError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
      case 'unauthorized':
        return 'ไม่มีสิทธิ์โพสต์ประกาศนี้ (ตรวจสอบ Security Rules)';
      case 'unavailable':
      case 'retry-limit-exceeded':
      case 'network-request-failed':
      case 'unknown':
        return 'เชื่อมต่อเซิร์ฟเวอร์ไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
      case 'canceled':
        return 'การอัปโหลดถูกยกเลิก';
      default:
        return 'โพสต์ไม่สำเร็จ (${e.code}) กรุณาลองใหม่';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ร่างประกาศของฉัน')),
      body: FutureBuilder<List<ListingDraftRow>>(
        future: _draftsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
          }
          final drafts = snapshot.data ?? [];
          if (drafts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ยังไม่มีร่างประกาศ ลองถ่ายรูปสินค้าแล้วให้ AI ช่วยร่างดูสิ',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: drafts.length,
            itemBuilder: (context, index) {
              final draft = drafts[index];
              final imageFile = File(draft.imagePath);
              final isPosting = _postingDraftId == draft.id;
              final anyPosting = _postingDraftId != null; // ระหว่างโพสต์ ห้ามกดร่างอื่นซ้อน
              return ListTile(
                leading: imageFile.existsSync()
                    ? Image.file(imageFile, width: 48, height: 48, fit: BoxFit.cover)
                    : const Icon(Icons.image_not_supported),
                title: Text(draft.title),
                subtitle: isPosting
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('กำลังอัปโหลด ${(_uploadProgress * 100).toStringAsFixed(0)}%'),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null),
                        ],
                      )
                    : Text(
                        '${draft.category}\nแก้ไขล่าสุด: ${_formatDate(draft.updatedAt)}',
                      ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: isPosting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      tooltip: 'โพสต์ขายจริง',
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: anyPosting ? null : () => _postForReal(draft),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: anyPosting ? null : () => _delete(draft),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
