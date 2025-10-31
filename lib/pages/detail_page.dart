import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/file_picker_nonweb.dart'
    if (dart.library.html) '../utils/file_picker_web.dart' as web_file_picker;
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import '../widgets/simple_sun_icon.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../services/open_meteo_service.dart';
import '../services/places_service.dart';
import '../services/mountain_info_ai_service.dart';
import '../services/api_service.dart';
import '../services/weather_score.dart';
// import 'plan_history_page.dart'; // 履歴ページ（未使用）
import 'facility_detail_page.dart'; // ✅ 施設詳細ページ

// ヘルパークラス：目的地情報
class _Dest {
  final String title;
  final double? lat;
  final double? lng;
  _Dest({required this.title, required this.lat, required this.lng});
}

class DetailPage extends StatefulWidget {
  final Map<String, dynamic> mountain;
  final String departureLabel;
  final DateTime? plannedDate;
  final double? departureLat;
  final double? departureLng;
  final String? selectedLevel;
  final String? selectedAccessTime;
  final String? selectedCourseTime;
  final List<String>? selectedStyles;
  final List<String>? selectedPurposes;
  final Map<String, String>? priorityPrefs;

  const DetailPage({
    super.key,
    required this.mountain,
    required this.departureLabel,
    this.plannedDate,
    this.departureLat,
    this.departureLng,
    this.selectedLevel,
    this.selectedAccessTime,
    this.selectedCourseTime,
    this.selectedStyles,
    this.selectedPurposes,
    this.priorityPrefs,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final TextEditingController _chatCtrl = TextEditingController();
  bool _isFavorite = false;
  int? _selectedTrailheadIndex;
  // State fields
  String _placesSortMode = 'rating'; // or 'distance'
  int _descReload = 0; // AI説明の再取得用
  final List<Map<String, String>> _localChat = []; // Firestore不可時のローカルログ
  bool _isSendingLocalAi = false; // 送信中スピナー表示
  List<Map<String, String>> _userSpots = []; // ユーザー追加の周辺スポット

  // 位置情報関連
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  String? _locationError;

  Future<void> _loadUserSpots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'user_spots:${(widget.mountain['name'] ?? '').toString()}';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is List) {
          final list = decoded
              .whereType<Map>()
              .map((m) =>
                  m.map((k, v) => MapEntry(k.toString(), (v ?? '').toString())))
              .toList();
          if (mounted) {
            setState(() => _userSpots = list.cast<Map<String, String>>());
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveUserSpots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'user_spots:${(widget.mountain['name'] ?? '').toString()}';
      await prefs.setString(key, json.encode(_userSpots));
    } catch (_) {}
  }

  /// 位置情報の権限を確認・取得
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 位置情報サービスが有効か確認
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      setState(() {
        _locationError = '位置情報サービスが無効です。デバイスの設定で有効にしてください。';
      });
      return false;
    }

