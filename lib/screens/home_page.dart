import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/item.dart';
import '../models/cart_model.dart';
import '../repositories/item_repository.dart';
import '../repositories/favorites_repository.dart';
import 'checkout_page.dart';
import '../services/gemini_service.dart';
import '../services/auth_service.dart';
import '../widgets/listing_image.dart';

class HomePage extends StatefulWidget {
  final List<ItemRepository> repositories;
  final FavoritesRepository favoritesRepository;
  const HomePage({
    super.key,
    required this.repositories,
    required this.favoritesRepository,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Item>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadAllItems();
  }

  /// เรียก getItems() จากทุก Repository พร้อมกันด้วย Future.wait แล้วรวมเป็น List เดียว
  /// HomePage ไม่รู้ว่าแต่ละตัวคือ API หรือ Firestore — รู้จักแค่ Interface ItemRepository
  Future<List<Item>> _loadAllItems() async {
    final errors = <Object>[];
    final results = await Future.wait(
      widget.repositories.map(
        (repo) => repo.getItems().catchError((Object e) {
          errors.add(e); // แหล่งหนึ่งพัง แหล่งอื่นยังแสดงได้
          return <Item>[];
        }),
      ),
    );
    // ทุกแหล่งล้มเหลว (เช่น ไม่มีอินเทอร์เน็ต) → ส่ง Error ให้ FutureBuilder แสดง
    if (errors.length == widget.repositories.length && errors.isNotEmpty) {
      throw errors.first;
    }
    // ประกาศจริงของนักศึกษา (Firestore) ขึ้นก่อน ตามด้วยสินค้าจาก API
    final all = results.expand((list) => list).toList();
    return [
      ...all.where((item) => item.isFromFirestore),
      ...all.where((item) => !item.isFromFirestore),
    ];
  }

  Future<void> _refresh() async {
    final future = _loadAllItems();
    setState(() {
      _itemsFuture = future;
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder จะแสดง Error ให้เอง
    }
  }

  Future<void> _confirmSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ออกจากระบบ'),
        content: const Text('ต้องการออกจากระบบใช่หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ออกจากระบบ')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await AuthService().signOut();
      // ไม่ต้อง Navigator — AuthGate จะสลับกลับไปหน้า Login เอง
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _sourceBadge(Item item) {
    final fromStudent = item.isFromFirestore;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fromStudent ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fromStudent ? Colors.green.shade300 : Colors.blue.shade200),
      ),
      child: Text(
        fromStudent ? '🎓 นักศึกษา' : '🏪 ร้านค้า',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Marketplace'),
        actions: [
          // ปุ่มทดสอบ Gemini Text API (ขั้นตอนที่ 2.3)
          IconButton(
            icon: const Icon(Icons.smart_toy),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final reply = await GeminiService().generateText(
                  'ช่วยแต่งประโยคทักทายลูกค้าร้านค้าออนไลน์แบบเป็นกันเอง',
                );
                print('Gemini Response: $reply');
                messenger.showSnackBar(SnackBar(content: Text(reply)));
              } catch (e) {
                print('Gemini Error: $e');
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            },
          ),
          IconButton(
            icon: Badge(
              label: Text('${context.watch<CartModel>().itemCount}'),
              child: const Icon(Icons.shopping_cart),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckoutPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ออกจากระบบ',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: FutureBuilder<List<Item>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  const SizedBox(height: 200),
                  Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}')),
                ],
              ),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('ไม่พบสินค้า'));
          }
          return RefreshIndicator(
            onRefresh: _refresh, // ดึงลงเพื่อโหลดประกาศใหม่จาก Firestore
            child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: ListingImage(imageUrl: item.imageUrl),
                title: Text(item.title),
                subtitle: Row(
                  children: [
                    Flexible(child: Text('${item.price} บาท', overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    _sourceBadge(item),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ปุ่มที่ 1: กดถูกใจ (บันทึกลง Drift)
                    IconButton(
                      icon: const Icon(Icons.favorite_border),
                      color: Colors.pink,
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await widget.favoritesRepository.addFavorite(
                            item.id,
                            item.title,
                            item.price,
                            item.imageUrl,
                          );
                          messenger.showSnackBar(
                            SnackBar(content: Text('เพิ่ม "${item.title}" ลงรายการโปรดแล้ว')),
                          );
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('บันทึกรายการโปรดไม่สำเร็จ: $e')),
                          );
                        }
                      },
                    ),
                    // ปุ่มที่ 2: ตะกร้าเดิม
                    IconButton(
                      icon: const Icon(Icons.add_shopping_cart),
                      onPressed: () {
                        context.read<CartModel>().add(item);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('เพิ่ม "${item.title}" ลงตะกร้าแล้ว')),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
            ),
          );
        },
      ),
    );
  }
}