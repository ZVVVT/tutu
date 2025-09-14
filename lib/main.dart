import 'dart:io';
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

enum MediaFilter { all, image, video, raw, heic }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // —— 持久化 key ——
  static const _kGridColsKey = 'tutu.grid.columns';
  static const _kPersonalizedEnabledKey = 'tutu.personalized.enabled';
  static const _kFilterKey = 'tutu.filter';

  // —— UI 状态 ——
  final _scroll = ScrollController();
  bool _titleShowsPhotos = false; // true=“照片”，false=“图库”

  // 列数：仅 1 / 3 / 6
  static const _allowedCols = [1, 3, 6];
  int _cols = 6;
  bool _scaleChangedOnce = false;

  bool _personalizedEnabled = true;
  MediaFilter _filter = MediaFilter.all;

  // 数据
  String? rootPath;
  List<MediaItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
    _scroll.addListener(_onScroll);
    _restoreRootAndScan();
  }

  Future<void> _restorePrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _cols = _normalizeCols(p.getInt(_kGridColsKey) ?? 6);
      _personalizedEnabled = p.getBool(_kPersonalizedEnabledKey) ?? true;
      _filter = MediaFilter.values[(p.getInt(_kFilterKey) ?? 0)
          .clamp(0, MediaFilter.values.length - 1)];
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
      await _scan();
    }
  }

  void _onScroll() {
    // 标题切换：进入“照片区”（底部）即显示“照片”，否则“图库”
    final offset = _scroll.offset;
    setState(() => _titleShowsPhotos = offset > 20);
  }

  Future<void> _pickFolder() async {
    final path = await FolderAccess.pickRoot();
    if (!mounted) return;
    if (path != null) {
      setState(() => rootPath = path);
      await _scan();
      _jumpToPhotosStart();
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('读取失败：$e')));
    }
  }

  List<MediaItem> get _filteredItems {
    return _items.where((it) {
      final p = it.path.toLowerCase();
      switch (_filter) {
        case MediaFilter.all:
          return true;
        case MediaFilter.image:
          return !it.isVideo && !_isRaw(p) && !_isHeic(p);
        case MediaFilter.video:
          return it.isVideo;
        case MediaFilter.raw:
          return !it.isVideo && _isRaw(p);
        case MediaFilter.heic:
          return !it.isVideo && _isHeic(p);
      }
    }).toList();
  }

  bool _isHeic(String p) => p.endsWith('.heic') || p.endsWith('.heif');
  bool _isRaw(String p) =>
      p.endsWith('.raw') ||
      p.endsWith('.dng') ||
      p.endsWith('.cr2') ||
      p.endsWith('.cr3') ||
      p.endsWith('.arw') ||
      p.endsWith('.nef') ||
      p.endsWith('.raf') ||
      p.endsWith('.nrw');

  Future<void> _setCols(int v) async {
    final nv = _normalizeCols(v);
    if (nv == _cols) return;
    setState(() => _cols = nv);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kGridColsKey, nv);
  }

  Future<void> _setFilter(MediaFilter f) async {
    setState(() => _filter = f);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kFilterKey, f.index);
  }

  Future<void> _setPersonalizedEnabled(bool enabled) async {
    setState(() => _personalizedEnabled = enabled);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPersonalizedEnabledKey, enabled);
  }

  void _jumpToPhotosStart() {
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  void _jumpToPersonalizedStart() {
    // 进入个性化区：滚动到页面底部附近
    _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  // 捏合列数：一次手势只切一次档位
  void _onScaleStart(ScaleStartDetails d) {
    _scaleChangedOnce = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_scaleChangedOnce) return;
    const upThreshold = 1.12;   // 放大：列数减小
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

  @override
  void dispose() {
    FolderAccess.releaseAccess();
    _scroll.dispose();
    super.dispose();
  }

  // —— UI ——
  @override
  Widget build(BuildContext context) {
    final titleText =
        _personalizedEnabled ? (_titleShowsPhotos ? '照片' : '图库') : '图库';

    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: Scaffold(
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            // 只保留 FlexibleSpaceBar，避免重复标题
            SliverAppBar(
              pinned: true,
              expandedHeight: 112,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                expandedTitleScale: 1.6,
                titlePadding:
                    const EdgeInsetsDirectional.only(start: 16, bottom: 12),
                title: Text(titleText),
              ),
            ),

            // 统计 + 筛选
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rootPath != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        '${_items.where((e) => !e.isVideo).length} 张照片 · ${_items.where((e) => e.isVideo).length} 个视频',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                    ),
                  _FilterChips(value: _filter, onChanged: _setFilter),
                ],
              ),
            ),

            // 照片区：使用 SliverFillRemaining，把网格“压到底部”（从下往上排）
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
            else if (_filteredItems.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('没有符合筛选的媒体')),
              )
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const Expanded(child: SizedBox()), // 把网格压到底部
                    // 照片网格（外层用 GridView 但不滚动，交给外层 Sliver 滚动）
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _cols,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, i) =>
                            _GridTile(item: _filteredItems[i]),
                      ),
                    ),
                    // 窥视预览（露头）：点击/上滑进入个性化区
                    if (_personalizedEnabled)
                      InkWell(
                        onTap: _jumpToPersonalizedStart,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('更多项目',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                              const Icon(Icons.expand_more),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // 个性化区：先提供“选择目录/相册”卡片
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

  // —— bottom sheets ——

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
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('相册选择即将支持')));
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
                      if (enabled) {
                        Future.delayed(const Duration(milliseconds: 120),
                            _jumpToPersonalizedStart);
                      } else {
                        _jumpToPhotosStart();
                      }
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

class _FilterChips extends StatelessWidget {
  final MediaFilter value;
  final ValueChanged<MediaFilter> onChanged;
  const _FilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = {
      MediaFilter.all: '全部',
      MediaFilter.image: '图片',
      MediaFilter.video: '视频',
      MediaFilter.raw: 'RAW',
      MediaFilter.heic: 'HEIC',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.entries.map((e) {
          final selected = e.key == value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(e.value),
              selected: selected,
              onSelected: (_) => onChanged(e.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  final MediaItem item;
  const _GridTile({required this.item});

  @override
  Widget build(BuildContext context) {
    // 关键：下对齐裁切
    return FutureBuilder<File?>(
      future: ThumbnailCache.getThumb(item, maxSize: 480),
      builder: (context, snap) {
        if (snap.hasData && snap.data != null) {
          return Image.file(
            snap.data!,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          );
        }
        if (!item.isVideo) {
          return Image.file(
            File(item.path),
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
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
