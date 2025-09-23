// ignore_for_file: unused_element
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import 'services/folder_access.dart';
import 'services/media_scanner.dart';
import 'services/thumbnail_cache.dart';

void main() {
  runApp(const TutuApp());
}

class TutuApp extends StatelessWidget {
  const TutuApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tutu',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // —— 持久化 key —— 
  static const _kGridColsKey = 'tutu.grid.columns';
  static const _kPersonalizedEnabledKey = 'tutu.personalized.enabled';

  // —— UI 状态 —— 
  final _scroll = ScrollController();

  // 列数：仅 1 / 3 / 6
  static const _allowedCols = [1, 3, 6];
  int _cols = 6;
  bool _scaleChangedOnce = false;

  bool _personalizedEnabled = true;

  // 数据
  String? rootPath;
  List<MediaItem> _items = [];
  bool _loading = false;

  // —— 布局常量（与网格/预览计算一致）—— 
  static const double _hPad = 6; // 左右外边距
  static const double _gridTopPad = 8;
  static const double _gridMainSpacing = 6;
  static const double _gridCrossSpacing = 6;

  // —— “一次性锚底”标记 ——（每次数据源变动会重置）
  bool _anchoredOnce = false;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
    _restoreRootAndScan();
  }

  Future<void> _restorePrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _cols = _normalizeCols(p.getInt(_kGridColsKey) ?? 6);
      _personalizedEnabled = p.getBool(_kPersonalizedEnabledKey) ?? true;
    });
  }

  int _normalizeCols(int v) {
    if (_allowedCols.contains(v)) return v;
    int nearest = _allowedCols.first;
    for (final c in _allowedCols) {
      if ((v - c).abs() < (v - nearest).abs()) nearest = c;
    }
    return nearest;
  }

  Future<void> _restoreRootAndScan() async {
    final path = await FolderAccess.restoreRoot();
    if (!mounted) return;
    if (path != null && Directory(path).existsSync()) {
      setState(() => rootPath = path);
      _anchoredOnce = false; // 允许本次扫描后锚底
      await _scan();
    }
  }

  Future<void> _pickFolder() async {
    final path = await FolderAccess.pickRoot();
    if (!mounted) return;
    if (path != null) {
      setState(() => rootPath = path);
      _anchoredOnce = false; // 选择新目录后，允许锚底
      await _scan();
    }
  }

  Future<void> _scan() async {
    final root = rootPath;
    if (root == null) return;
    setState(() => _loading = true);
    try {
      final result = await scanMediaRecursively(root);
      if (!mounted) return;
      setState(() {
        _items = result;
        _loading = false;
      });
      _anchorToBottomOnce(); // 扫描结束 → 锚定到底部（仅一次）
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('读取失败：$e')));
    }
  }

  // —— 首次构建完成后锚定到底（只执行一次）——
  void _anchorToBottomOnce() {
    if (_anchoredOnce) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (target > 0) {
        _scroll.jumpTo(target); // 避免闪烁
        _anchoredOnce = true;
      } else {
        _anchoredOnce = true; // 不足一屏也算完成
      }
    });
  }

  Future<void> _setCols(int v) async {
    final nv = _normalizeCols(v);
    if (nv == _cols) return;
    setState(() => _cols = nv);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kGridColsKey, nv);
  }

  Future<void> _setPersonalizedEnabled(bool enabled) async {
    setState(() => _personalizedEnabled = enabled);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPersonalizedEnabledKey, enabled);
  }

  void _jumpToPhotosStart() {
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  // 捏合列数：一次手势只切一次档位
  void _onScaleStart(ScaleStartDetails d) {
    _scaleChangedOnce = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_scaleChangedOnce) return;
    const upThreshold = 1.12; // 放大：列数减小
    const downThreshold = 0.88; // 缩小：列数增大
    final s = d.scale;
    final idx = _allowedCols.indexOf(_cols);
    if (s >= upThreshold && idx > 0) {
      _scaleChangedOnce = true;
      _setCols(_allowedCols[idx - 1]);
      HapticFeedback.selectionClick();
    } else if (s <= downThreshold && idx < _allowedCols.length - 1) {
      _scaleChangedOnce = true;
      _setCols(_allowedCols[idx + 1]);
      HapticFeedback.selectionClick();
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _scaleChangedOnce = false;
  }

  // —— 网格尺寸计算 —— //
  double _tileSizeByCrossExtent(double crossExtent) {
    final usable = crossExtent - _hPad * 2 - (_cols - 1) * _gridCrossSpacing;
    return usable / _cols;
  }

  int _rowCount(int itemCount) => (itemCount + _cols - 1) ~/ _cols;

  double _gridHeight(double crossExtent, int itemCount) {
    final rows = _rowCount(itemCount);
    if (rows == 0) return 0;
    final tile = _tileSizeByCrossExtent(crossExtent);
    final tilesHeight = rows * tile + (rows - 1) * _gridMainSpacing;
    return _gridTopPad + tilesHeight;
  }

  @override
  void dispose() {
    FolderAccess.releaseAccess();
    _scroll.dispose();
    super.dispose();
  }

  // —— UI —— //
  @override
  Widget build(BuildContext context) {
    // 标题固定“图库”，滚动不再切换，避免闪变
    const titleText = '图库';

    final imageCount = _items.where((e) => !e.isVideo).length;
    final videoCount = _items.where((e) => e.isVideo).length;

    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: Scaffold(
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            // 顶部：自定义大标题（毛玻璃+渐变；副标题贴在大标题下，仅展开态可见）
            SliverPersistentHeader(
              pinned: true,
              delegate: PhotosHeaderDelegate(
                title: titleText,
                subtitle:
                    rootPath != null ? '$imageCount 张照片 · $videoCount 个视频' : '',
                topPadding: MediaQuery.of(context).padding.top,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
            ),

            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rootPath == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: FilledButton.icon(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择文件夹'),
                  ),
                ),
              )
            else if (_items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('暂无媒体')),
              )
            else ...[
              // 顶端占位：内容不足一屏时，把网格压到底部（不再预留“窥视露头”）
              if (_personalizedEnabled)
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final cross = constraints.crossAxisExtent;
                    final remaining = constraints.remainingPaintExtent;
                    final gridH = _gridHeight(cross, _items.length);
                    final double topPad =
                        (remaining - gridH) > 0 ? (remaining - gridH) : 0.0;
                    return SliverToBoxAdapter(child: SizedBox(height: topPad));
                  },
                ),

              // 照片网格（贴底裁切，下对齐）
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(_hPad, _gridTopPad, _hPad, 0),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _cols,
                    mainAxisSpacing: _gridMainSpacing,
                    crossAxisSpacing: _gridCrossSpacing,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, i) => _GridTile(item: _items[i]),
                ),
              ),
            ],

            // 个性化区：直接显示“选择目录/相册”卡片（没有“更多项目”）
            if (_personalizedEnabled)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                sliver: SliverList.list(children: [
                  _ChooseSourceCard(onTap: () => _showChooseSheet(context)),
                ]),
              ),

            // “自定义与重新排序”：始终显示
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child:
                    _CustomizeButton(onTap: () => _showCustomizeSheet(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —— bottom sheets —— //

  void _showChooseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('选择文件夹'),
              onTap: () async {
                Navigator.pop(context);
                await _pickFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('选择相册（即将支持）'),
              subtitle: const Text('后续接入系统相册/PhotoKit 选择器'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('相册选择即将支持')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomizeSheet(BuildContext context) {
    bool enabled = _personalizedEnabled;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('自定义与重新排序',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: enabled,
                    onChanged: (v) => setS(() => enabled = v),
                    title: const Text('显示：选择目录/相册'),
                    subtitle: const Text('关闭后首页仅显示图库（隐藏个性化区域）'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _setPersonalizedEnabled(enabled);
                      _anchoredOnce = false; // 重置一次性标记
                      _anchorToBottomOnce(); // 开场即到底（统一体验）
                    },
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// —— 小部件 —— //

class _GridTile extends StatelessWidget {
  final MediaItem item;
  const _GridTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: ThumbnailCache.getThumb(item, maxSize: 480),
      builder: (context, snap) {
        if (snap.hasData && snap.data != null) {
          return Image.file(
            snap.data!,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter, // 贴底裁切
          );
        }
        if (!item.isVideo) {
          return Image.file(
            File(item.path),
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter, // 贴底裁切
            cacheWidth: 480,
          );
        }
        return const ColoredBox(color: Colors.black12);
      },
    );
  }
}

class _ChooseSourceCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ChooseSourceCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: const [
              Icon(Icons.add_photo_alternate_outlined, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text('选择目录 / 相册', style: TextStyle(fontSize: 16)),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomizeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CustomizeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onTap,
      icon: const Icon(Icons.tune),
      label: const Text('自定义与重新排序'),
    );
  }
}

/// 顶部大标题（毛玻璃 + 渐变；副标题贴大标题下，仅展开态可见；始终左对齐不跳位；无分割线）
class PhotosHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final String subtitle; // 统计小字（展开时显示，收起淡出）
  final double topPadding; // 安全区
  final Color backgroundColor; // 适配明暗色

  PhotosHeaderDelegate({
    required this.title,
    required this.subtitle,
    required this.topPadding,
    required this.backgroundColor,
  });

  @override
  double get minExtent => topPadding + 56; // 收起高度
  @override
  double get maxExtent => topPadding + 120; // 展开高度

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final d = (maxExtent - minExtent);
    final t = (d <= 0) ? 1.0 : (shrinkOffset / d).clamp(0.0, 1.0);

    final double titleFont = ui.lerpDouble(32, 20, t)!; // 大->小
    final double titleTop = topPadding + ui.lerpDouble(18, 8, t)!; // 轻微上移
    final double subtitleOpacity = 1 - t; // 仅展开时可见

    return Stack(
      fit: StackFit.expand,
      children: [
        // 毛玻璃 + 半透明底色
        ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: backgroundColor.withValues(alpha: 0.5)),
          ),
        ),
        // 自上而下渐变透明（露出下方内容）
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    backgroundColor.withValues(alpha: 0.90),
                    backgroundColor.withValues(alpha: 0.60),
                    backgroundColor.withValues(alpha: 0.00),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
        ),
        // 左对齐标题 + 展开态副标题
        Positioned(
          left: 16,
          right: 16,
          top: titleTop,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleFont,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              if (subtitle.isNotEmpty)
                Opacity(
                  opacity: subtitleOpacity,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ✅ 已去掉“更多项目”窥视与分割线
      ],
    );
  }

  @override
  bool shouldRebuild(covariant PhotosHeaderDelegate old) {
    return title != old.title ||
        subtitle != old.subtitle ||
        backgroundColor != old.backgroundColor ||
        topPadding != old.topPadding;
  }
}
