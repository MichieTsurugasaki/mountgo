import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'result_page.dart';
import 'facility_detail_page.dart';
import '../services/location_service.dart';
import '../widgets/gorgeous_sun_icon.dart';
import '../services/geocoding_service.dart';
import '../services/places_service.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  // ===== State =====
  final TextEditingController _departureCtrl = TextEditingController();
  final FocusNode _departureFocus = FocusNode();
  List<PlaceSuggestion> _placeSuggestions = [];
  Timer? _debounce;
  bool isStaySelected = false;
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;

  String? _accessTime;
  String? _level;
  String? _courseTime;
  final List<String> _accessMethods = []; // 複数選択
  final List<String> _selectedStyles = [];
  final List<String> _selectedPurposes = [];
  final List<String> _selectedOptions = [];
  bool _hyakumeizanOnly = false; // 日本百名山のみフィルタ
  bool _nihyakumeizanOnly = false; // 日本二百名山のみフィルタ
  int _ttlHours = 12; // DirectionsキャッシュTTL (UI設定)

  // 位置情報（本日の実装を維持）
  double? _departureLat;
  double? _departureLng;

  // ===== Palette (from image) =====
  static const Color tealDark = Color(0xFF004C50);
  static const Color teal = Color(0xFF00939C);
  static const Color tealLight = Color(0xFF10ABB4);
  // Removed unused palette colors to satisfy analyzer

  // neutrals / surfaces
  static const Color surface = Color(0xFFF8FBFB);
  static const Color card = Colors.white;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('ja_JP', null);
    // 開発: 6h / 本番: 12h をデフォルトに設定
    _ttlHours = kReleaseMode ? 12 : 6;
    // .env で上書き: DIRECTIONS_TTL_HOURS=6|12|任意数
    // テスト環境など dotenv 未初期化時は安全にスキップ
    final envTtl =
        dotenv.isInitialized ? dotenv.maybeGet('DIRECTIONS_TTL_HOURS') : null;
    final parsed = int.tryParse((envTtl ?? '').trim());
    if (parsed != null && parsed > 0 && parsed < 72) {
      _ttlHours = parsed;
    }
  }

  @override
  void dispose() {
    _departureCtrl.dispose();
    _departureFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 背景：山と澄んだ空気（深緑→黄）グラデーション
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
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildCard(context),
                  ],
                ),
              ),

              // 固定フッターの大きな立体グラデボタン + クレジット
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        // ボタンは別メソッドでビルド
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSearchButton(context),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const FacilityDetailPage(
                                mountainId: 'sample-mountain-id',
                                mountainName: 'サンプル山',
                              ),
                            ),
                          );
                        },
                        child: const Text('施設情報を管理（開発用）'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Produce by Mountain Connection',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== Header =====
  Widget _buildHeader() {
    return Column(
      children: [
        // タイトル（太陽アイコン＋白文字）
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GorgeousSunIcon(size: 27, glowSpread: 1.45, rayLength: 1.34),
            const SizedBox(width: 8),
            Text(
              "晴れ山 SEARCH",
              style: TextStyle(
                fontSize: 42,
                height: 1.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.white,
                shadows: [
                  Shadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(painter: _RidgePainter())),
        const SizedBox(height: 6),
        // サブキャッチ（カード風）
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: card.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: tealDark.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
            border: Border.all(color: tealLight.withValues(alpha: 0.2)),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: const [
              Text(
                '14日先までの天気予報で 天気',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF244045),
                ),
              ),
              GorgeousSunIcon(size: 7, glowSpread: 1.0, rayLength: 0.9),
              Text(
                'も気分も、あなたの晴れ山⛰️をみつけよう！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF244045),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===== Main Card =====
  Widget _buildCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: tealDark.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 8)),
        ],
        border: Border.all(color: teal.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ④ 出発地点：手動入力＋現在地（必須）
          Row(
            children: [
              const _SectionTitle("出発地点"),
              const SizedBox(width: 8),
              _requiredBadge(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  focusNode: _departureFocus,
                  controller: _departureCtrl,
                  decoration: InputDecoration(
                    hintText: "例）新宿駅、渋谷駅、東京タワー",
                    filled: true,
                    fillColor: surface,
                    prefixIcon: const Icon(Icons.search_rounded, color: teal),
                    suffixIcon: (_departureCtrl.text.isNotEmpty)
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              setState(() {
                                _departureCtrl.clear();
                                _placeSuggestions = [];
                                _departureLat = null;
                                _departureLng = null;
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFDFE8E8)),
                    ),
                  ),
                  onChanged: (value) => _onDepartureChanged(value),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: "現在地を使用",
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // 本日の実装（LocationService）を適用
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    try {
                      final pos = await LocationService.getCurrentPosition();
                      setState(() {
                        _departureLat = pos.latitude;
                        _departureLng = pos.longitude;
                        _departureCtrl.text = '現在地';
                      });
                      // 逆ジオコーディングして地名を表示（可能な場合）
                      try {
                        final name = await GeocodingService.reverseGeocode(
                          pos.latitude,
                          pos.longitude,
                          detailed: true, // 町名・番地まで取得
                        );
                        if (!mounted) return;
                        if (name != null && name.isNotEmpty) {
                          setState(() {
                            _departureCtrl.text = name;
                          });
                        }
                      } catch (e) {
                        debugPrint('reverseGeocode failed: $e');
                      }
                    } catch (e) {
                      messenger?.showSnackBar(const SnackBar(
                        content: Text("現在地を取得できませんでした"),
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text("現在地"),
                ),
              ),
            ],
          ),

          // 住所/施設名の候補一覧（Places Autocomplete）
          if (_departureFocus.hasFocus && _placeSuggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDFE8E8)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 6)),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _placeSuggestions.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFEFF3F3)),
                itemBuilder: (context, index) {
                  final s = _placeSuggestions[index];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined, color: teal),
                    title: Text(s.description,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      // place details → lat/lng を決定
                      final detail =
                          await PlacesService.fetchPlaceDetail(s.placeId);
                      if (!mounted) return;
                      setState(() {
                        _departureCtrl.text = s.description;
                        _departureLat = detail?.lat;
                        _departureLng = detail?.lng;
                        _placeSuggestions = [];
                      });
                      // フォーカスを外す
                      _departureFocus.unfocus();
                    },
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ⑤ 日帰り/宿泊 タブ（横に長く）
          Row(
            children: [
              Expanded(
                  child: _scheduleTab(context, "日帰り", !isStaySelected, false,
                      () => setState(() => isStaySelected = false))),
              const SizedBox(width: 10),
              Expanded(
                  child: _scheduleTab(context, "宿泊", isStaySelected, true,
                      () => setState(() => isStaySelected = true))),
            ],
          ),
          const SizedBox(height: 12),

          // カレンダー（必須）
          Row(
            children: [
              const _SectionTitle("登山日"),
              const SizedBox(width: 8),
              _requiredBadge(),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showCalendar(context, stay: isStaySelected),
            child: _buildDateLabel(),
          ),

          const SizedBox(height: 22),

          // ⑥ 出発地からのアクセス時間（必須）
          Row(
            children: [
              const _SectionTitle("出発地からのアクセス時間"),
              const SizedBox(width: 8),
              _requiredBadge(),
            ],
          ),
          const SizedBox(height: 8),
          _dropdown(
            "選択してください",
            const ["~1時間", "1〜2時間", "2〜3時間", "3〜5時間", "5時間以上"],
            _accessTime,
            (v) => setState(() => _accessTime = v),
          ),

          const SizedBox(height: 20),

          // ⑦ 希望コースタイム（単一選択）
          const _SectionTitle("希望コースタイム"),
          const SizedBox(height: 8),
          _singleSelectChips(
            ["〜2時間", "2〜4時間", "4〜6時間", "6〜9時間", "それ以上（縦走を含む）"],
            _courseTime,
            (v) => setState(() => _courseTime = v),
          ),

          const SizedBox(height: 20),

          // ⑧ レベル
          const _SectionTitle("レベル"),
          const SizedBox(height: 8),
          _dropdown(
            "レベルを選択",
            const ["初級", "中級", "上級"],
            _level,
            (v) => setState(() => _level = v),
          ),

          const SizedBox(height: 20),

          // ⑨ アクセス方法（複数選択可）
          const _SectionTitle("アクセス方法（複数選択可）"),
          const SizedBox(height: 8),
          _multiSelectChips(["車", "公共交通機関"], _accessMethods),

          const SizedBox(height: 22),

          // ➓ 詳細オプション（任意）
          _buildAccordion(),
        ],
      ),
    );
  }

  // ===== Tabs =====
  Widget _scheduleTab(BuildContext context, String label, bool active,
      bool stay, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        onTap();
        // show calendar after frame so Localizations/Material are available
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showCalendar(context, stay: stay);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 48,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [teal, tealLight],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: active ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: active ? tealLight : const Color(0xFFDAE7E7)),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: teal.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6)),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : tealDark,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  // ===== Date Label =====
  Widget _buildDateLabel() {
    String label;
    if (isStaySelected) {
      if (selectedStartDate != null && selectedEndDate != null) {
        final s = DateFormat('M月d日(E)', 'ja_JP').format(selectedStartDate!);
        final e = DateFormat('M月d日(E)', 'ja_JP').format(selectedEndDate!);
        label = '宿泊日程：$s ～ $e'; // スケジュール選択後に登山日が出る
      } else {
        label = '宿泊日程を選択（最大2泊3日）';
      }
    } else {
      label = selectedStartDate != null
          ? '登山日：${DateFormat('M月d日(E)', 'ja_JP').format(selectedStartDate!)}'
          : '登山日を選択';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDFE8E8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: tealDark),
            ),
          ),
          const Icon(Icons.calendar_month_rounded, color: teal, size: 20),
        ],
      ),
    );
  }

  // ===== Calendar (JP themed, bug-safe) =====
  Future<void> _showCalendar(BuildContext context, {bool stay = false}) async {
    final now = DateTime.now();

    if (stay) {
      final DateTimeRange initial = (selectedStartDate != null &&
              selectedEndDate != null)
          ? DateTimeRange(start: selectedStartDate!, end: selectedEndDate!)
          : DateTimeRange(start: now, end: now.add(const Duration(days: 1)));
      DateTimeRange? picked;
      try {
        picked = await showDateRangePicker(
          context: context,
          locale: const Locale('ja', 'JP'),
          initialDateRange: initial,
          firstDate: now,
          // 限定：今日から14日間のみ選択可
          lastDate: now.add(const Duration(days: 14)),
          builder: (BuildContext ctx, Widget? child) {
            // グローバルの Localizations (main.dart) を利用。ここではサイズだけ調整。
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: child,
              ),
            );
          },
        );
      } catch (e, st) {
        // Log and show a safe alert instead of letting the tool crash.
        debugPrint('showDateRangePicker error: $e\n$st');
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('カレンダー表示エラー'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(c).pop(),
                  child: const Text('閉じる')),
            ],
          ),
        );
        return;
      }

      if (picked != null) {
        final nights = picked.end.difference(picked.start).inDays;
        if (nights > 2) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('宿泊は最大2泊3日までです🌙'),
            backgroundColor: Colors.orange,
          ));
          return;
        }
        final p = picked;
        setState(() {
          isStaySelected = true;
          selectedStartDate = p.start;
          selectedEndDate = p.end; // 自動保存
        });
      }
    } else {
      // 日帰りは単一日付のピッカーで選択（同日ダブルタップ不要にする）
      final DateTime initial = selectedStartDate ?? now;
      DateTime? picked;
      try {
        picked = await showDatePicker(
          context: context,
          locale: const Locale('ja', 'JP'),
          initialDate: initial.isBefore(now) ? now : initial,
          firstDate: now,
          // 限定：今日から14日間のみ選択可
          lastDate: now.add(const Duration(days: 14)),
          builder: (BuildContext ctx, Widget? child) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: child,
              ),
            );
          },
        );
      } catch (e, st) {
        debugPrint('showDatePicker (day) error: $e\n$st');
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('カレンダー表示エラー'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(c).pop(),
                  child: const Text('閉じる')),
            ],
          ),
        );
        return;
      }

      if (picked != null) {
        final selected = DateTime(picked.year, picked.month, picked.day);
        setState(() {
          isStaySelected = false;
          selectedStartDate = selected;
          selectedEndDate = null; // 日帰りは終了日を使わない
        });
      }
    }
  }

  // ===== Dropdown =====
  Widget _dropdown(
    String label,
    List<String> items,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDFE8E8)),
      ),
      child: DropdownButton<String>(
        isExpanded: true,
        underline: const SizedBox(),
        value: value,
        hint: Text(label, style: const TextStyle(color: Colors.black54)),
        icon: const Icon(Icons.expand_more, color: teal),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ===== Chips (single select) =====
  Widget _singleSelectChips(
    List<String> options,
    String? current,
    ValueChanged<String> onSelect,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final selected = current == opt;
        return ChoiceChip(
          label: Text(opt),
          selected: selected,
          selectedColor: teal,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : tealDark,
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide(color: selected ? teal : const Color(0xFFE2E8E8)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (v) {
            if (v) onSelect(opt);
          },
        );
      }).toList(),
    );
  }

  // ===== Chips (multi select) =====
  Widget _multiSelectChips(List<String> options, List<String> selectedList) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final selected = selectedList.contains(opt);
        return FilterChip(
          label: Text(opt),
          selected: selected,
          selectedColor: tealLight.withValues(alpha: 0.18),
          checkmarkColor: tealDark,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? tealDark : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide(color: selected ? teal : const Color(0xFFE2E8E8)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (v) {
            setState(() {
              if (v) {
                selectedList.add(opt);
              } else {
                selectedList.remove(opt);
              }
            });
          },
        );
      }).toList(),
    );
  }

  // ===== 必須バッジ =====
  Widget _requiredBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '必須',
        style: TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  // ===== Accordion (Details) =====
  Widget _buildAccordion() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 6),
        backgroundColor: surface,
        collapsedBackgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          "詳細オプション（任意）",
          style: TextStyle(fontWeight: FontWeight.w800, color: tealDark),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SubTitle("目的"),
                _multiSelectChips(
                    ["冒険", "癒し", "リフレッシュ", "デート", "家族旅行"], _selectedPurposes),
                const SizedBox(height: 14),
                const _SubTitle("スタイル"),
                _multiSelectChips(
                    ["ハイキング", "絶景", "自然", "稜線", "岩場", "鎖場"], _selectedStyles),
                const SizedBox(height: 14),
                const _SubTitle("希望オプション"),
                _multiSelectChips([
                  "ロープウェイ",
                  "ケーブルカー",
                  "山小屋",
                  "テント泊",
                  "温泉を楽しみたい",
                  "郷土料理を味わいたい"
                ], _selectedOptions),
                const SizedBox(height: 16),

                // 日本百名山のみフィルタ
                CheckboxListTile(
                  title: const Text(
                    '日本百名山のみ表示',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: const Text('日本百名山に選定された山のみを表示します'),
                  value: _hyakumeizanOnly,
                  onChanged: (v) =>
                      setState(() => _hyakumeizanOnly = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                // 日本二百名山のみフィルタ
                CheckboxListTile(
                  title: const Text(
                    '日本二百名山のみ表示',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: const Text('日本二百名山に選定された山のみを表示します'),
                  value: _nihyakumeizanOnly,
                  onChanged: (v) =>
                      setState(() => _nihyakumeizanOnly = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== Fixed Footer Button =====
  Widget _buildSearchButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          // 視認性を確保した「黄緑 → 濃い緑」グラデーション（右を濃く）
          colors: [Color(0xFFA8E063), Color(0xFF104E41)],
          stops: [0.0, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(44),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF104E41).withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 10)),
        ],
      ),
      child: ElevatedButton(
        onPressed: () => _onSearchPressed(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(59),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(44)),
        ),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 59),
          child: const Text(
            "🌤 晴れている山を探す",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 1.0,
              shadows: [
                Shadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    offset: Offset(0, 1.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== Validation + Navigation (必須チェック) =====
  void _onSearchPressed(BuildContext context) {
    final missing = <String>[];
    if (_departureCtrl.text.trim().isEmpty) missing.add('出発地点');
    if (isStaySelected) {
      if (selectedStartDate == null || selectedEndDate == null) {
        missing.add('宿泊日程');
      }
    } else {
      if (selectedStartDate == null) missing.add('登山日');
    }
    if (_accessTime == null || _accessTime!.isEmpty)
      missing.add('出発地からのアクセス時間');

    if (missing.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('未入力の必須項目があります'),
          content: Text('以下を入力してください。\n- ${missing.join('\n- ')}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    print(
        '🔵🔵🔵 SearchPage: ResultPageへ遷移 - hyakumeizanOnly: $_hyakumeizanOnly, nihyakumeizanOnly: $_nihyakumeizanOnly');
    final List<String> requiredTags = [];
    if (_hyakumeizanOnly) requiredTags.add('日本百名山');
    if (_nihyakumeizanOnly) requiredTags.add('日本二百名山');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(
          departureLabel: _departureCtrl.text.trim().isEmpty
              ? '出発地未設定'
              : _departureCtrl.text.trim(),
          departureLat: _departureLat ?? 0,
          departureLng: _departureLng ?? 0,
          selectedLevel: _level,
          selectedAccessTime: _accessTime,
          selectedCourseTime: _courseTime,
          selectedStyles: _selectedStyles,
          selectedPurposes: _selectedPurposes,
          selectedOptions: _selectedOptions,
          selectedAccessMethods: _accessMethods,
          plannedStartDate: selectedStartDate,
          plannedEndDate: selectedEndDate,
          cacheTtlHours: _ttlHours,
          hyakumeizanOnly: _hyakumeizanOnly,
          nihyakumeizanOnly: _nihyakumeizanOnly,
          requiredTagFilters: requiredTags.isEmpty ? null : requiredTags,
        ),
      ),
    );
  }

  // ===== Places: debounce 検索 =====
  void _onDepartureChanged(String value) {
    setState(() {}); // suffixIcon表示のため
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _placeSuggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final list = await PlacesService.autocomplete(value);
      if (!mounted) return;
      setState(() {
        _placeSuggestions = list;
      });
    });
  }
}

