import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// 与系统“照片”一致：
/// - 新 → 旧（降序）
/// - reverse: true（首帧在底部，上滑更旧）
/// - 行内右→左
/// - 缩略图渐进清晰
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final ScrollController _scroll = ScrollController();

  // 状态
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String? _denyReason;

  // 数据
  final List<AssetEntity> _assets = [];

  // 分页
  static const int _pageSize = 200;
  int _nextPage = 0;

  // 滚动节流（停止 120ms 后再升高清）
  bool _isScrolling = false;
  DateTime _lastScroll = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // 稳定排序：按创建时间降序；同秒按 id 降序
  void _stableSortDesc(List<AssetEntity> list) {
    list.sort((a, b) {
      final c = b.createDateTime.compareTo(a.createDateTime);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _denyReason = null;
      _nextPage = 0;
      _noMore = false;
      _assets.clear();
    });

    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      setState(() {
        _loading = false;
        _denyReason = ps.isAuth ? null : '未授权访问相册';
      });
      return;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: const FilterOptionGroup(
        orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (paths.isEmpty) {
      setState(() {
        _loading = false;
        _noMore = true;
      });
      return;
    }

    final p = paths.first;
    final first = await p.getAssetListPaged(page: _nextPage, size: _pageSize);
    _nextPage++;

    final valid = first.where((a) => a.createDateTime.year > 1970).toList();
    _stableSortDesc(valid);

    setState(() {
      _assets.addAll(valid);
      _loading = false;
      _noMore = valid.length < _pageSize;
    });
  }

  void _onScroll() {
    _isScrolling = true;
    _lastScroll = DateTime.now();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (DateTime.now().difference(_lastScroll).inMilliseconds >= 120) {
        _isScrolling = false;
        if (mounted) setState(() {}); // 触发可视区高清升级
      }
    });

    if (_loadingMore || _noMore || !_scroll.hasClients) return;

    final pos = _scroll.position;
    final bool nearTop = pos.pixels >= (pos.maxScrollExtent - 1000);
    if (nearTop) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _noMore) return;
    setState(() => _loadingMore = true);

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: const FilterOptionGroup(
        orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (paths.isEmpty) {
      setState(() {
        _loadingMore = false;
        _noMore = true;
      });
      return;
    }
    final p = paths.first;

    final chunk = await p.getAssetListPaged(page: _nextPage, size: _pageSize);
    _nextPage++;

    final valid = chunk.where((a) => a.createDateTime.year > 1970).toList();
    _stableSortDesc(valid);

    setState(() {
      _assets.addAll(valid);
      _loadingMore = false;
      if (valid.length < _pageSize) _noMore = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 顶部透明度：0 更透，1 最实（约 120px 内过渡完）
    final double barOpacity =
        _scroll.hasClients ? (_scroll.offset / 120.0).clamp(0.0, 1.0) : 0.0;

    if (_loading) {
      return Scaffold(
        appBar: _GlassAppBar(title: '时间线', height: 44, opacity: 1.0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_denyReason != null) {
      return Scaffold(
        appBar: _GlassAppBar(title: '时间线', height: 44, opacity: 1.0),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('无法访问相册：$_denyReason', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => PhotoManager.openSetting(),
                child: const Text('去设置'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _GlassAppBar(title: '时间线', height: 44, opacity: barOpacity),
      body: Directionality(
        textDirection: TextDirection.rtl, // 行内右→左
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is UserScrollNotification) {
              _isScrolling = n.direction != ScrollDirection.idle;
              if (!_isScrolling && mounted) setState(() {});
            }
            return false;
          },
          child: CustomScrollView(
            controller: _scroll,
            reverse: true,         // 自底向上
            cacheExtent: 1200,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(4),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final asset = _assets[index]; // 新→旧
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => _Viewer(asset: asset)),
                        ),
                        child: _ProgressiveThumb(
                          asset,
                          enableHigh: !_isScrolling,
                        ),
                      );
                    },
                    childCount: _assets.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                ),
              ),

              // 顶部分页指示（reverse 下的“顶部”）
              SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _loadingMore
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 缩略图“渐进清晰”：先低清（轻模糊）→ 再淡入高清
class _ProgressiveThumb extends StatefulWidget {
  const _ProgressiveThumb(this.asset, {this.enableHigh = true});
  final AssetEntity asset;
  final bool enableHigh;

  static const int lowEdge = 120;
  static const int highEdge = 300;

  @override
  State<_ProgressiveThumb> createState() => _ProgressiveThumbState();
}

class _ProgressiveThumbState extends State<_ProgressiveThumb> {
  bool _hiReady = false;

  @override
  Widget build(BuildContext context) {
    final low = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
        child: Image(
          image: AssetEntityImageProvider(
            widget.asset,
            isOriginal: false,
            thumbnailSize:
                const ThumbnailSize.square(_ProgressiveThumb.lowEdge),
          ),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
    );

    final high = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image(
        image: AssetEntityImageProvider(
          widget.asset,
          isOriginal: false,
          thumbnailSize:
              const ThumbnailSize.square(_ProgressiveThumb.highEdge),
        ),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        frameBuilder: (context, child, frame, wasSyncLoaded) {
          if (frame != null && !_hiReady) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hiReady = true);
            });
          }
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: _hiReady ? 1 : 0,
            child: child,
          );
        },
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        low,
        if (widget.enableHigh) high,
      ],
    );
  }
}

/// 毛玻璃 + 渐变透明 AppBar（随滚动变实，更接近系统“照片”）
class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassAppBar({
    required this.title,
    this.height = 44,
    this.opacity = 1.0, // 0~1
  });

  final String title;
  final double height;
  final double opacity;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final o = opacity.clamp(0.0, 1.0);

    return AppBar(
      title: Text(title),
      centerTitle: true,
      toolbarHeight: height,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1) 毛玻璃（略强）
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: const SizedBox.expand(),
            ),
            // 2) 纵向渐变：上实下透；随滚动叠加透明度
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.surface.withValues(alpha: 0.88 * o),
                    scheme.surface.withValues(alpha: 0.60 * o),
                    scheme.surface.withValues(alpha: 0.00 * o),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
            // 3) 轻微高光蒙层，增强磨砂质感
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.02 * o),
              ),
            ),
            // 4) 底部分隔线（随滚动显现）
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 0.5,
                color: scheme.onSurface.withValues(alpha: 0.10 * o),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 查看页：先中清(1024) → 再原图淡入
class _Viewer extends StatelessWidget {
  const _Viewer({required this.asset});
  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(asset.title ?? '查看')),
      body: Center(child: _ProgressiveOriginal(asset)),
    );
  }
}

class _ProgressiveOriginal extends StatefulWidget {
  const _ProgressiveOriginal(this.asset);
  final AssetEntity asset;

  @override
  State<_ProgressiveOriginal> createState() => _ProgressiveOriginalState();
}

class _ProgressiveOriginalState extends State<_ProgressiveOriginal> {
  bool _oriReady = false;

  @override
  Widget build(BuildContext context) {
    final mid = Image(
      image: AssetEntityImageProvider(
        widget.asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize(1024, 1024),
      ),
      fit: BoxFit.contain,
      alignment: Alignment.center,
    );

    final ori = Image(
      image: AssetEntityImageProvider(widget.asset, isOriginal: true),
      fit: BoxFit.contain,
      alignment: Alignment.center,
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (frame != null && !_oriReady) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _oriReady = true);
          });
        }
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _oriReady ? 1 : 0,
          child: child,
        );
      },
    );

    return Stack(fit: StackFit.expand, children: [mid, ori]);
  }
}