    // 権限を確認
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return false;
        setState(() {
          _locationError = '位置情報の権限が拒否されました。';
        });
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      setState(() {
        _locationError = '位置情報の権限が永続的に拒否されています。設定から許可してください。';
      });
      return false;
    }

    return true;
  }

  /// 現在地を取得
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });

      // 位置情報取得成功のメッセージ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('現在地を取得しました'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = '位置情報の取得に失敗しました: ${e.toString()}';
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _showAddSpotDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final photoCtrl = TextEditingController();
    final memoCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('店舗名を追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '店舗名（必須）'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                // Photo URL / web file pick
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: photoCtrl,
                        decoration:
                            const InputDecoration(labelText: '写真URL（任意）'),
                        keyboardType: TextInputType.url,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (kIsWeb)
                      ElevatedButton(
                        onPressed: () async {
                          final dataUrl =
                              await web_file_picker.pickImageFileAsDataUrl();
                          if (dataUrl != null) {
                            photoCtrl.text = dataUrl;
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF267365),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('ファイル選択'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'URL（任意）'),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: memoCtrl,
                  decoration: const InputDecoration(labelText: 'メモ（任意）'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final url = urlCtrl.text.trim();
                final photo = photoCtrl.text.trim();
                final memo = memoCtrl.text.trim();
                if (name.isEmpty) return; // 必須
                // If a photo was provided, try uploading to Firebase Storage first.
                String? finalPhoto = photo.isNotEmpty ? photo : null;
                if (photo.isNotEmpty) {
                  // Attempt upload; if successful, replace with download URL.
                  final uploaded = await StorageService.uploadImageFromDataUrl(
                      photo,
                      filenamePrefix:
                          (widget.mountain['name'] ?? 'spot').toString());
                  if (uploaded != null) {
                    finalPhoto = uploaded;
                  } else {
                    // keep original (could be external URL or data URL) if upload failed
                    finalPhoto = photo;
                  }
                }

                setState(() {
                  final entry = {'name': name, 'url': url, 'memo': memo};
                  if (finalPhoto != null && finalPhoto.isNotEmpty) {
                    entry['photo'] = finalPhoto;
                  }
                  _userSpots.add(entry);
                });
                await _saveUserSpots();

                // Try to persist to Firestore as well (best-effort).
                try {
                  final mountainId =
                      (widget.mountain['id'] ?? widget.mountain['name'] ?? '')
                          .toString();
                  if (mountainId.isNotEmpty) {
                    await FirestoreService.saveUserSpot(
                        mountainId: mountainId,
                        spot: {
                          'name': name,
                          'url': url,
                          'memo': memo,
                          if (finalPhoto != null && finalPhoto.isNotEmpty)
                            'photo': finalPhoto,
                        });
                  }
                } catch (e) {
                  debugPrint('Firestore save user spot failed: $e');
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
              },
              child: const Text('追加する'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserSpots();
  }

  @override
  Widget build(BuildContext context) {
    final mountain = widget.mountain;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFB),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF1E4F45), // deep green
              Color(0xFF2B6F63), // pine
              Color(0xFFF7D154), // warm yellow
            ],
            stops: [0.0, 0.55, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _appTitle(),
                const SizedBox(height: 10),
                _header(context, mountain),
                const SizedBox(height: 10),
                _mountainInfoCard(mountain),
                if (widget.plannedDate != null) ...[
                  const SizedBox(height: 10),
                  _scheduleBanner(widget.plannedDate!),
                ],
                const SizedBox(height: 16),
                _weatherIndexCard(mountain),
                const SizedBox(height: 12),
                _weatherCard(mountain),
                const SizedBox(height: 16),
                _mapCard(mountain), // ✅ 地図カード
                const SizedBox(height: 16),
                _trailheadInfoCard(mountain),
                const SizedBox(height: 16),
                _descriptionCard(mountain),
                const SizedBox(height: 16),
                _relaxLinksCard(mountain),
                const SizedBox(height: 16),
                _gourmetLinksCard(mountain),
                const SizedBox(height: 16),
                _nearbyPlacesCard(mountain),
                const SizedBox(height: 20),
                _aiRecommendationCard(), // ✅ AIおすすめカード
                const SizedBox(height: 20),
                _chatSection(),
                const SizedBox(height: 24),
                _shareButtons(),
                const SizedBox(height: 20),
                _saveAndHistoryButtons(context),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _fixedBackButton(context),
    );
  }

  // 固定フッター：検索結果に戻る
  Widget _fixedBackButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF7CB342), Color(0xFF104E41)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF104E41).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: InkWell(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  '検索結果に戻る',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 💚 ヘッダー
  Widget _header(BuildContext context, Map<String, dynamic> mountain) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ふりがな（小さく表示）
                if ((mountain['name_kana'] ?? '').toString().isNotEmpty)
                  Text(
                    (mountain['name_kana'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                // 山名
                Text(
                  "${mountain["name"]}（${mountain["pref"]}）",
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                // 名称下にタグバッジ（日本百名山 / 日本二百名山）
                Builder(builder: (context) {
                  final List tags = (mountain['tags'] is List)
                      ? (mountain['tags'] as List)
                      : const [];
                  final bool is100 = tags.contains('日本百名山');
                  final bool is200 = tags.contains('日本二百名山');
                  if (!is100 && !is200) return const SizedBox.shrink();
                  List<Widget> chips = [];
                  if (is100) {
                    chips.add(Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8BC34A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('日本百名山',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ));
                  }
                  if (is200) {
                    chips.add(Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64B5F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('日本二百名山',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ));
                  }
                  return Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: chips);
                }),
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            _isFavorite ? Icons.favorite : Icons.favorite_border,
            color: Colors.pinkAccent,
          ),
          onPressed: () => setState(() => _isFavorite = !_isFavorite),
        ),
      ],
    );
  }

  // � アプリタイトル（検索と統一）

  // 🏔️ 山の基本情報カード（タイトル下）
  Widget _mountainInfoCard(Map<String, dynamic> mountain) {
    // 山の説明を拡充
    String description = (mountain['description'] ?? '').toString().trim();
    if (description.isEmpty) {
      // デフォルト説明を充実化
      final name = mountain["name"] ?? '';
      final pref = mountain["pref"] ?? '';
      final elevation = mountain["elevation"] ?? mountain["height"] ?? '';
      final elevText =
          elevation.toString().isNotEmpty ? '標高${elevation}m、' : '';
      description =
          '$nameは$prefに位置する山です。$elevText四季折々の自然を楽しめる人気の登山スポットです。山頂からの眺望や登山道の景観、周辺の温泉施設など、登山後の楽しみも豊富にあります。';
    }
    // 300文字に拡大
    if (description.length > 300) {
      description = '${description.substring(0, 300)}...';
    }

    // アクセス時間の取得（Firestoreの新旧フィールド/計算済みフィールドを網羅）
    final accessTime =
        (mountain['accessTime'] ?? mountain['time'] ?? '').toString();
    final rawCar =
        (mountain['accessCar'] ?? mountain['time_car'] ?? '').toString();
    final rawPublic =
        (mountain['accessPublic'] ?? mountain['time_public'] ?? '').toString();
    final int? compCar = (mountain['computed_time_car'] is num)
        ? (mountain['computed_time_car'] as num).toInt()
        : null;
    final int? compPT = (mountain['computed_time_public'] is num)
        ? (mountain['computed_time_public'] as num).toInt()
        : null;
    // 表示用（計算済みを最優先）
    final String accessCar = (compCar != null)
        ? '$compCar分（実ルート）'
        : (rawCar.isNotEmpty ? '$rawCar分' : '');
    final String accessPublic = (compPT != null)
        ? '$compPT分（実ルート）'
        : (rawPublic.isNotEmpty ? '$rawPublic分' : '');

    // デバッグ: コンソールに出力
    print('🚗 Mountain: ${mountain["name"]}');
    print('  accessTime: "$accessTime"');
    print('  accessCar: "$accessCar"');
    print('  accessPublic: "$accessPublic"');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF00939C).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Colors.black87,
            ),
          ),
          if (accessCar.isNotEmpty || accessPublic.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🚗 出発地点から登山口までのアクセス時間',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00939C),
                  ),
                ),
                // 現在地取得ボタン
                if (!_isLoadingLocation)
                  InkWell(
                    onTap: _getCurrentLocation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00939C).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF00939C), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _currentPosition != null
                                ? Icons.location_on
                                : Icons.my_location,
                            size: 14,
                            color: const Color(0xFF00939C),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _currentPosition != null ? '現在地更新' : '現在地取得',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF00939C),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF00939C)),
                    ),
                  ),
              ],
            ),
            if (_locationError != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _locationError!,
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_currentPosition != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '現在地: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            // 車のアクセス時間（データがあれば表示、なければ「未登録」）
            Row(
              children: [
                const Icon(Icons.directions_car,
                    size: 16, color: Color(0xFF267365)),
                const SizedBox(width: 6),
                Text(
                  accessCar.isNotEmpty ? '車：$accessCar' : '車：データ未登録',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        accessCar.isNotEmpty ? Colors.black87 : Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 公共交通機関のアクセス時間（データがあれば表示、なければ「未登録」）
            Row(
              children: [
                const Icon(Icons.train, size: 16, color: Color(0xFF267365)),
                const SizedBox(width: 6),
                Text(
                  accessPublic.isNotEmpty
                      ? '公共交通機関：$accessPublic'
                      : '公共交通機関：データ未登録',
                  style: TextStyle(
                    fontSize: 13,
                    color: accessPublic.isNotEmpty
                        ? Colors.black87
                        : Colors.black45,
                  ),
                ),
              ],
            ),
          ] else if (accessTime.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time,
                    size: 16, color: Color(0xFF00939C)),
                const SizedBox(width: 6),
                Text(
                  'アクセス時間：$accessTime',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ] else ...[
            // デバッグ: データがない場合の表示
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'この山のアクセス時間データは未登録です（データベース要確認）',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _appTitle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SimpleSunIcon(size: 20),
        SizedBox(width: 8),
        Text(
          '晴れ山 SEARCH',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  // 🗓 日程（詳細ページ上部）
  Widget _scheduleBanner(DateTime day) {
    final d = DateTime(day.year, day.month, day.day)
        .toIso8601String()
        .split('T')
        .first
        .replaceAll('-', '/');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF00939C).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, color: Color(0xFF00939C)),
          const SizedBox(width: 8),
          Text('登山日：$d', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // �🌤 天気カード（API連携：登山日の24時間・横スクロール）
  Widget _weatherCard(Map<String, dynamic> m) {
    // 実ルート用の登山口座標があれば優先（result_pageと一貫性を保つ）
    double? lat = (m['lat'] is num) ? (m['lat'] as num).toDouble() : null;
    double? lng = (m['lng'] is num) ? (m['lng'] as num).toDouble() : null;
    if (m['computed_dest_lat'] is num && m['computed_dest_lng'] is num) {
      lat = (m['computed_dest_lat'] as num).toDouble();
      lng = (m['computed_dest_lng'] as num).toDouble();
      debugPrint(
          '🌤️ [DetailPage] Using trailhead coordinates for weather: ($lat, $lng)');
    }
    final DateTime target = widget.plannedDate ?? DateTime.now();

    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "⛰ 山の天気（1時間ごと）",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (lat == null || lng == null)
            const Text(
              '位置情報が不足しているため、この山の時間別天気を表示できません。',
              style: TextStyle(color: Colors.black54),
            )
          else
            FutureBuilder<List<Map<String, dynamic>>>(
              future: OpenMeteoService.fetchHourly(lat, lng, day: target),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 4),
                  );
                }
                if (snap.hasError) {
                  return const Text('天気データの取得に失敗しました。時間をおいて再度お試しください。',
                      style: TextStyle(color: Colors.black87));
                }
                final data = snap.data ?? const [];
                if (data.isEmpty) {
                  return const Text('この日の時間別天気データはありません。',
                      style: TextStyle(color: Colors.black87));
                }
                return SizedBox(
                  height: 170,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: data.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final e = data[i];
                      final timeStr = e['time']?.toString() ?? '';
                      final hh = (timeStr.length >= 13)
                          ? timeStr.substring(11, 13)
                          : '';
                      final hourLabel =
                          hh.isNotEmpty ? '${int.tryParse(hh) ?? 0}時' : '';
                      final wcode = (e['weathercode'] as int?) ?? 0;
                      final emoji =
                          OpenMeteoService.emojiFromWeatherCode(wcode);
                      final temp = (e['temp_c'] as num?)?.toDouble();
                      final wind = (e['wind_m_s'] as num?)?.toDouble();
                      final pop = ((e['pop'] as num?)?.toDouble() ?? 0.0) * 100;

                      return Container(
                        width: 100,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFF8E1), Color(0xFFFFFFFF)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFF00939C)
                                  .withValues(alpha: 0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(hourLabel,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 4),
                            _weatherVisual(wcode, emoji),
                            const SizedBox(height: 6),
                            if (temp != null)
                              Text('${temp.round()}°C',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E4F45))),
                            const SizedBox(height: 6),
                            // 風速
                            if (wind != null) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.air,
                                      size: 14, color: Color(0xFF00939C)),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      '風 ${wind.toStringAsFixed(1)}m/s',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF424242)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                            ],
                            // 降水確率
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.water_drop,
                                    size: 14, color: Color(0xFF10ABB4)),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    '雨 ${pop.round()}%',
                                    style: const TextStyle(
                                        fontSize: 10, color: Color(0xFF424242)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _weatherVisual(int weatherCode, String emoji) {
    // Clear sky (0) or mostly clear (1) → simple orange sun icon
    if (weatherCode == 0 || weatherCode == 1) {
      return const SimpleSunIcon(size: 26);
    }
    // Partly cloudy
    if (weatherCode == 2) {
      return const Icon(Icons.wb_cloudy, color: Color(0xFF90A4AE), size: 30);
    }
    // Cloud / rain fallback: keep emoji for variety
    return Text(emoji, style: const TextStyle(fontSize: 32));
  }

  // 🏔 山情報
  Widget _descriptionCard(Map<String, dynamic> m) {
    final hasDbDesc = ((m['description'] ?? '').toString().trim().isNotEmpty);
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("🏔 山の情報",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 10),
          if (hasDbDesc)
            Text(
              (m['description'] as String).trim(),
              style: const TextStyle(height: 1.6, color: Colors.black87),
            )
          else
            FutureBuilder<String?>(
              key: ValueKey('ai-desc-${m['name']}-$_descReload'),
              future: MountainInfoAIService.getOrGenerateDescription(m),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: LinearProgressIndicator(minHeight: 4),
                  );
                }
                final text = (snap.data ?? '').toString().trim();
                if (text.isEmpty) {
                  return Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '説明なし（AI生成を取得できませんでした）',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _descReload++),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('再試行'),
                      ),
                    ],
                  );
                }
                return Text(
                  text,
                  style: const TextStyle(height: 1.6, color: Colors.black87),
                );
              },
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Builder(builder: (context) {
              final name = (m['name'] ?? '').toString();
              final pref = (m['pref'] ?? '').toString();
              final String itinerary =
                  (m['itinerary_yamap'] ?? '').toString().trim();
              final String yamapUrlField =
                  (m['yamap_url'] ?? '').toString().trim();
              final dynamic yamapIdDyn = m['yamapMountainId'] ??
                  m['yamap_mountain_id'] ??
                  m['yamap_id'];
              final String yamapId = (yamapIdDyn ?? '').toString().trim();

              String targetUrl;
              String label;
              if (itinerary.isNotEmpty && itinerary.startsWith('http')) {
                targetUrl = itinerary;
                label = '🧭 YAMAPでコースをみる';
              } else if (yamapUrlField.isNotEmpty &&
                  yamapUrlField.startsWith('http')) {
                targetUrl = yamapUrlField;
                label = '🧭 YAMAPで山ページを開く';
              } else if (int.tryParse(yamapId) != null) {
                targetUrl = 'https://yamap.com/mountains/$yamapId';
                label = '🧭 YAMAPで山ページを開く';
              } else {
                final q = [
                  'YAMAP',
                  if (name.isNotEmpty) name,
                  if (pref.isNotEmpty) pref
                ].join(' ');
                targetUrl =
                    'https://www.google.com/search?q=${Uri.encodeComponent(q)}';
                label = '🧭 YAMAPで山を探す';
              }

              return OutlinedButton(
                onPressed: () => launchUrl(Uri.parse(targetUrl),
                    mode: LaunchMode.externalApplication),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE57373), width: 1.5),
                  foregroundColor: const Color(0xFFE57373),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(40)),
                ),
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // 📈 天気指数 & 今日のアドバイス（1日単位）
  Widget _weatherIndexCard(Map<String, dynamic> m) {
    // 実ルート用の登山口座標があれば優先（result_pageと一貫性を保つ）
    double? lat = (m['lat'] is num) ? (m['lat'] as num).toDouble() : null;
    double? lng = (m['lng'] is num) ? (m['lng'] as num).toDouble() : null;
    if (m['computed_dest_lat'] is num && m['computed_dest_lng'] is num) {
      lat = (m['computed_dest_lat'] as num).toDouble();
      lng = (m['computed_dest_lng'] as num).toDouble();
      debugPrint(
          '🌤️ [DetailPage] Using trailhead coordinates for weather index: ($lat, $lng)');
    }
    final DateTime target = widget.plannedDate ?? DateTime.now();

    if (lat == null || lng == null) {
      return _cardContainer(
        child: const Text('位置情報が不足しているため、この日の天気指数を表示できません。',
            style: TextStyle(color: Colors.black54)),
      );
    }

    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📈 天気指数とアドバイス',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            '※あくまでも天気予報のため、当日の天気は直前にしっかり調べてから入山しましょう',
            style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: OpenMeteoService.fetchDaily(lat, lng, days: 14),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(minHeight: 4);
              }
              if (snap.hasError) {
                debugPrint('❌ [DetailPage] Weather fetch error: ${snap.error}');
              }
              final days = snap.data ?? const [];
              debugPrint(
                  '🌤️ [DetailPage] Received ${days.length} days for weather index at ($lat, $lng)');
              if (days.isEmpty) {
                return const Text('天気指数を計算できませんでした。時間をおいて再度お試しください。',
                    style: TextStyle(color: Colors.black87));
              }
              final picked =
                  OpenMeteoService.chooseBestOrDate(days, target: target) ??
                      days.first;
              debugPrint(
                  '🌤️ [DetailPage] Picked weather: POP=${((picked['pop'] as num?) ?? 0) * 100}%, temp=${picked['temp_c']}°C');
              final f = {
                'pop': (picked['pop'] as num?)?.toDouble() ?? double.nan,
                'wind_m_s':
                    (picked['wind_m_s'] as num?)?.toDouble() ?? double.nan,
                'cloud_pct':
                    (picked['cloud_pct'] as num?)?.toDouble() ?? double.nan,
                'temp_c': (picked['temp_c'] as num?)?.toDouble() ?? double.nan,
                'precip_mm': 0.0,
              };
              final res = WeatherScore.scoreDay(f);
              final score = (res['score'] as int?) ?? 0;
              final reason = (res['reason'] as String?) ?? '';
              final breakdown = (res['breakdown'] as Map?) ?? const {};
              final advice = _buildDailyAdvice(score, breakdown, picked);

              Color badgeColor;
              if (score >= 75) {
                badgeColor = const Color(0xFF2E7D32);
              } else if (score >= 50) {
                badgeColor = const Color(0xFFF9A825);
              } else {
                badgeColor = const Color(0xFFD32F2F);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('$score',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Text('天気指数（0-100）',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(reason, style: const TextStyle(color: Colors.black87)),
                  const SizedBox(height: 6),
                  Text(advice,
                      style:
                          const TextStyle(color: Colors.black87, height: 1.5)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _buildDailyAdvice(int score, Map breakdown, Map picked) {
    if (score >= 85) {
      return '今日は絶好の山日和！展望や稜線歩きをたっぷり楽しめそうです。日焼け・水分補給の準備をお忘れなく。';
    } else if (score >= 70) {
      return '良い条件です。午前を中心に計画すると、より気持ちよく歩けます。午後は余裕をもって安全に。';
    } else if (score >= 55) {
      return '少し揺らぎはありますが、樹林帯中心や低山コースなら快適に楽しめます。早めの行動でゆとりを。';
    } else {
      return '今日は静かな山時間を。近場のハイキングや別日の快晴狙いも素敵です。安全第一で無理なく。';
    }
  }

  // 🚏 登山口情報カード
  Widget _trailheadInfoCard(Map<String, dynamic> m) {
    String orDash(String s) => (s.isNotEmpty) ? s : '—';
    final List ths =
        (m['trailheads'] is List) ? (m['trailheads'] as List) : const [];
    final mountainId = (m['id'] ?? m['name'] ?? '').toString();
    final mountainName = (m['name'] ?? '').toString();

    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🚏 登山口情報',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FacilityDetailPage(
                        mountainId: mountainId,
                        mountainName: mountainName,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_location_alt, size: 18),
                label: const Text('施設を管理'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00939C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (ths.isEmpty) ...[
            _trailRow(Icons.flag, '登山口名', orDash('${m['name'] ?? ''} 登山口')),
            const SizedBox(height: 6),
            _trailRow(
                Icons.place, '住所', orDash((m['address'] ?? '').toString())),
            const SizedBox(height: 6),
            _trailRow(Icons.local_parking, '駐車場',
                orDash((m['parking'] ?? '').toString())),
            const SizedBox(height: 6),
            _trailRow(Icons.wc, 'トイレ', orDash((m['toilet'] ?? '').toString())),
          ] else ...[
            ...ths.asMap().entries.map((entry) {
              final i = entry.key;
              final th = Map<String, dynamic>.from(entry.value as Map);
              final tname =
                  (th['name'] ?? '${m['name'] ?? ''} 登山口${i + 1}').toString();
              final taddr = (th['address'] ?? '').toString();
              final tparkNote = (th['parking'] ?? '').toString();
              final tcap = th['capacity']?.toString() ??
                  th['capacityCar']?.toString() ??
                  '';
              final tpark = tcap.isNotEmpty
                  ? (tparkNote.isNotEmpty ? '約$tcap台（$tparkNote）' : '約$tcap台')
                  : (tparkNote.isNotEmpty ? tparkNote : '');
              final hasToilet = (th['hasToilet'] == true);
              final ttltSeason = (th['toiletSeason'] ?? '').toString();
              final ttltLegacy = (th['toilet'] ?? '').toString();
              final ttlt = hasToilet
                  ? (ttltSeason.isNotEmpty ? 'あり（$ttltSeason）' : 'あり')
                  : (ttltSeason.isNotEmpty ? ttltSeason : ttltLegacy);
              return Padding(
                padding: EdgeInsets.only(bottom: i == ths.length - 1 ? 0 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _trailRow(Icons.flag, '登山口名', orDash(tname)),
                    const SizedBox(height: 6),
                    _trailRow(Icons.place, '住所', orDash(taddr)),
                    const SizedBox(height: 6),
                    _trailRow(Icons.local_parking, '駐車場', orDash(tpark)),
                    const SizedBox(height: 6),
                    _trailRow(Icons.wc, 'トイレ', orDash(ttlt)),
                  ],
                ),
              );
            })
          ]
        ],
      ),
    );
  }

  Widget _trailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF267365)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(value),
            ],
          ),
        )
      ],
    );
  }

  // 🧭 周辺スポット（Google Places が設定されているときのみ表示）
  Widget _nearbyPlacesCard(Map<String, dynamic> m) {
    if (!PlacesService.isConfigured) {
      return const SizedBox.shrink();
    }
    final List ths =
        (m['trailheads'] is List) ? (m['trailheads'] as List) : const [];
    double? lat = (m['lat'] is num) ? (m['lat'] as num).toDouble() : null;
    double? lng = (m['lng'] is num) ? (m['lng'] as num).toDouble() : null;
    if (ths.isNotEmpty) {
      final int idx = _selectedTrailheadIndex ?? 0;
      final Map th = Map.from(ths[idx]);
      final tlat = th['lat'];
      final tlng = th['lng'];
      if (tlat is num && tlng is num) {
        lat = tlat.toDouble();
        lng = tlng.toDouble();
      }
    }
    if (lat == null || lng == null) {
      return const SizedBox.shrink();
    }
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔎 店舗名（Google）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('評価順'),
                selected: _placesSortMode == 'rating',
                onSelected: (v) => setState(() => _placesSortMode = 'rating'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('距離順'),
                selected: _placesSortMode == 'distance',
                onSelected: (v) => setState(() => _placesSortMode = 'distance'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: PlacesService.nearbyOnsenAndFoodWeighted(lat, lng,
                radiusMeters: 15000, sort: _placesSortMode),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(minHeight: 4);
              }
              if (!snap.hasData || snap.data == null) {
                return _emptySpotsBlock(showAdd: true);
              }
              final show = snap.data!;
              if (show.isEmpty) {
                return _emptySpotsBlock(showAdd: true);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...show.map((e) {
                    final rating = (e['rating'] as num?)?.toDouble();
                    final distKm = (e['distanceKm'] as num?)?.toDouble();
                    final subtitle = [
                      if (rating != null && rating > 0)
                        '⭐ ${rating.toStringAsFixed(1)}',
                      if (distKm != null) '${distKm.toStringAsFixed(1)}km',
                      if ((e['desc'] ?? '').toString().isNotEmpty)
                        (e['desc'] as String),
                    ].join(' ・ ');
                    return GestureDetector(
                      onTap: () => launchUrl(Uri.parse(e['url']),
                          mode: LaunchMode.externalApplication),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                              color: const Color(0xFF267365)
                                  .withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          title: Text(e['name'],
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(subtitle),
                          trailing:
                              const Icon(Icons.map, color: Color(0xFF267365)),
                        ),
                      ),
                    );
                  }),
                  if (_userSpots.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('📝 ユーザー追加スポット',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ..._userSpots.map((e) {
                      final subtitle = [
                        if ((e['memo'] ?? '').toString().isNotEmpty)
                          (e['memo'] ?? ''),
                        if ((e['url'] ?? '').toString().isNotEmpty) 'リンクあり',
                      ].where((s) => s.isNotEmpty).join(' ・ ');
                      return GestureDetector(
                        onTap: () {
                          final u = (e['url'] ?? '').trim();
                          if (u.isNotEmpty) {
                            launchUrl(Uri.parse(u),
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FBFA),
                            border: Border.all(
                                color: const Color(0xFF267365)
                                    .withValues(alpha: 0.2)),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            leading: (e['photo'] != null &&
                                    (e['photo'] as String).isNotEmpty)
                                ? CircleAvatar(
                                    backgroundImage:
                                        NetworkImage((e['photo'] as String)),
                                    radius: 22,
                                  )
                                : null,
                            title: Text(e['name'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(subtitle.isEmpty ? '—' : subtitle),
                            trailing: const Icon(Icons.open_in_new,
                                color: Color(0xFF267365)),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              );
            },
          ),
          if (_userSpots.isEmpty) ...[
            const SizedBox(height: 8),
            _emptySpotsHintNote(),
          ]
        ],
      ),
    );
  }

  Widget _emptySpotsBlock({bool showAdd = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F7F7),
            border: Border.all(
                color: const Color(0xFF267365).withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            '店舗名の情報がありません。見つけた店舗情報を追加して、次に訪れる方に役立てましょう。',
            style: TextStyle(color: Colors.black87),
          ),
        ),
        const SizedBox(height: 8),
        if (showAdd)
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _showAddSpotDialog,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('店舗を追加', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF267365),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        if (_userSpots.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('📝 ユーザー追加店舗',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ..._userSpots.map((e) {
            final subtitle = [
              if ((e['memo'] ?? '').toString().isNotEmpty) (e['memo'] ?? ''),
              if ((e['url'] ?? '').toString().isNotEmpty) 'リンクあり',
            ].where((s) => s.isNotEmpty).join(' ・ ');
            return GestureDetector(
              onTap: () {
                final u = (e['url'] ?? '').trim();
                if (u.isNotEmpty) {
                  launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FBFA),
                  border: Border.all(
                      color: const Color(0xFF267365).withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: (e['photo'] != null &&
                          (e['photo'] as String).isNotEmpty)
                      ? CircleAvatar(
                          backgroundImage: NetworkImage((e['photo'] as String)),
                          radius: 22,
                        )
                      : null,
                  title: Text(e['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(subtitle.isEmpty ? '—' : subtitle),
                  trailing:
                      const Icon(Icons.open_in_new, color: Color(0xFF267365)),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _emptySpotsHintNote() {
    return const Text(
      '手元の情報（温泉・食事・観光スポットなど）があれば「スポットを追加」から追記できます。',
      style: TextStyle(color: Colors.black54, fontSize: 13.5),
    );
  }

  // 🗺 地図カード（✅追加）
  Widget _mapCard(Map<String, dynamic> mountain) {
    final double? lat =
        (mountain['lat'] is num) ? (mountain['lat'] as num).toDouble() : null;
    final double? lng =
        (mountain['lng'] is num) ? (mountain['lng'] as num).toDouble() : null;
    // trailheads
    final List ths = (mountain['trailheads'] is List)
        ? (mountain['trailheads'] as List)
        : const [];
    double? dLat = lat, dLng = lng;
    if (ths.isNotEmpty) {
      final int idx = _selectedTrailheadIndex ?? 0;
      final Map th = Map.from(ths[idx]);
      final tlat = th['lat'];
      final tlng = th['lng'];
      if (tlat is num && tlng is num) {
        dLat = tlat.toDouble();
        dLng = tlng.toDouble();
      }
    }
    final LatLng pos = (dLat != null && dLng != null)
        ? LatLng(dLat, dLng)
        : const LatLng(35.625, 139.243);
    final String mname = (mountain['name'] ?? '山').toString();
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("🗺 登山口アクセスマップ",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          if (ths.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _selectedTrailheadIndex,
              items: ths.asMap().entries.map((e) {
                final i = e.key;
                final Map th = Map.from(e.value);
                final title = (th['name'] ?? '登山口${i + 1}').toString();
                return DropdownMenuItem<int>(value: i, child: Text(title));
              }).toList(),
              onChanged: (v) => setState(() => _selectedTrailheadIndex = v),
              decoration: const InputDecoration(
                labelText: '目的地の登山口を選択',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: GoogleMap(
              key: ValueKey('map-${_selectedTrailheadIndex ?? -1}'),
              onMapCreated: (controller) {},
              initialCameraPosition: CameraPosition(target: pos, zoom: 11),
              markers: {
                Marker(
                    markerId: const MarkerId("mountain"),
                    position: pos,
                    infoWindow: InfoWindow(title: mname)),
              },
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () async {
              // 現在地を優先的に使用
              final String origin;
              if (_currentPosition != null) {
                origin =
                    '${_currentPosition!.latitude.toStringAsFixed(6)},${_currentPosition!.longitude.toStringAsFixed(6)}';
              } else {
                final oLat = widget.departureLat;
                final oLng = widget.departureLng;
                origin = (oLat != null &&
                        oLng != null &&
                        (oLat != 0 || oLng != 0))
                    ? '${oLat.toStringAsFixed(6)},${oLng.toStringAsFixed(6)}'
                    : (widget.departureLabel.isNotEmpty
                        ? widget.departureLabel
                        : '出発地');
              }
              final hasPos = (pos.latitude != 0 && pos.longitude != 0);
              final destination = hasPos
                  ? '${pos.latitude},${pos.longitude}'
                  : '${widget.mountain["name"]} 登山口';
              final uri = Uri.https('www.google.com', '/maps/dir/', {
                'api': '1',
                'origin': origin,
                'destination': destination,
                'travelmode': 'driving',
              });
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.directions_car, color: Colors.white),
            label: const Text("Googleマップで車ルート"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00939C),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              // 現在地を優先的に使用
              final String origin;
              if (_currentPosition != null) {
                origin =
                    '${_currentPosition!.latitude.toStringAsFixed(6)},${_currentPosition!.longitude.toStringAsFixed(6)}';
              } else {
                final oLat = widget.departureLat;
                final oLng = widget.departureLng;
                origin = (oLat != null &&
                        oLng != null &&
                        (oLat != 0 || oLng != 0))
                    ? '${oLat.toStringAsFixed(6)},${oLng.toStringAsFixed(6)}'
                    : (widget.departureLabel.isNotEmpty
                        ? widget.departureLabel
                        : '出発地');
              }
              final hasPos = (pos.latitude != 0 && pos.longitude != 0);
              final destination = hasPos
                  ? '${pos.latitude},${pos.longitude}'
                  : '${widget.mountain["name"]} 登山口';
              final uri = Uri.https('www.google.com', '/maps/dir/', {
                'api': '1',
                'origin': origin,
                'destination': destination,
                'travelmode': 'transit',
              });
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.train, color: Colors.white),
            label: const Text("Googleマップで公共交通ルート"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10ABB4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ],
      ),
    );
  }

  // 🍴 周辺グルメ（郷土料理・そば）
  Widget _gourmetLinksCard(Map<String, dynamic> m) {
    final _Dest d = _resolveDestination(m);
    final base = d.title;
    final lat = d.lat;
    final lng = d.lng;
    final kws = ['郷土料理', 'そば'];
    return _linksCard(
        title: '周辺グルメ 🍴',
        color: const Color(0xFFE91E63),
        base: base,
        lat: lat,
        lng: lng,
        keywords: kws);
  }

  // ♨️ 周辺くつろぎ（温泉・サウナ・民宿・旅館・ホテル）
  Widget _relaxLinksCard(Map<String, dynamic> m) {
    final _Dest d = _resolveDestination(m);
    final base = d.title;
    final lat = d.lat;
    final lng = d.lng;
    final kws = ['温泉', 'サウナ', '民宿', '旅館', 'ホテル'];
    return _linksCard(
        title: '周辺くつろぎ ♨️',
        color: const Color(0xFFFF8F00),
        base: base,
        lat: lat,
        lng: lng,
        keywords: kws);
  }

  _Dest _resolveDestination(Map<String, dynamic> m) {
    final List ths =
        (m['trailheads'] is List) ? (m['trailheads'] as List) : const [];
    String title = (m['name'] ?? '').toString();
    double? lat = (m['lat'] is num) ? (m['lat'] as num).toDouble() : null;
    double? lng = (m['lng'] is num) ? (m['lng'] as num).toDouble() : null;
    if (ths.isNotEmpty) {
      final int idx = _selectedTrailheadIndex ?? 0;
      final Map th = Map.from(ths[idx]);
      final tlat = th['lat'];
      final tlng = th['lng'];
      if (tlat is num && tlng is num) {
        lat = tlat.toDouble();
        lng = tlng.toDouble();
      }
      title = (th['name'] ?? title).toString();
    }
    return _Dest(title: title, lat: lat, lng: lng);
  }

  Widget _linksCard({
    required String title,
    required Color color,
    required String base,
    required double? lat,
    required double? lng,
    required List<String> keywords,
  }) {
    final center = (lat != null && lng != null)
        ? '@${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)},14z'
        : '';
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: color)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: keywords.map((kw) {
              final q = '$base $kw';
              final url = Uri.parse(
                  'https://www.google.com/maps/search/${Uri.encodeComponent(q)}/$center');
              return OutlinedButton.icon(
                onPressed: () =>
                    launchUrl(url, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.map),
                label: Text('$kwを探す'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                ),
              );
            }).toList(),
          )
        ],
      ),
    );
  }

  // 🌟 AIおすすめカード（✅追加）
  Widget _aiRecommendationCard() {
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "🌟 あなたにおすすめの次の山",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            "過去の登山傾向からAIがあなたに合う山を提案します🌿",
            style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                // ひとまず前の画面（検索結果）へ戻ることで他候補を見られる導線を用意
                Navigator.maybePop(context);
              },
              icon: const Icon(Icons.list_alt),
              label: const Text('他の候補を見る'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF267365),
                side: const BorderSide(color: Color(0xFF267365)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          )
        ],
      ),
    );
  }

  // 💬 AIチャットセクション
  Widget _chatSection() {
    // final mountainId = widget.mountain["name"]; // 未使用
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("🧭 AIマウンテンコンシェルジュ",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          // ローカル/オンラインのモード表示（Firestoreは使用しない）
          Builder(
            builder: (context) {
              Widget _modeBanner() {
                final t = ApiService.lastTransport;
                if (t == 'local') {
                  return _chatFallbackNotice();
                } else if (t == 'worker' ||
                    t == 'direct' ||
                    t == 'stream-worker') {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F5EE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00939C).withOpacity(0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.cloud_done,
                            color: Color(0xFF00939C), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'オンラインAIに接続中（Gemini Flash）',
                            style: TextStyle(
                              color: Color(0xFF1E4F45),
                              height: 1.4,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              }

              // ローカルチャット履歴がない場合はウェルカムメッセージ
              if (_localChat.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _modeBanner(),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFE7F5EE).withOpacity(0.5),
                            const Color(0xFFE7F5EE),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF00939C).withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.assistant,
                                  color: Color(0xFF00939C), size: 28),
                              SizedBox(width: 8),
                              Text(
                                'はじめまして！',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF1E4F45),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'AIマウンテンコンシェルジュです。\nあなたの検索条件と天気予報を活かして、最適な山旅プランを提案します！',
                            style: TextStyle(
                              color: Colors.black87,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '💡 質問例：',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E4F45),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildSuggestionChip('おすすめのタイムスケジュールは？'),
                          const SizedBox(height: 6),
                          _buildSuggestionChip('この時期の注意点は？'),
                          const SizedBox(height: 6),
                          _buildSuggestionChip('下山後のおすすめスポットは？'),
                        ],
                      ),
                    ),
                  ],
                );
              }

              // チャット履歴を表示
              return Column(
                children: [
                  _modeBanner(),
                  const SizedBox(height: 12),
                  ..._localChat.map((d) {
                    final isUser = d['role'] == 'user';
                    return Container(
                      margin: EdgeInsets.only(
                        top: 6,
                        bottom: 6,
                        left: isUser ? 50 : 0,
                        right: isUser ? 0 : 50,
                      ),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFFF2CB05)
                            : const Color(0xFFE7F5EE),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        d['text'] ?? '',
                        style: const TextStyle(height: 1.4),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _chatCtrl,
                  maxLines: 4,
                  minLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: "登山計画を相談してみよう…\n（質問例：おすすめのタイムスケジュールは？）",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: null,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF00939C),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: _handleSendMessage,
                  icon: _isSendingLocalAi
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ))
                      : const Icon(Icons.send, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return InkWell(
      onTap: () {
        _chatCtrl.text = text;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00939C).withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 16, color: Color(0xFF00939C)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF1E4F45),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatFallbackNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F5EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00939C).withOpacity(0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF00939C), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ローカルAIモードで動作中（チャット履歴は保存されません）',
              style: TextStyle(
                color: Color(0xFF1E4F45),
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSendMessage() async {
    // final mountainId = widget.mountain["name"]; // 未使用
    final msg = _chatCtrl.text.trim();
    if (msg.isEmpty) return;
    _chatCtrl.clear();

    // ローカルAIモードで動作
    await _sendLocalAiMessage(msg);
  }

  Future<void> _sendLocalAiMessage(String userText) async {
    // 画面に即時反映
    setState(() {
      _localChat.add({'role': 'user', 'text': userText});
      _isSendingLocalAi = true;
    });

    final m = widget.mountain;
    final name = (m['name'] ?? '').toString();
    final pref = (m['pref'] ?? '').toString();
    final course = (m['course'] ?? m['popularRoute'] ?? '').toString();
    // 🎯 強化されたシステムプロンプト：検索条件と天気を活用
    final system = '''
あなたは「晴れ山SEARCH AIマウンテンコンシェルジュ」です。
ユーザーが選択した検索条件と天気予報を最大限に活用して、最適な山旅プランを提案してください。

【役割】
・安全第一で、季節・天候・難易度・アクセスを考慮した山旅満喫プランを日本語で提案
・検索条件に基づいた personalized なアドバイス
・天気予報を活用した具体的なタイムスケジュール提案
・日帰り/宿泊、温泉、郷土料理など、ユーザーの希望を最大限反映

【回答スタイル】
・タイムライン形式で具体的に（例：05:30 出発 → 08:00 登山口到着 → ...）
・箇条書き中心で読みやすく
・安全上の注意点を必ず含める
・絵文字を適度に使用して親しみやすく
''';

    // ユーザー検索条件を収集
    final searchConditions = <String>[];
    if (widget.selectedLevel != null && widget.selectedLevel!.isNotEmpty) {
      searchConditions.add('・難易度: ${widget.selectedLevel}');
    }
    if (widget.selectedAccessTime != null &&
        widget.selectedAccessTime!.isNotEmpty) {
      searchConditions.add('・アクセス時間: ${widget.selectedAccessTime}');
    }
    if (widget.selectedCourseTime != null &&
        widget.selectedCourseTime!.isNotEmpty) {
      searchConditions.add('・コースタイム: ${widget.selectedCourseTime}');
    }
    if (widget.selectedStyles != null && widget.selectedStyles!.isNotEmpty) {
      searchConditions.add('・登山スタイル: ${widget.selectedStyles!.join('、')}');
    }
    if (widget.selectedPurposes != null &&
        widget.selectedPurposes!.isNotEmpty) {
      searchConditions.add('・目的: ${widget.selectedPurposes!.join('、')}');
    }
    if (widget.priorityPrefs != null && widget.priorityPrefs!.isNotEmpty) {
      final prefs = widget.priorityPrefs!.entries
          .where((e) => e.value == 'must')
          .map((e) => e.key)
          .join('、');
      if (prefs.isNotEmpty) searchConditions.add('・優先条件: $prefs');
    }

    // 天気情報を追加
    final weatherInfo = <String>[];
    if (m['rain_am'] != null) weatherInfo.add('午前降水確率: ${m['rain_am']}');
    if (m['rain_pm'] != null) weatherInfo.add('午後降水確率: ${m['rain_pm']}');
    if (m['temp_c'] != null) weatherInfo.add('気温: ${m['temp_c']}°C');
    if (m['wind'] != null) weatherInfo.add('風速: ${m['wind']}');
    if (m['weather'] != null) weatherInfo.add('天気: ${m['weather']}');

    final user = [
      '【ユーザーの質問】',
      userText,
      '',
      '【選択された山の情報】',
      if (name.isNotEmpty) '・山名: $name',
      if (pref.isNotEmpty) '・都道府県: $pref',
      if (course.isNotEmpty) '・人気コース: $course',
      '',
      '【検索時の条件】',
      if ((widget.departureLabel).isNotEmpty) '・出発地: ${widget.departureLabel}',
      if (widget.plannedDate != null)
        '・登山予定日: ${widget.plannedDate!.toIso8601String().split('T').first}',
      ...searchConditions,
      '',
      if (weatherInfo.isNotEmpty) '【当日の天気予報】',
      ...weatherInfo.map((w) => '・$w'),
      '',
      '上記の情報を踏まえて、最適な山旅プランを具体的に提案してください。',
    ].join('\n');

    String reply;
    try {
      reply = await ApiService.askGemini(
        systemPrompt: system,
        userMessage: user,
        context: {
          'mountain': {
            'name': name,
            'pref': pref,
            'course': course,
          },
          'departure': widget.departureLabel,
          'plannedDate': widget.plannedDate?.toIso8601String(),
          'searchConditions': searchConditions,
          'weatherInfo': weatherInfo,
        },
      );
    } catch (e) {
      reply = '⚠️ AIからの応答取得に失敗しました。\nネットワーク接続をご確認の上、再度お試しください。\n\nエラー詳細: $e';
    }

    setState(() {
      _localChat.add({'role': 'assistant', 'text': reply});
      _isSendingLocalAi = false;
    });
  }

  // � カード装飾
  // シェアボタン（簡易版）
  Widget _shareButtons() {
    return const SizedBox.shrink();
  }

  // 保存とヒストリーボタン（簡易版）
  Widget _saveAndHistoryButtons(BuildContext context) {
    return const SizedBox.shrink();
  }

  Widget _cardContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}
