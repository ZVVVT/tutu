import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// 系统相册时间线（首版最小可运行）
/// - 首次进入请求相册权限
/// - 加载最近的图片/视频缩略图（按创建时间倒序）
/// - 点开查看原图
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  bool _loading = true;
  List<AssetEntity> _assets = [];
  String? _denyReason; // 用于展示拒绝/受限情况

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loading = true;
      _denyReason = null;
    });

    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      setState(() {
        _loading = false;
        _denyReason = ps.isAuth ? null : '未授权访问相册';
      });
      return;
    }

    // 取所有相册路径（图片+视频），按创建时间倒序
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );

    final List<AssetEntity> all = [];
    // 先取每个目录前 300 项做首屏（足够丝滑）
    for (final p in paths) {
      final page = await p.getAssetListPaged(page: 0, size: 300);
      all.addAll(page);
    }

    setState(() {
      _assets = all;
      _loading = false;
    });
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

    // 未授权或无资源时的空态
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
              OutlinedButton(
                onPressed: _loadAssets,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const _AppBar(title: '时间线'),
      body: CustomScrollView(
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
                    child: AssetEntityImage(
                      asset,
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(300),
                      fit: BoxFit.cover,
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
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      centerTitle: false,
    );
  }
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
