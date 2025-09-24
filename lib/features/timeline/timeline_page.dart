import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

// 如需把状态栏图标改为白色，解开下一行并在 _GlassAppBar 里启用 systemOverlayStyle
// import 'package:flutter/services.dart';

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

  // 顶部“可点留白”高度（状态栏 + AppBar + 额外缓冲）
  double _topInteractiveGap(BuildContext context) {
    final topSafe = MediaQuery.of(context).padding.top;
    const double kToolbar = 55; // 与 _GlassAppBar 默认高度保持一致
    const double kExtra = 0;    // 手指缓冲，避免误触
    return topSafe + kToolbar + kExtra;
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
      filterOption: FilterOptionGroup(
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
    // 仅用于“渐进清晰”，与 AppBar 无关（AppBar 不随滚动改变）
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
      filterOption: FilterOptionGroup(
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
    if (_loading) {
      return Scaffold(
        appBar: const _GlassAppBar(
          title: '时间线',
          height: 55,
          blurSigma: 18,
          tintAlphaTop: 0.60,
          featherHeight: 24,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_denyReason != null) {
      return Scaffold(
        appBar: const _GlassAppBar(
          title: '时间线',
          height: 55,
          blurSigma: 18,
          tintAlphaTop: 0.60,
          featherHeight: 24,
        ),
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
      extendBodyBehindAppBar: true, // 内容延伸到 AppBar 背后
      appBar: const _GlassAppBar(
        title: '时间线',
        height: 55,
        blurSigma: 18,
        tintAlphaTop: 0.60,
        featherHeight: 24,
      ),
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
            reverse: true, // 自底向上
            cacheExtent: 1200,
            slivers: [
              // 1) 照片网格（reverse=true：视觉上“靠下”）
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

              // 2) 顶部分页指示（reverse 下的“顶部”）
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

              // 3) 视觉最顶上的“可点留白”（reverse=true 要放在最后）
              SliverToBoxAdapter(
                child: SizedBox(height: _topInteractiveGap(context)),
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

// 毛玻璃（大面积）+ 底缘羽化 + 深色着色 + 侧向羽化，且无滚动暗影
class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassAppBar({
    required this.title,
    this.height = 55,
    this.blurSigma = 18,       // 毛玻璃强度（8–24）
    this.tintAlphaTop = 0.55,  // 顶部黑色强度（0.45–0.65）
    this.featherHeight = 32,   // 底缘羽化高度（24–40）
    this.sideFeather = 12,     // 左右边缘羽化宽度（8–16）
  });

  final String title;
  final double height;

  // 可调参数
  final double blurSigma;
  final double tintAlphaTop;
  final double featherHeight;
  final double sideFeather;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final mediaTop = MediaQuery.paddingOf(context).top; // 状态栏高度
    final totalHeight = mediaTop + height;

    return AppBar(
      // 文字/图标保持白色
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle:
          Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
      title: Text(title),
      centerTitle: true,
      toolbarHeight: height,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0, // ✅ 关闭滚动暗影，避免“黑边”

      // 如需白色状态栏图标，解开下一行并在文件顶部 import services.dart
      // systemOverlayStyle: SystemUiOverlayStyle.light,

      flexibleSpace: SizedBox(
        height: totalHeight,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1) 毛玻璃（整块）
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: const SizedBox.expand(),
              ),

              // 2) 底缘羽化：把毛玻璃在底部挖成渐隐，确保“完全透明、无模糊”
              Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: const [Colors.black, Colors.transparent],
                        stops: const [0.0, 1.0],
                      ).createShader(
                        Rect.fromLTWH(
                          0, rect.height - featherHeight, rect.width, featherHeight,
                        ),
                      );
                    },
                    blendMode: BlendMode.dstOut,
                    child: Container(height: featherHeight, color: Colors.black),
                  ),
                ),
              ),

              // 3) 深色着色（上深下透），并做左右侧向羽化，避免两侧显得更黑
              ShaderMask(
                shaderCallback: (rect) {
                  final edge = (sideFeather / rect.width).clamp(0.0, 0.25);
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: const [
                      Colors.transparent, Colors.white, Colors.white, Colors.transparent
                    ],
                    stops: [0.0, edge, 1 - edge, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn, // 仅保留中间，左右渐隐
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      // 让透明更早结束，避免底缘叠加太重
                      stops: const [0.0, 0.85],
                      colors: [
                        Colors.black.withValues(alpha: tintAlphaTop),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
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