// ===== Titles =====
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: _SearchPageState.tealDark,
        ));
  }
}

class _SubTitle extends StatelessWidget {
  final String text;
  const _SubTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _SearchPageState.teal,
          )),
    );
  }
}

// うっすら山脈のアウトラインを描く装飾用ペインタ
class _RidgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final h = size.height;
    final w = size.width;
    // 中央は低め、左は1つ大きな峰、右側は非対称で起伏を増やす
    path.moveTo(0, h * 0.72);
    path.lineTo(w * 0.08, h * 0.60);
    path.lineTo(w * 0.16, h * 0.52);
    path.lineTo(w * 0.22, h * 0.25); // 左高峰（鋭く）
    path.lineTo(w * 0.28, h * 0.55);
    path.lineTo(w * 0.36, h * 0.46);
    path.lineTo(w * 0.44, h * 0.60);
    path.lineTo(w * 0.50, h * 0.68); // タイトル直下は穏やか
    path.lineTo(w * 0.56, h * 0.58);
    path.lineTo(w * 0.64, h * 0.46);
    // 右側：小刻みなアップダウンで起伏を強く（左右非対称）
    path.lineTo(w * 0.70, h * 0.60);
    path.lineTo(w * 0.74, h * 0.40);
    path.lineTo(w * 0.78, h * 0.26); // 右高峰（鋭く）
    path.lineTo(w * 0.81, h * 0.45);
    path.lineTo(w * 0.835, h * 0.32); // こぶ状の小ピーク
    path.lineTo(w * 0.86, h * 0.50);
    path.lineTo(w * 0.89, h * 0.38); // ノッチ
    path.lineTo(w * 0.92, h * 0.60);
    path.lineTo(w * 0.96, h * 0.48);
    path.lineTo(w, h * 0.58);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
