import 'package:flutter/material.dart';
import '../models/facility.dart';
import '../services/facility_service.dart';

class FacilityDetailPage extends StatefulWidget {
  final String mountainId;
  final String mountainName;

  const FacilityDetailPage({
    super.key,
    required this.mountainId,
    required this.mountainName,
  });

  @override
  State<FacilityDetailPage> createState() => _FacilityDetailPageState();
}

class _FacilityDetailPageState extends State<FacilityDetailPage> {
  List<Facility> _facilities = [];
  bool _isLoading = true;

  static const Color teal = Color(0xFF00939C);

  @override
  void initState() {
    super.initState();
    _loadFacilities();
  }

  Future<void> _loadFacilities() async {
    setState(() => _isLoading = true);
    final facilities =
        await FacilityService.getFacilitiesByMountainId(widget.mountainId);
    if (!mounted) return;
    setState(() {
      _facilities = facilities;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.mountainName} — ルート沿いの施設'),
        backgroundColor: teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showAddFacilityDialog(context),
                        icon: const Icon(Icons.add_location_alt, size: 18),
                        label: const Text("施設を追加"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text("${_facilities.length}件",
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _facilities.isEmpty
                        ? const Center(
                            child: Text(
                              '施設が登録されていません\n「施設を追加」で登録してください',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _facilities.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, i) {
                              final f = _facilities[i];
                              return ListTile(
                                leading: Icon(
                                  f.type == 'トイレ'
                                      ? Icons.wc
                                      : (f.type == '山小屋'
                                          ? Icons.house
                                          : Icons.store),
                                  color: teal,
                                ),
                                title: Text(
                                  "${f.type} • ${f.name}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  [
                                    if (f.distanceKm != null)
                                      "${f.distanceKm}km",
                                    if (f.elevationM != null)
                                      "${f.elevationM}m",
                                    if (f.openSeason.isNotEmpty)
                                      "開設: ${f.openSeason}",
                                    if (f.winterClosed) "❄️冬季凍結の可能性",
                                    if (f.notes.isNotEmpty) "備考: ${f.notes}",
                                  ].join(' • '),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          color: Colors.blue),
                                      onPressed: () =>
                                          _showEditFacilityDialog(context, f),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.grey),
                                      onPressed: () =>
                                          _confirmDelete(context, f),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _showAddFacilityDialog(BuildContext ctx) async {
    final nameCtrl = TextEditingController();
    final distanceCtrl = TextEditingController();
    final elevCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final openSeasonCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String type = 'トイレ';
    bool winterClosed = false;

    await showDialog<bool>(
      context: ctx,
      builder: (c) {
        return StatefulBuilder(builder: (sbCtx, sbSetState) {
          return AlertDialog(
            title: const Text('施設を追加'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text("種別：",
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: type,
                        items: const [
                          DropdownMenuItem(value: 'トイレ', child: Text('トイレ')),
                          DropdownMenuItem(value: '山小屋', child: Text('山小屋')),
                          DropdownMenuItem(value: 'お店', child: Text('お店')),
                        ],
                        onChanged: (v) => sbSetState(() => type = v ?? 'トイレ'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '名称 (必須)')),
                  TextField(
                    controller: distanceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: '登山口からの距離 (km)'),
                  ),
                  TextField(
                    controller: elevCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '標高 (m)'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(labelText: '緯度'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lngCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(labelText: '経度'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: openSeasonCtrl,
                    decoration: const InputDecoration(
                        labelText: '開いている時期 例: 通年 / 4-11'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: winterClosed,
                        onChanged: (v) =>
                            sbSetState(() => winterClosed = v ?? false),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('冬季凍結で閉鎖される可能性がある（トイレ向け）')),
                    ],
                  ),
                  TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: '備考')),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(c).pop(false),
                  child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(const SnackBar(content: Text('名称は必須です')));
                    return;
                  }

                  final facility = Facility(
                    id: '', // Firestoreで自動生成
                    mountainId: widget.mountainId,
                    type: type,
                    name: nameCtrl.text.trim(),
                    distanceKm: double.tryParse(distanceCtrl.text.trim()),
                    elevationM: int.tryParse(elevCtrl.text.trim()),
                    lat: double.tryParse(latCtrl.text.trim()),
                    lng: double.tryParse(lngCtrl.text.trim()),
                    openSeason: openSeasonCtrl.text.trim(),
                    winterClosed: winterClosed,
                    notes: notesCtrl.text.trim(),
                  );

                  final docId = await FacilityService.createFacility(facility);
                  if (docId != null) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('施設を追加しました')));
                    _loadFacilities();
                    Navigator.of(c).pop(true);
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('施設の追加に失敗しました')));
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _showEditFacilityDialog(
      BuildContext ctx, Facility facility) async {
    final nameCtrl = TextEditingController(text: facility.name);
    final distanceCtrl =
        TextEditingController(text: facility.distanceKm?.toString() ?? '');
    final elevCtrl =
        TextEditingController(text: facility.elevationM?.toString() ?? '');
    final latCtrl = TextEditingController(text: facility.lat?.toString() ?? '');
    final lngCtrl = TextEditingController(text: facility.lng?.toString() ?? '');
    final openSeasonCtrl = TextEditingController(text: facility.openSeason);
    final notesCtrl = TextEditingController(text: facility.notes);
    String type = facility.type;
    bool winterClosed = facility.winterClosed;

    await showDialog<bool>(
      context: ctx,
      builder: (c) {
        return StatefulBuilder(builder: (sbCtx, sbSetState) {
          return AlertDialog(
            title: const Text('施設を編集'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text("種別：",
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: type,
                        items: const [
                          DropdownMenuItem(value: 'トイレ', child: Text('トイレ')),
                          DropdownMenuItem(value: '山小屋', child: Text('山小屋')),
                          DropdownMenuItem(value: 'お店', child: Text('お店')),
                        ],
                        onChanged: (v) => sbSetState(() => type = v ?? 'トイレ'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '名称 (必須)')),
                  TextField(
                    controller: distanceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: '登山口からの距離 (km)'),
                  ),
                  TextField(
                    controller: elevCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '標高 (m)'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(labelText: '緯度'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lngCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(labelText: '経度'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: openSeasonCtrl,
                    decoration: const InputDecoration(
                        labelText: '開いている時期 例: 通年 / 4-11'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: winterClosed,
                        onChanged: (v) =>
                            sbSetState(() => winterClosed = v ?? false),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('冬季凍結で閉鎖される可能性がある（トイレ向け）')),
                    ],
                  ),
                  TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: '備考')),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(c).pop(false),
                  child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(const SnackBar(content: Text('名称は必須です')));
                    return;
                  }

                  final updated = facility.copyWith(
                    type: type,
                    name: nameCtrl.text.trim(),
                    distanceKm: double.tryParse(distanceCtrl.text.trim()),
                    elevationM: int.tryParse(elevCtrl.text.trim()),
                    lat: double.tryParse(latCtrl.text.trim()),
                    lng: double.tryParse(lngCtrl.text.trim()),
                    openSeason: openSeasonCtrl.text.trim(),
                    winterClosed: winterClosed,
                    notes: notesCtrl.text.trim(),
                    updatedAt: DateTime.now(),
                  );

                  final success = await FacilityService.updateFacility(updated);
                  if (success) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('施設を更新しました')));
                    _loadFacilities();
                    Navigator.of(c).pop(true);
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('施設の更新に失敗しました')));
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, Facility facility) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${facility.name}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('キャンセル')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await FacilityService.deleteFacility(facility.id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('施設を削除しました')));
        _loadFacilities();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('施設の削除に失敗しました')));
      }
    }
  }
}
