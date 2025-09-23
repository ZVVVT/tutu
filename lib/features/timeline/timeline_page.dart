import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// 与系统“照片”一致：
/// - 新 -> 旧（降序）
/// - 视图 reverse: true，首帧出现在底部
/// - 向“上”滚动时分页加载更旧的资源
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final ScrollController _scroll = ScrollController();

  bool _loading = true;           // 首次加载
  bool _loadingMore = false;      // 顶部追加分页
  bool _noMore = false;           // 已无更多数据
  String? _denyReason;

  final List<AssetEntity> _assets = [];

  // 分页参数
  static const int _pageSize = 200;
  int _nextPage = 0; // getAssetListPaged(page: _nextPage)

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

    // 只取“所有照片/Recent”，并按创建时间【降序】（新 -> 旧）
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
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

    // 首次只取一页，保证首帧快；reverse 渲染，首帧直接在底部，无需跳转
    final first = await p.getAssetListPaged(page: _nextPage, size: _pageSize);
    _nextPage++;
    setState(() {
      _assets.addAll(first);
      _loading = false;
      _noMore = first.length < _pageSize;
    });
  }

  // 监听向上滚动接近“顶部”时加载更多（reverse: true -> 视觉顶部 = 滚动距离接近 maxScrollExtent）
  void _onScroll() {
    if (_loadingMore || _noMore || !_scroll.hasClients) return;

    final pos = _scroll.position;
    // 距离“视觉顶部”小于 1000 像素时触发下一页
    final bool nearTop = pos.pixels >= (pos.maxScrollExtent - 1000);
    if (nearTop) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _noMore) return;
    setState(() => _loadingMore = true);

    // 仍按创建时间【降序】分页（与首屏一致）
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
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

    // 在 reverse 视图下，追加到列表尾部 = 视觉上的“上方”，不会影响底部稳定性
    setState(() {
      _assets.addAll(chunk);
      _loadingMore = false;
      if (chunk.length < _pageSize) _noMore = true;
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
      body: CustomScrollView(
        controller: _scroll,
        reverse: true,                 // ✅ 关键：首帧在底部，滚动方向与系统一致
        cacheExtent: 1200,            // 预取，减小滚动加载感
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(4),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final asset = _assets[index]; // 新->旧
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => _Viewer(asset: asset)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: AssetEntityImage(
                        asset,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize.square(300),
                        fit: BoxFit.cover,
                        alignment: Alignment.center, // 居中裁切，贴近照片App
                      ),
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

          // 顶部加载条（reverse=true 时显示在“视觉顶部”）
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _loadingMore
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => AppBar(title: Text(title));
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _Viewer extends StatelessWidget {
  const _Viewer({required this.asset});
  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(asset.title ?? '查看')),
      body: Center(
        child: AssetEntityImage(
          asset,
          isOriginal: true, // 查看页按需拉原片
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
