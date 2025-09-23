import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// 时间线：与系统“照片”一致 —— 最新在底部，从底部开始往上浏览
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  String? _denyReason;
  List<AssetEntity> _assets = [];

  bool _anchoredOnce = false; // 首次布局后只锚底一次

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loading = true;
      _denyReason = null;
      _anchoredOnce = false;
    });

    // 申请权限
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      setState(() {
        _loading = false;
        _denyReason = ps.isAuth ? null : '未授权访问相册';
      });
      return;
    }

    // 只取“所有照片(Recent)”这一个路径，按创建时间【升序】（旧→新）
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true, // 关键：系统所有照片聚合
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: true)],
      ),
    );

    if (paths.isEmpty) {
      setState(() {
        _assets = const [];
        _loading = false;
      });
      return;
    }

    // 先取前 N 页做首屏（升序，最新在最后），后续可做分页
    final List<AssetEntity> all = [];
    final p = paths.first;
    // 取前 3 页、每页 200（可按需调整）
    for (int page = 0; page < 3; page++) {
      final chunk = await p.getAssetListPaged(page: page, size: 200);
      if (chunk.isEmpty) break;
      all.addAll(chunk);
    }

    setState(() {
      _assets = all;
      _loading = false;
    });

    _anchorToBottomOnce();
  }

  void _anchorToBottomOnce() {
    if (_anchoredOnce) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      _anchoredOnce = true;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        appBar: _AppBar(title: '时间线'),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_denyReason != null || _assets.isEmpty) {
      return Scaffold(
        appBar: const _AppBar(title: '时间线'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_denyReason != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    '无法访问相册：$_denyReason\n请在“设置 > 隐私 > 照片”中允许访问。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else
                Text('没有可显示的照片或视频', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => PhotoManager.openSetting(),
                child: const Text('去设置'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _loadAssets, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const _AppBar(title: '时间线'),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(4),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final asset = _assets[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => _Viewer(asset: asset)),
                      );
                    },
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(4), // 可选：小圆角，更贴近系统
                        child: AssetEntityImage(
                            asset,
                            isOriginal: false,
                            thumbnailSize: const ThumbnailSize.square(300),
                            fit: BoxFit.cover,               // 保持覆盖裁切
                            alignment: Alignment.center,     // 关键：居中显示
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
