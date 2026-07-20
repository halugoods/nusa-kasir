import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/data/repositories/product_repository.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';
import 'package:nusa_kasir/shared/widgets/skeleton_list.dart';

/// Kategori grid screen — navigated to from ProductsScreen "Kategori" segment.
/// Route: /produk/kategori
class KategoriListScreen extends ConsumerStatefulWidget {
  const KategoriListScreen({super.key});
  @override
  ConsumerState<KategoriListScreen> createState() => _KategoriListScreenState();
}

class _KategoriListScreenState extends ConsumerState<KategoriListScreen> {
  Map<String, int> _counts = {};
  bool _loading = true;
  bool _sortByCount = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ProductRepository(ref.read(databaseProvider));
    final counts = await repo.categoryProductCounts();
    if (mounted) setState(() { _counts = counts; _loading = false; });
  }

  List<MapEntry<String, int>> _sortedCats() {
    final entries = _counts.entries.toList();
    if (_sortByCount) {
      entries.sort((a, b) => b.value.compareTo(a.value));
    } else {
      entries.sort((a, b) => a.key.compareTo(b.key));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScreenScaffold(
      'Kategori Produk',
      _loading
          ? const SkeletonList()
          : Column(children: [
              // Sort toggle
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(children: [
                  Icon(Icons.sort, size: 18, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _sortByCount = !_sortByCount),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? NusaConfig.darkSurface : NusaConfig.surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? NusaConfig.darkBorder : NusaConfig.dividerColor),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_sortByCount ? 'Terbanyak' : 'A-Z',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                        const SizedBox(width: 4),
                        Icon(Icons.swap_vert, size: 16, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  Text('${_counts.length} kategori', style: TextStyle(fontSize: 12, color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary)),
                ]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.1),
                    itemCount: _sortedCats().length,
                    itemBuilder: (_, i) {
                      final entry = _sortedCats()[i];
                      final cat = entry.key;
                      final count = entry.value;
                      final gradient = NusaConfig.catGradientFor(cat);
                      final emoji = NusaConfig.catEmojiFor(cat);

                      return GestureDetector(
                        onTap: () => context.push('/produk/kategori/$cat'),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(NusaConfig.radiusXL),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradient,
                            ),
                            boxShadow: [BoxShadow(
                              color: gradient.last.withValues(alpha: 0.5),
                              blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                right: -10, top: -10,
                                child: Opacity(opacity: 0.2,
                                  child: Text(emoji, style: const TextStyle(fontSize: 72))),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(NusaConfig.spaceLG),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(emoji, style: const TextStyle(fontSize: 32)),
                                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(cat, style: TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                                        letterSpacing: -0.3)),
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(NusaConfig.radiusFull)),
                                        child: Text('$count produk',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? NusaConfig.darkTextSecondary : NusaConfig.textSecondary)),
                                      ),
                                    ]),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ]),
    );
  }
}
