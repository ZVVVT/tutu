import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection; // 正确来源
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// 与系统“照片”一致：
/// - 新 → 旧（降序）
/// - 视图 reverse: true，首帧位于底部
/// - 向“上”滚动时分页加载更旧
/// - 缩略图/原图采用“渐进清晰”（先糊后清）
/// - 排序按“元数据创建时间”；二级稳定排序用 Dart 端的 asset.id
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final ScrollController _scroll = ScrollController();

  // 加载状态
  bool _loading = true;       // 首屏加载
  bool _loadingMore = false;  // 顶部分页加载
  bool _noMore = false;       // 没有更多旧内容
  String? _denyReason;

  // 数据
  final List<AssetEntity> _assets = [];

  // 分页参数（可按需要调小/调大）
  static const int _pageSize = 200;
  int _nextPage = 0;

  // 滚动节流：滚动中只渲染低清，停止 120ms 后再升级高清
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

  // Dart 端稳定排序：先按创建时间降序；同时间戳按 id 降序
  void _stableSortDesc(List<AssetEntity> list) {
    list.sort((a, b) {
      final c = b.createDateTime.compareTo(a.createDateTime); // 新→旧
      if (c != 0) return c;
      return b.id.compareTo(a.id); // 二级保障稳定
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

    // 仅取系统“所有照片/Recent”，按元数据创建时间【降序】（新→旧）
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: const [
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
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

    // 过滤异常日期 + 稳定排序
    final valid = first.where((a) => a.createDateTime.year > 1970).toList();
    _stableSortDesc(valid);

    setState(() {
      _assets.addAll(valid);            // 新→旧
      _loading = false;
      _noMore = valid.length < _pageSize;
    });
  }

  void _onScroll() {
    // 轻量节流：记录滚动中状态，降低高清替换频率
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
    // reverse=true：视觉“顶部”是 pos.maxScrollExtent。逼近时加载更多旧数据
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
        orders: const [
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
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

    // 追加到尾部（reverse=true 下“视觉上方”），不会影响底部稳定性
    setState(() {
      _assets.addAll(valid);
      _loadingMore = false;
      if (valid.length < _pageSize) _noMore = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: _AppBar(title: '时间线'),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_denyReason != null) {
      return Scaffold(
        appBar: const _AppBar(title: '时间线'),
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
      appBar: const _AppBar(title: '时间线'),
      // 👇 关键：用 RTL 包住整个 CustomScrollView，使每一行按 右→左 排列
      body: Directionality(
        textDirection: TextDirection.rtl,
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
            reverse: true,              // 首帧在底部，向上看更旧
            cacheExtent: 1200,          // 预取，降低加载感
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(4),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final asset = _assets[index]; // 仍是新→旧数据
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => _Viewer(asset: asset)),
                        ),
                        child: _ProgressiveThumb(
                          asset,
                          enableHigh: !_isScrolling, // 滚动中只显示低清；停止后再升级高清
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

              // 顶部分页指示（reverse=true 下可视顶部）
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

/// 缩略图“渐进清晰”组件：先低清（轻模糊）→ 再淡入高清
class _ProgressiveThumb extends StatefulWidget {
  const _ProgressiveThumb(this.asset, {this.enableHigh = true});
  final AssetEntity asset;
  final bool enableHigh;

  // 统一常量
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
            thumbnailSize: const ThumbnailSize.square(_ProgressiveThumb.lowEdge),
          ),
          fit: BoxFit.cover,
          alignment: Alignment.center, // 居中裁切
        ),
      ),
    );

    // 高清层：用 frameBuilder 侦测首帧解码完成后淡入
    final high = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image(
        image: AssetEntityImageProvider(
          widget.asset,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(_ProgressiveThumb.highEdge),
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

/// 顶部 AppBar
class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({required this.title, this.height = 44});
  final String title;
  @override
  Widget build(BuildContext context) => AppBar(title: Text(title));
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
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
