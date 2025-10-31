import 'package:flutter/material.dart';
import 'package:yamabiyori_flutter/utils/logger.dart';
import 'dart:math';
import 'detail_page.dart';
import '../widgets/simple_sun_icon.dart';
import '../services/weather_score.dart';
import '../services/weight_config.dart';
import '../services/open_meteo_service.dart';
import '../services/firestore_service.dart';
import '../services/directions_service.dart';
import '../services/airport_service.dart';
import '../services/directions_cache.dart';
import '../services/travel_config.dart';

class ResultPage extends StatelessWidget {
  // Teal palette to match SearchPage
  static const Color _teal = Color(0xFF00939C);
  static const Color _card = Colors.white;

  static double _titleFontSize(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w < 360 ? 28.0 : 32.0;
  }

  // 表示件数（無料プランは3件固定）
  final ValueNotifier<int> _displayCount = ValueNotifier<int>(3);

  final String departureLabel;
  final double departureLat;
  final double departureLng;

  final String? selectedLevel;
  final String? selectedAccessTime;
  final String? selectedCourseTime;
  final List<String>? selectedStyles;
  final List<String>? selectedPurposes;
  final List<String>? selectedOptions;
  final List<String>? selectedAccessMethods;
  final DateTime? plannedStartDate;
  final DateTime? plannedEndDate;
  final Map<String, String>? priorityPrefs;
  final int cacheTtlHours;
  final bool hyakumeizanOnly; // 日本百名山のみフィルタ
  final bool nihyakumeizanOnly; // 日本二百名山のみフィルタ
  final List<String>? requiredTagFilters; // 任意の必須タグ（いずれかを含む）

  ResultPage({
    super.key,
    required this.departureLabel,
    required this.departureLat,
    required this.departureLng,
    this.selectedLevel,
    this.selectedAccessTime,
    this.selectedCourseTime,
    this.selectedStyles,
    this.selectedPurposes,
    this.selectedOptions,
    this.selectedAccessMethods,
    this.plannedStartDate,
    this.plannedEndDate,
    this.priorityPrefs,
    this.cacheTtlHours = 12,
    this.hyakumeizanOnly = false,
    this.nihyakumeizanOnly = false,
    this.requiredTagFilters,
  });

  Map<String, dynamic> _toForecast(Map<String, dynamic> m) {
    double pop = 0.0;
    try {
      // 優先: 数値のAM/PM降水確率（0-100）を使用
      final int? amNum =
          (m['_am_pop_pct'] is int) ? m['_am_pop_pct'] as int : null;
      final int? pmNum =
          (m['_pm_pop_pct'] is int) ? m['_pm_pop_pct'] as int : null;
      if (pmNum != null) {
        pop = pmNum.toDouble();
      } else if (amNum != null) {
        pop = amNum.toDouble();
      } else {
        // 旧: 文字列の “xx%” をパース
        final am = m['rain_am']?.toString().replaceAll('%', '');
        final pm = m['rain_pm']?.toString().replaceAll('%', '');
        if (pm != null && pm.isNotEmpty) {
          pop = double.tryParse(pm) ?? 0.0;
        } else if (am != null && am.isNotEmpty) {
          pop = double.tryParse(am) ?? 0.0;
        }
      }
    } catch (_) {}
    pop = (pop / 100.0).clamp(0.0, 1.0);

    double wind = 0.0;
    try {
      final w = m['wind']?.toString().replaceAll('m/s', '').trim();
      wind = double.tryParse(w ?? '') ?? 0.0;
    } catch (_) {}

    double cloud =
        (m['cloud_pct'] is num) ? (m['cloud_pct'] as num).toDouble() : 20.0;
    double temp = (m['temp_c'] is num) ? (m['temp_c'] as num).toDouble() : 15.0;
    double precip = pop > 0.5 ? 3.0 : 0.0;

    return {
      'pop': pop,
      'wind_m_s': wind,
      'cloud_pct': cloud,
      'temp_c': temp,
      'precip_mm': precip,
      'condition': m['weather']?.toString(),
    };
  }

  // コースタイムを分に変換（例："5時間30分" → 330）
  int _parseTimeToMinutes(String timeStr) {
    try {
      int totalMinutes = 0;
      final hourMatch = RegExp(r'(\d+)時間').firstMatch(timeStr);
      final minuteMatch = RegExp(r'(\d+)分').firstMatch(timeStr);

      if (hourMatch != null) {
        totalMinutes += int.parse(hourMatch.group(1)!) * 60;
      }
      if (minuteMatch != null) {
        totalMinutes += int.parse(minuteMatch.group(1)!);
      }

      return totalMinutes;
    } catch (_) {
      return 0;
    }
  }

  // コースタイムの範囲を取得
  Map<String, int>? _getCourseTimeRange(String timeRange) {
    switch (timeRange) {
      case '〜2時間':
        return {'min': 0, 'max': 120};
      case '2〜4時間':
        return {'min': 120, 'max': 240};
      case '4〜6時間':
        return {'min': 240, 'max': 360};
      case '6〜9時間':
        return {'min': 360, 'max': 540};
      case 'それ以上（縦走を含む）':
        return {'min': 540, 'max': 9999};
      default:
        return null;
    }
  }

  // アクセス時間の範囲を取得
  Map<String, int>? _getAccessTimeRange(String timeRange) {
    switch (timeRange) {
      case '~1時間':
        return {'min': 0, 'max': 60};
      case '1〜2時間':
        return {'min': 60, 'max': 120};
      case '2〜3時間':
        return {'min': 120, 'max': 180};
      case '3〜5時間':
        return {'min': 180, 'max': 300};
      case '5時間以上':
        return {'min': 300, 'max': 9999};
      default:
        return null;
    }
  }

  // Firestore の mountains から候補を取得（失敗時は最小モックにフォールバック）
  Future<List<Map<String, dynamic>>> _loadCandidateMountains() async {
    print('=== _loadCandidateMountains 開始 ===');
    // Firestoreを優先。必要フィールド未整備でも最低限のキーを補完して扱う
    try {
      print('🔍 Firestoreからデータを取得中...');
      final fsList = await FirestoreService.listMountains(limit: 80);
      print('📊 Firestoreから${fsList.length}件取得');
      final normalized = fsList
          .map((m) {
            // 基本フィールド
            final id = m['id'];
            final name = (m['name'] ?? '').toString();
            final nameKana = (m['name_kana'] ?? '').toString();
            final pref = (m['pref'] ?? '').toString();
            double? lat =
                (m['lat'] is num) ? (m['lat'] as num).toDouble() : null;
            double? lng =
                (m['lng'] is num) ? (m['lng'] as num).toDouble() : null;
            final course = (m['popularRoute'] ?? m['course'] ?? '').toString();
            final description = (m['description'] ?? '').toString();

            // 任意フィールド
            final access = (m['access'] is List) ? m['access'] : <String>[];
            final tags = (m['tags'] is List) ? m['tags'] : <String>[];
            final styles = (m['styles'] is List) ? m['styles'] : <String>[];
            final purposes =
                (m['purposes'] is List) ? m['purposes'] : <String>[];
            final level = (m['level'] ?? '').toString();
            // コースタイム（未設定なら代替フィールドから生成）
            String courseTime = (m['courseTime'] ?? '').toString();
            if (courseTime.isEmpty) {
              final totalMin = (m['course_time_total'] is num)
                  ? (m['course_time_total'] as num).toInt()
                  : (int.tryParse((m['course_time_total'] ?? '').toString()) ??
                      0);
              if (totalMin > 0) {
                final h = totalMin ~/ 60;
                final mm = totalMin % 60;
                courseTime = h > 0 ? '$h時間$mm分' : '$mm分';
              } else if (m['course_time_up'] != null ||
                  m['course_time_down'] != null) {
                final up = (m['course_time_up'] is num)
                    ? (m['course_time_up'] as num).toInt()
                    : (int.tryParse((m['course_time_up'] ?? '').toString()) ??
                        0);
                final down = (m['course_time_down'] is num)
                    ? (m['course_time_down'] as num).toInt()
                    : (int.tryParse((m['course_time_down'] ?? '').toString()) ??
                        0);
                final sum = up + down;
                if (sum > 0) {
                  final h = sum ~/ 60;
                  final mm = sum % 60;
                  courseTime = h > 0 ? '$h時間$mm分' : '$mm分';
                }
              } else if (m['median_time_h'] != null) {
                final hours = double.tryParse(m['median_time_h'].toString());
                if (hours != null && hours > 0) {
                  final h = hours.floor();
                  final mm = ((hours - h) * 60).round();
                  courseTime = '$h時間$mm分';
                }
              }
              if (courseTime.isEmpty) courseTime = '—';
            }

            // アクセス時間フィールド
            final timeCar = (m['accessCar'] ?? m['time_car'] ?? '').toString();
            final timePublic =
                (m['accessPublic'] ?? m['time_public'] ?? '').toString();
            final timeCombined =
                (m['accessTime'] ?? m['time'] ?? '').toString();

            // trailheads を保持し、山座標が無ければ先頭の登山口を使用
            final ths = (m['trailheads'] is List)
                ? (m['trailheads'] as List)
                : const [];
            if ((lat == null || lng == null) && ths.isNotEmpty) {
              final th0 = ths.first;
              final thLat = (th0 is Map && th0['lat'] is num)
                  ? (th0['lat'] as num).toDouble()
                  : null;
              final thLng = (th0 is Map && th0['lng'] is num)
                  ? (th0['lng'] as num).toDouble()
                  : null;
              if (thLat != null && thLng != null) {
                lat = thLat;
                lng = thLng;
              }
            }

            return {
              'id': id,
              'name': name,
              'name_kana': nameKana,
              'pref': pref,
              'lat': lat,
              'lng': lng,
              'course': course,
              'description': description,
              'time_car': timeCar,
              'time_public': timePublic,
              'time': timeCombined,
              'access': access,
              'tags': tags,
              'styles': styles,
              'purposes': purposes,
              'level': level,
              'courseTime': courseTime,
              'trailheads': ths,
            };
          })
          .where((e) => e['name'].toString().isNotEmpty)
          .toList();
      if (normalized.isNotEmpty) {
        print('✅ Firestoreデータを使用: ${normalized.length}件');
        return normalized;
      }
      print('⚠️ Firestoreデータが空、フォールバックを使用');
    } catch (e) {
      print('❌ Firestore取得エラー: $e');
    }

    // フォールバック（日本の人気の山20+件）
    print('📋 フォールバックデータを使用');
    return [
      // === 初級（コースタイム ~4時間）===
      {
        'name': '高尾山',
        'name_kana': 'たかおさん',
        'pref': '東京都',
        'lat': 35.625,
        'lng': 139.243,
        'course': '1号路 表参道コース',
        'description':
            '都心から1時間、標高599mの身近な名山。ケーブルカーやリフトもあり、初心者から楽しめる。山頂からは富士山や都心の眺望が素晴らしい。',
        'access': ['公共交通機関', '車'],
        'tags': ['ケーブルカー', '温泉', '郷土料理'],
        'styles': ['ハイキング', '自然'],
        'purposes': ['癒し', 'デート', '家族旅行'],
        'level': '初級',
        'courseTime': '2時間10分',
        'time_car': '60',
        'time_public': '70',
        'time': '60分（車）/ 70分（公共交通機関）',
      },
      {
        'name': '阿蘇山',
        'name_kana': 'あそさん',
        'pref': '熊本県',
        'lat': 32.8842,
        'lng': 131.1047,
        'course': 'ロープウェイコース',
        'description':
            '標高1,592m、世界最大級のカルデラを持つ活火山。ロープウェイで火口近くまで行ける。噴煙を上げる中岳火口は圧巻。',
        'access': ['車'],
        'tags': ['ロープウェイ', '温泉', '郷土料理'],
        'styles': ['絶景', '自然'],
        'purposes': ['癒し', '家族旅行'],
        'level': '初級',
        'courseTime': '2時間00分',
        'time_car': '180',
        'time_public': '240',
        'time': '180分（車）/ 240分（公共交通機関）',
      },

      // === 中級（コースタイム 4~6時間）===
      {
        'name': '塔ノ岳',
        'name_kana': 'とうのだけ',
        'pref': '神奈川県',
        'lat': 35.4503,
        'lng': 139.1595,
        'course': '大倉尾根コース',
        'description':
            '丹沢の名峰、標高1,491m。大倉尾根は「バカ尾根」と呼ばれる急登だが、山頂からの富士山と相模湾の眺望は絶景。',
        'access': ['車', '公共交通機関'],
        'tags': ['山小屋', '温泉', '郷土料理'],
        'styles': ['絶景', '稜線'],
        'purposes': ['冒険', 'リフレッシュ'],
        'level': '中級',
        'courseTime': '5時間30分',
        'time_car': '150',
        'time_public': '180',
        'time': '150分（車）/ 180分（公共交通機関）',
      },
      {
        'name': '木曽駒ヶ岳',
        'name_kana': 'きそこまがたけ',
        'pref': '長野県',
        'lat': 35.7851,
        'lng': 137.7982,
        'course': '千畳敷カールコース',
        'description':
            '標高2,956m。駒ヶ岳ロープウェイで千畳敷カールまで一気に登れる。高山植物の宝庫で、稜線からの眺望も素晴らしい。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', 'ロープウェイ', '山小屋', 'テント泊', '温泉'],
        'styles': ['絶景', '稜線'],
        'purposes': ['癒し', 'リフレッシュ'],
        'level': '中級',
        'courseTime': '4時間00分',
        'time_car': '240',
        'time_public': '300',
        'time': '240分（車）/ 300分（公共交通機関）',
      },
      {
        'name': '立山',
        'name_kana': 'たてやま',
        'pref': '富山県',
        'lat': 36.5740,
        'lng': 137.6185,
        'course': '室堂～雄山コース',
        'description':
            '標高3,015m、立山黒部アルペンルートでアクセス抜群。室堂から雄山へのルートは整備されており、3,000m級を体験できる。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', 'ロープウェイ', 'ケーブルカー', '山小屋', '温泉', '郷土料理'],
        'styles': ['絶景', '稜線'],
        'purposes': ['癒し', 'リフレッシュ'],
        'level': '中級',
        'courseTime': '5時間00分',
        'time_car': '180',
        'time_public': '210',
        'time': '180分（車）/ 210分（公共交通機関）',
      },
      {
        'name': '月山',
        'name_kana': 'がっさん',
        'pref': '山形県',
        'lat': 38.5497,
        'lng': 140.0259,
        'course': '姥沢登山口コース',
        'description':
            '標高1,984m、出羽三山の主峰。夏でも残雪があり、高山植物の宝庫。リフト利用で姥ヶ岳まで上がれば比較的楽に登れる。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', 'ロープウェイ', '山小屋', '温泉', '郷土料理'],
        'styles': ['絶景', '自然'],
        'purposes': ['癒し', 'リフレッシュ'],
        'level': '中級',
        'courseTime': '5時間00分',
        'time_car': '210',
        'time_public': '270',
        'time': '210分（車）/ 270分（公共交通機関）',
      },
      {
        'name': '霧島山',
        'name_kana': 'きりしまやま',
        'pref': '宮崎県・鹿児島県',
        'lat': 31.9331,
        'lng': 130.8531,
        'course': 'えびの高原～韓国岳コース',
        'description':
            '標高1,700m（韓国岳）、火山群からなる霊峰。韓国岳からは桜島や開聞岳を望む絶景。霧島温泉郷が近く、登山と温泉を楽しめる。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', '山小屋', '温泉', '郷土料理'],
        'styles': ['絶景', '自然'],
        'purposes': ['癒し', 'リフレッシュ'],
        'level': '中級',
        'courseTime': '4時間00分',
        'time_car': '240',
        'time_public': '300',
        'time': '240分（車）/ 300分（公共交通機関）',
      },

      // === 中級～上級（コースタイム 6~9時間）===
      {
        'name': '丹沢山',
        'name_kana': 'たんざわさん',
        'pref': '神奈川県',
        'lat': 35.4760,
        'lng': 139.1760,
        'course': '塔ノ岳経由 丹沢山縦走コース',
        'description':
            '標高1,567m、丹沢山地の最高峰。塔ノ岳から稜線を縦走するルートが人気。ブナ林の美しい自然と展望の良い稜線歩きが魅力。',
        'access': ['車', '公共交通機関'],
        'tags': ['山小屋', 'テント泊', '温泉', '郷土料理'],
        'styles': ['稜線', '絶景'],
        'purposes': ['冒険', 'リフレッシュ'],
        'level': '中級',
        'courseTime': '6時間45分',
        'time_car': '125',
        'time_public': '165',
        'time': '125分（車）/ 165分（公共交通機関）',
      },
      {
        'name': '岩手山',
        'name_kana': 'いわてさん',
        'pref': '岩手県',
        'lat': 39.8514,
        'lng': 141.0037,
        'course': '馬返し登山口コース',
        'description':
            '標高2,038m、岩手県の最高峰。「南部片富士」と呼ばれる美しい山容。樹林帯から火山地形まで変化に富む登山道。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', '山小屋', '温泉', '郷土料理'],
        'styles': ['絶景', '自然'],
        'purposes': ['冒険', 'リフレッシュ'],
        'level': '中級',
        'courseTime': '8時間00分',
        'time_car': '240',
        'time_public': '300',
        'time': '240分（車）/ 300分（公共交通機関）',
      },
      // === 上級（コースタイム 9時間以上、技術必要）===
      {
        'name': '富士山',
        'name_kana': 'ふじさん',
        'pref': '静岡県・山梨県',
        'lat': 35.3606,
        'lng': 138.7274,
        'course': '富士宮口五合目コース',
        'description':
            '標高3,776m、日本最高峰。7月〜9月の夏山シーズンのみ登山可能。高山病対策と防寒具が必須。山頂からのご来光は一生の思い出に。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', '山小屋', '温泉', '郷土料理'],
        'styles': ['絶景'],
        'purposes': ['冒険'],
        'level': '上級',
        'courseTime': '10時間00分',
        'time_car': '180',
        'time_public': '240',
        'time': '180分（車）/ 240分（公共交通機関）',
      },
      {
        'name': '赤岳',
        'name_kana': 'あかだけ',
        'pref': '長野県・山梨県',
        'lat': 35.9710,
        'lng': 138.3709,
        'course': '文三郎尾根コース',
        'description':
            '標高2,899m、八ヶ岳連峰の最高峰。岩場と鎖場があり、登山技術が必要。山頂からは南北アルプスや富士山の大パノラマ。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', '山小屋', 'テント泊', '温泉', '郷土料理'],
        'styles': ['岩場', '鎖場', '絶景'],
        'purposes': ['冒険'],
        'level': '上級',
        'courseTime': '9時間00分',
        'time_car': '210',
        'time_public': '270',
        'time': '210分（車）/ 270分（公共交通機関）',
      },
      {
        'name': '槍ヶ岳',
        'name_kana': 'やりがたけ',
        'pref': '長野県',
        'lat': 36.3356,
        'lng': 137.6464,
        'course': '上高地～槍沢コース',
        'description':
            '標高3,180m、日本のマッターホルンと称される名峰。山頂直下の梯子と鎖場は高度感抜群。槍ヶ岳山荘での一泊が必須。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', '山小屋', 'テント泊', '温泉', '郷土料理'],
        'styles': ['岩場', '鎖場', '絶景'],
        'purposes': ['冒険'],
        'level': '上級',
        'courseTime': '16時間00分',
        'time_car': '300',
        'time_public': '360',
        'time': '300分（車）/ 360分（公共交通機関）',
      },
      {
        'name': '穂高岳',
        'name_kana': 'ほたかだけ',
        'pref': '長野県',
        'lat': 36.2897,
        'lng': 137.6486,
        'course': '上高地～涸沢～奥穂高岳',
        'description':
            '標高3,190m、北アルプスの盟主。奥穂高岳、前穂高岳、北穂高岳など複数のピークからなる。岩稜帯の縦走は高度な技術が必要。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', '山小屋', 'テント泊', '温泉', '郷土料理'],
        'styles': ['岩場', '鎖場', '絶景'],
        'purposes': ['冒険'],
        'level': '上級',
        'courseTime': '15時間00分',
        'time_car': '300',
        'time_public': '360',
        'time': '300分（車）/ 360分（公共交通機関）',
      },
      {
        'name': '大峰山',
        'name_kana': 'おおみねさん',
        'pref': '奈良県',
        'lat': 34.1795,
        'lng': 135.9286,
        'course': '行者還トンネル～八経ヶ岳',
        'description':
            '標高1,915m（八経ヶ岳）、近畿最高峰。修験道の聖地で、弥山、八経ヶ岳へと続く稜線歩き。鎖場や岩場もあり登山技術が必要。',
        'access': ['車', '公共交通機関'],
        'tags': ['山小屋', 'テント泊', '温泉', '郷土料理'],
        'styles': ['鎖場', '自然'],
        'purposes': ['冒険'],
        'level': '上級',
        'courseTime': '9時間00分',
        'time_car': '240',
        'time_public': '300',
        'time': '240分（車）/ 300分（公共交通機関）',
      },
      {
        'name': '屋久島・宮之浦岳',
        'name_kana': 'やくしま・みやのうらだけ',
        'pref': '鹿児島県',
        'lat': 30.3346,
        'lng': 130.5054,
        'course': '淀川登山口コース',
        'description':
            '標高1,936m、九州最高峰。世界自然遺産の原生林を抜けて登る。往復11時間と長丁場で体力が必要。屋久島の大自然を満喫できる。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', '山小屋', 'テント泊', '温泉', '郷土料理'],
        'styles': ['自然'],
        'purposes': ['冒険', '癒し'],
        'level': '上級',
        'courseTime': '11時間00分',
        'time_car': '60',
        'time_public': '90',
        'time': '60分（車）/ 90分（公共交通機関）',
      },

      // === 追加の人気の山 ===
      {
        'name': '大菩薩嶺',
        'name_kana': 'だいぼさつれい',
        'pref': '山梨県',
        'lat': 35.7686,
        'lng': 138.8342,
        'course': '上日川峠コース',
        'description':
            '標高2,057m、初心者でも楽しめる稜線歩き。上日川峠から登れば、比較的楽に2,000m級の山を体験できる。大菩薩峠からの富士山の眺望は絶景。',
        'access': ['車', '公共交通機関'],
        'tags': ['山小屋', '温泉', '郷土料理'],
        'styles': ['絶景', '稜線'],
        'purposes': ['癒し', 'リフレッシュ'],
        'level': '初級',
        'courseTime': '4時間00分',
        'time_car': '150',
        'time_public': '210',
        'time': '150分（車）/ 210分（公共交通機関）',
      },
      {
        'name': '筑波山',
        'name_kana': 'つくばさん',
        'pref': '茨城県',
        'lat': 36.2256,
        'lng': 140.1063,
        'course': 'ケーブルカー～女体山コース',
        'description': '標高877m、関東平野を一望できる眺望の良い山。ケーブルカーやロープウェイもあり、初心者や家族連れにも人気。',
        'access': ['車', '公共交通機関'],
        'tags': ['日本百名山', 'ケーブルカー', 'ロープウェイ', '温泉', '郷土料理'],
        'styles': ['ハイキング', '絶景'],
        'purposes': ['癒し', 'デート', '家族旅行'],
        'level': '初級',
        'courseTime': '2時間30分',
        'time_car': '90',
        'time_public': '120',
        'time': '90分（車）/ 120分（公共交通機関）',
      },
      {
        'name': '御岳山',
        'name_kana': 'みたけさん',
        'pref': '東京都',
        'lat': 35.7819,
        'lng': 139.1359,
        'course': 'ケーブルカー～御岳山',
        'description':
            '標高929m、古くから信仰の山として親しまれてきた。ケーブルカーで気軽に登れ、武蔵御嶽神社や滝を巡るハイキングコースも人気。',
        'access': ['車', '公共交通機関'],
        'tags': ['ケーブルカー', '温泉', '郷土料理'],
        'styles': ['ハイキング', '自然'],
        'purposes': ['癒し', '家族旅行'],
        'level': '初級',
        'courseTime': '3時間00分',
        'time_car': '90',
        'time_public': '120',
        'time': '90分（車）/ 120分（公共交通機関）',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    print(
        '🚀🚀🚀 ResultPage.build() 開始 - hyakumeizanOnly: $hyakumeizanOnly, requiredTagFilters: ${requiredTagFilters ?? []}');
    return FutureBuilder<Weights>(
      future: WeightConfig.load(),
      builder: (context, snapshot) {
        final w = snapshot.data ?? Weights.defaults();
        final int bonusPreferTag = w.bonusPreferTag;
        final int bonusPreferPT = w.bonusPreferPT;
        final int bonusStyleStrong = w.bonusStyleStrong;
        final int bonusStyleSoft = w.bonusStyleSoft;

        bool wasRelaxed = false;

        // 候補プール：Firestore から取得（フォールバックあり）
        // この時点では天気未計算・未フィルタ
        // ignore: unused_local_variable
        final placeholder = <Map<String, dynamic>>[];

        Future<List<Map<String, dynamic>>> considerFuture() async {
          // Load travel config to tune cache key rounding at runtime
          try {
            final tc = await TravelConfig.load();
            DirectionsCache.defaultCoordDecimals = tc.directionsCoordDecimals;
          } catch (_) {}
          // Note: TTLはUIから渡されるcacheTtlHoursを使用
          final base = await _loadCandidateMountains();
          final List<String> unmatchedConditions = [];

          // 事前に「実ルートのアクセス時間」を可能な範囲で計算して候補データに埋め込む
          // - Google Directions が使えれば車/公共の分単位を計算
          // - 公共が難しい長距離は空路の推定（最寄り空港 + フライト + 現地空港→山の麓）
          // - APIキー未設定や失敗時はスキップ（既存のtime_car/time_publicで評価）

          // 軽いキャッシュで重複計算を避ける
          final Map<String, int?> cache = {};
          final ttl = Duration(hours: cacheTtlHours);
          Future<int?> cached(String key, Future<int?> Function() fn) async {
            // 1) メモリキャッシュ
            if (cache.containsKey(key)) return cache[key];
            // 2) ローカル永続キャッシュ（TTL）
            final local = await DirectionsCache.getWithTTL(key, ttl: ttl);
            if (local != null) {
              cache[key] = local;
              return local;
            }
            // 3) 外部API → 成功時にメモリ/ローカルへ保存
            final v = await fn();
            if (v != null) {
              cache[key] = v;
              await DirectionsCache.set(key, v);
            }
            return v;
          }

          Future<void> augmentAccessTimes() async {
            if (departureLat.isNaN || departureLng.isNaN) return;
            // 1リクエストあたりの外部API呼び出しを抑えるため上限設定
            // 山座標が無くても、trailheads に座標があれば対象とする
            List<Map<String, dynamic>> pickTargets(
                List<Map<String, dynamic>> list) {
              final out = <Map<String, dynamic>>[];
              for (final m in list) {
                final hasMountainCoord = (m['lat'] is num) && (m['lng'] is num);
                final ths = (m['trailheads'] is List)
                    ? (m['trailheads'] as List)
                    : const [];
                final hasAnyTrailheadCoord = ths.any(
                    (th) => th is Map && th['lat'] is num && th['lng'] is num);
                if (hasMountainCoord || hasAnyTrailheadCoord) out.add(m);
                if (out.length >= 30) break; // 上限
              }
              return out;
            }

            final targets = pickTargets(base);
            double deg2rad(double d) => d * 3.141592653589793 / 180.0;
            double haversineKm(
                double lat1, double lon1, double lat2, double lon2) {
              const R = 6371.0; // km
              final dLat = deg2rad(lat2 - lat1);
              final dLon = deg2rad(lon2 - lon1);
              final a = (sin(dLat / 2) * sin(dLat / 2)) +
                  cos(deg2rad(lat1)) *
                      cos(deg2rad(lat2)) *
                      (sin(dLon / 2) * sin(dLon / 2));
              final c = 2 * atan2(sqrt(a), sqrt(1 - a));
              return R * c;
            }

            // 出発地点から見て「主要な登山口」を選ぶ
            ({double lat, double lng, int? index, String? name})
                selectPrimaryTrailhead(Map<String, dynamic> m) {
              final ths = (m['trailheads'] is List)
                  ? (m['trailheads'] as List)
                  : const [];
              // 1) main/isMain/primary フラグがあればそれを優先
              for (int i = 0; i < ths.length; i++) {
                final th = ths[i];
                if (th is Map) {
                  final isMain = th['main'] == true ||
                      th['isMain'] == true ||
                      th['primary'] == true;
                  final tlat = th['lat'];
                  final tlng = th['lng'];
                  if (isMain && tlat is num && tlng is num) {
                    return (
                      lat: tlat.toDouble(),
                      lng: tlng.toDouble(),
                      index: i,
                      name: (th['name'] ?? '').toString()
                    );
                  }
                }
              }
              // 2) 出発地点に最も近い登山口
              double? bestDist;
              int? bestIdx;
              double? bestLat;
              double? bestLng;
              String? bestName;
              for (int i = 0; i < ths.length; i++) {
                final th = ths[i];
                if (th is Map) {
                  final tlat = th['lat'];
                  final tlng = th['lng'];
                  if (tlat is num && tlng is num) {
                    final d = haversineKm(departureLat, departureLng,
                        tlat.toDouble(), tlng.toDouble());
                    if (bestDist == null || d < bestDist) {
                      bestDist = d;
                      bestIdx = i;
                      bestLat = tlat.toDouble();
                      bestLng = tlng.toDouble();
                      bestName = (th['name'] ?? '').toString();
                    }
                  }
                }
              }
              if (bestLat != null && bestLng != null) {
                return (
                  lat: bestLat,
                  lng: bestLng,
                  index: bestIdx,
                  name: bestName
                );
              }
              // 3) 登山口情報が使えない場合は山の座標
              final mlat =
                  (m['lat'] is num) ? (m['lat'] as num).toDouble() : 0.0;
              final mlng =
                  (m['lng'] is num) ? (m['lng'] as num).toDouble() : 0.0;
              return (lat: mlat, lng: mlng, index: null, name: null);
            }

            for (final m in targets) {
              final sel = selectPrimaryTrailhead(m);
              final double lat = sel.lat;
              final double lng = sel.lng;
              int? carMin;
              int? pubMin;

              // 車（driving）
              carMin = await cached(
                  DirectionsCache.keyFromCoords(
                    mode: 'car',
                    originLat: departureLat,
                    originLng: departureLng,
                    destLat: lat,
                    destLng: lng,
                  ),
                  () => DirectionsService.drivingMinutes(
                      originLat: departureLat,
                      originLng: departureLng,
                      destLat: lat,
                      destLng: lng));

              // 公共交通（transit）
              pubMin = await cached(
                  DirectionsCache.keyFromCoords(
                    mode: 'pt',
                    originLat: departureLat,
                    originLng: departureLng,
                    destLat: lat,
                    destLng: lng,
                  ),
                  () => DirectionsService.transitMinutes(
                      originLat: departureLat,
                      originLng: departureLng,
                      destLat: lat,
                      destLng: lng));

              // 長距離で公共が取れない場合は空路推定
              if (pubMin == null) {
                try {
                  final depA = await AirportService.nearestAirportSmart(
                      departureLat, departureLng,
                      toleranceKm: 50);
                  final arrA = await AirportService.nearestAirportSmart(
                      lat, lng,
                      toleranceKm: 50);
                  if (depA != null && arrA != null) {
                    // 出発地→出発空港（公共優先→車）
                    final depToAirport = await cached(
                        DirectionsCache.keyFromCoords(
                          mode: 'ptdep',
                          originLat: departureLat,
                          originLng: departureLng,
                          destLat: depA.lat,
                          destLng: depA.lng,
                        ),
                        () => DirectionsService.transitMinutes(
                            originLat: departureLat,
                            originLng: departureLng,
                            destLat: depA.lat,
                            destLng: depA.lng));
                    final depToAirportCar = depToAirport ??
                        await cached(
                            DirectionsCache.keyFromCoords(
                              mode: 'cardep',
                              originLat: departureLat,
                              originLng: departureLng,
                              destLat: depA.lat,
                              destLng: depA.lng,
                            ),
                            () => DirectionsService.drivingMinutes(
                                originLat: departureLat,
                                originLng: departureLng,
                                destLat: depA.lat,
                                destLng: depA.lng));
                    // フライト本体（強化版推定: 距離・時間帯・週末係数など）
                    final when = plannedStartDate ?? DateTime.now();
                    final flight =
                        await FlightEstimator.estimateFlightMinutesEnhanced(
                      depA.lat,
                      depA.lng,
                      arrA.lat,
                      arrA.lng,
                      when: when,
                    );
                    // 到着空港→目的地（公共優先→車）
                    final arrToDest = await cached(
                        DirectionsCache.keyFromCoords(
                          mode: 'ptarr',
                          originLat: arrA.lat,
                          originLng: arrA.lng,
                          destLat: lat,
                          destLng: lng,
                        ),
                        () => DirectionsService.transitMinutes(
                            originLat: arrA.lat,
                            originLng: arrA.lng,
                            destLat: lat,
                            destLng: lng));
                    final arrToDestCar = arrToDest ??
                        await cached(
                            DirectionsCache.keyFromCoords(
                              mode: 'cararr',
                              originLat: arrA.lat,
                              originLng: arrA.lng,
                              destLat: lat,
                              destLng: lng,
                            ),
                            () => DirectionsService.drivingMinutes(
                                originLat: arrA.lat,
                                originLng: arrA.lng,
                                destLat: lat,
                                destLng: lng));

                    if (depToAirportCar != null && arrToDestCar != null) {
                      pubMin = depToAirportCar + flight + arrToDestCar;
                    }
                  }
                } catch (_) {}
              }

              if (carMin != null) m['computed_time_car'] = carMin;
              if (pubMin != null) m['computed_time_public'] = pubMin;
              // 目的地メタデータ（後でUIでの説明やデバッグ確認に役立つ）
              m['computed_dest_lat'] = lat;
              m['computed_dest_lng'] = lng;
              if (sel.index != null) {
                m['computed_trailhead_index'] = sel.index;
                if ((sel.name ?? '').isNotEmpty) {
                  m['computed_trailhead_name'] = sel.name;
                }
              }
              // 最終フォールバック（API不可/フォールバック無）：距離ベースの概算
              // ただし、300km以上の遠距離は概算の精度が低いため、フィルタで除外されるよう大きな値を設定
              if (carMin == null && pubMin == null) {
                final dist = haversineKm(departureLat, departureLng, lat, lng);
                if (dist >= 300) {
                  // 遠距離：フィルタで確実に除外されるよう大きな値（999分 = 16.6時間）
                  m['computed_time_car'] = 999;
                  m['computed_time_public'] = 999;
                } else {
                  // 近距離のみ概算を許可
                  final approxCar = (dist / 60.0 * 60.0).round(); // 60km/h 想定
                  final approxPT = (dist / 40.0 * 60.0).round(); // 40km/h 想定
                  if (approxCar > 0) m['computed_time_car'] = approxCar;
                  if (approxPT > 0) m['computed_time_public'] = approxPT;
                }
              }
              if (carMin != null || pubMin != null) {
                final parts = <String>[];
                if (carMin != null) parts.add('車$carMin分');
                if (pubMin != null) parts.add('公共$pubMin分');
                final thName = (m['computed_trailhead_name'] ?? '').toString();
                final suffix = thName.isNotEmpty ? '（目的地: $thName）' : '';
                m['computed_time_summary'] = parts.join(' / ') + suffix;
              }
            }
          }

          await augmentAccessTimes();

          print('📍 フィルタリング開始: 対象${base.length}件');
          print('   hyakumeizanOnly: $hyakumeizanOnly');
          print('   selectedLevel: $selectedLevel');
          print('   selectedAccessTime: $selectedAccessTime');
          print('   selectedCourseTime: $selectedCourseTime');

          // デバッグ: 全候補山の名前とタグをprint
          print('\n${"=" * 80}');
          print('🗻 全候補山リスト (${base.length}件):');
          print("=" * 80);
          int hyakuCount = 0;
          int nihyakuCount = 0;
          final List<String> hyakumeizanList = [];
          final List<String> nihyakumeizanList = [];
          for (var m in base) {
            final name = m['name'] ?? 'unknown';
            final tags = (m['tags'] is List) ? m['tags'] : [];
            final has = tags.contains('日本百名山');
            final has200 = tags.contains('日本二百名山');
            if (has) {
              hyakuCount++;
              hyakumeizanList.add(name);
            }
            if (has200) {
              nihyakuCount++;
              nihyakumeizanList.add(name);
            }
            print('  ${has ? "✅" : "❌"} $name - tags: $tags');
          }
          print("=" * 80);
          print('📊 日本百名山タグを持つ山: $hyakuCount/${base.length}件');
          print('   ${hyakumeizanList.join(", ")}');
          print('📊 日本二百名山タグを持つ山: $nihyakuCount/${base.length}件');
          if (nihyakumeizanList.isNotEmpty) {
            print('   ${nihyakumeizanList.join(", ")}');
          }
          print("=" * 80);
          print('');

          // デバッグ用: 除外された山のリスト
          final List<String> excludedMountains = [];

          // 必須条件に応じた前段フィルタ(厳密)
          final List<String> requiredTags = [
            ...?requiredTagFilters,
          ];

          // 日本百名山・日本二百名山フィルター（排他的）
          final List<Map<String, dynamic>> picked = base
              .map((m) {
                final prefs = priorityPrefs ?? const {};
                bool ok = true;
                final List<String> matchReasons = [];
                final String mountainName = (m['name'] ?? 'unknown').toString();

                if ((prefs['publicTransportOnly'] ?? 'none') == 'must') {
                  final acc = (m['access'] is List)
                      ? (m['access'] as List).map((e) => e.toString()).toList()
                      : <String>[];
                  if (!acc.contains('公共交通機関')) {
                    ok = false;
                    if (!unmatchedConditions.contains('公共交通機関')) {
                      unmatchedConditions.add('公共交通機関');
                    }
                  }
                }
                final tags = (m['tags'] is List)
                    ? (m['tags'] as List).map((e) => e.toString()).toList()
                    : <String>[];

                // 日本百名山フィルター
                if (hyakumeizanOnly && !tags.contains('日本百名山')) {
                  final reason = '$mountainName - 日本百名山フィルター不一致';
                  print('❌ 除外: $reason');
                  excludedMountains.add(reason);
                  ok = false;
                }

                // 日本二百名山フィルター
                if (nihyakumeizanOnly && !tags.contains('日本二百名山')) {
                  final reason = '$mountainName - 日本二百名山フィルター不一致';
                  print('❌ 除外: $reason');
                  excludedMountains.add(reason);
                  ok = false;
                }

                // タグ必須フィルタ（いずれかを含む）
                if (requiredTags.isNotEmpty &&
                    !requiredTags.any((t) => tags.contains(t))) {
                  final reason = '$mountainName - タグなし: $tags';
                  print('❌❌❌ 除外: $reason');
                  excludedMountains.add(reason);
                  ok = false;
                }

                // 日帰り検索の場合は、複数日程が前提のルート（縦走・泊を示唆）を除外
                // キーワードは強めに「縦走」「泊」「宿泊」「山小屋泊」「テント泊」を対象（「尾根」「主脈」は日帰りでもあり得るため除外）
                bool textContainsAny(String text, List<String> kws) =>
                    kws.any((k) => text.contains(k));
                final bool isDayTrip =
                    plannedStartDate != null && plannedEndDate == null;
                if (isDayTrip) {
                  final courseStr = (m['course'] ?? '').toString();
                  final descStr = (m['description'] ?? '').toString();
                  final combined = courseStr + descStr;
                  final isTraverse =
                      tags.contains('縦走') || textContainsAny(combined, ['縦走']);
                  final mentionsStay =
                      textContainsAny(combined, ['泊', '宿泊', '山小屋泊', 'テント泊']);
                  if (isTraverse || mentionsStay) {
                    ok = false;
                  }
                }
                if ((prefs['onsen'] ?? 'none') == 'must' &&
                    !tags.contains('温泉')) {
                  ok = false;
                  if (!unmatchedConditions.contains('温泉')) {
                    unmatchedConditions.add('温泉');
                  }
                }
                if ((prefs['mountainHut'] ?? 'none') == 'must' &&
                    !tags.contains('山小屋')) {
                  ok = false;
                  if (!unmatchedConditions.contains('山小屋')) {
                    unmatchedConditions.add('山小屋');
                  }
                }
                if ((prefs['tent'] ?? 'none') == 'must' &&
                    !tags.contains('テント泊')) {
                  ok = false;
                  if (!unmatchedConditions.contains('テント泊')) {
                    unmatchedConditions.add('テント泊');
                  }
                }
                if ((prefs['localFood'] ?? 'none') == 'must' &&
                    !tags.contains('郷土料理')) {
                  ok = false;
                  if (!unmatchedConditions.contains('郷土料理')) {
                    unmatchedConditions.add('郷土料理');
                  }
                }
                if ((prefs['ropeway'] ?? 'none') == 'must' &&
                    !tags.contains('ロープウェイ')) {
                  ok = false;
                  if (!unmatchedConditions.contains('ロープウェイ')) {
                    unmatchedConditions.add('ロープウェイ');
                  }
                }
                if ((prefs['cableCar'] ?? 'none') == 'must' &&
                    !tags.contains('ケーブルカー')) {
                  ok = false;
                  if (!unmatchedConditions.contains('ケーブルカー')) {
                    unmatchedConditions.add('ケーブルカー');
                  }
                }

                // === レベルフィルタ ===
                if (selectedLevel != null && selectedLevel!.isNotEmpty) {
                  final mountainLevel = (m['level'] ?? '').toString();
                  if (mountainLevel.isNotEmpty &&
                      mountainLevel != selectedLevel) {
                    ok = false;
                  } else if (mountainLevel.isNotEmpty &&
                      mountainLevel == selectedLevel) {
                    matchReasons.add('レベル: $mountainLevel');
                  }
                }

                // === コースタイムフィルタ（推奨条件：除外しない） ===
                if (selectedCourseTime != null &&
                    selectedCourseTime!.isNotEmpty) {
                  final courseTimeStr = (m['courseTime'] ?? '').toString();
                  if (courseTimeStr.isNotEmpty) {
                    // コースタイムを分に変換
                    final minutes = _parseTimeToMinutes(courseTimeStr);
                    final range = _getCourseTimeRange(selectedCourseTime!);
                    if (range != null && minutes > 0) {
                      if (minutes >= range['min']! &&
                          minutes <= range['max']!) {
                        matchReasons.add(
                            'コースタイム: $courseTimeStr（条件：$selectedCourseTime）');
                      }
                      // 条件外でも除外しない（推奨条件として扱う）
                    }
                  }
                }

                // === アクセス時間フィルタ（推奨条件：除外しない） ===
                if (selectedAccessTime != null &&
                    selectedAccessTime!.isNotEmpty) {
                  final computedCar = (m['computed_time_car'] is num)
                      ? (m['computed_time_car'] as num).toInt()
                      : null;
                  final computedPT = (m['computed_time_public'] is num)
                      ? (m['computed_time_public'] as num).toInt()
                      : null;

                  // 実ルートがない場合は静的値を使用（フォールバック）
                  final fallbackCar = m['time_car'] != null
                      ? int.tryParse(m['time_car'].toString())
                      : null;
                  final fallbackPT = m['time_public'] != null
                      ? int.tryParse(m['time_public'].toString())
                      : null;

                  final carTime = computedCar ?? fallbackCar ?? 0;
                  final publicTime = computedPT ?? fallbackPT ?? 0;

                  final range = _getAccessTimeRange(selectedAccessTime!);

                  if (range != null) {
                    final hasAcceptableTime = (carTime > 0 &&
                            carTime >= range['min']! &&
                            carTime <= range['max']!) ||
                        (publicTime > 0 &&
                            publicTime >= range['min']! &&
                            publicTime <= range['max']!);
                    if (hasAcceptableTime) {
                      final List<String> accessDetails = [];
                      if (carTime > 0 &&
                          carTime >= range['min']! &&
                          carTime <= range['max']!) {
                        final source = computedCar != null ? '実ルート' : '推定';
                        accessDetails.add('車$carTime分（$source）');
                      }
                      if (publicTime > 0 &&
                          publicTime >= range['min']! &&
                          publicTime <= range['max']!) {
                        final source = computedPT != null ? '実ルート' : '推定';
                        accessDetails.add('公共$publicTime分（$source）');
                      }
                      matchReasons.add(
                          'アクセス時間: ${accessDetails.join(' / ')}（条件：$selectedAccessTime）');
                    }
                    // 条件外でも除外しない（推奨条件として扱う）
                  }
                }

                // === スタイルフィルタ（部分一致）===
                if (selectedStyles != null && selectedStyles!.isNotEmpty) {
                  final mountainStyles = (m['styles'] is List)
                      ? (m['styles'] as List).map((e) => e.toString()).toList()
                      : <String>[];
                  if (mountainStyles.isNotEmpty) {
                    // 選択されたスタイルのいずれかが含まれていればOK
                    final matchingStyles = selectedStyles!
                        .where((style) => mountainStyles.contains(style))
                        .toList();
                    if (matchingStyles.isEmpty) {
                      ok = false;
                    } else {
                      matchReasons.add('スタイル: ${matchingStyles.join(', ')}');
                    }
                  }
                }

                // === 目的フィルタ（部分一致）===
                if (selectedPurposes != null && selectedPurposes!.isNotEmpty) {
                  final mountainPurposes = (m['purposes'] is List)
                      ? (m['purposes'] as List)
                          .map((e) => e.toString())
                          .toList()
                      : <String>[];
                  if (mountainPurposes.isNotEmpty) {
                    // 選択された目的のいずれかが含まれていればOK
                    final matchingPurposes = selectedPurposes!
                        .where((purpose) => mountainPurposes.contains(purpose))
                        .toList();
                    if (matchingPurposes.isEmpty) {
                      ok = false;
                    } else {
                      matchReasons.add('目的: ${matchingPurposes.join(', ')}');
                    }
                  }
                }

                // 理由を山のデータに追加
                if (ok) {
                  if (matchReasons.isNotEmpty) {
                    final copy = Map<String, dynamic>.from(m);
                    copy['_matchReasons'] = matchReasons;
                    return copy;
                  }
                  return m;
                }

                return null;
              })
              .whereType<Map<String, dynamic>>()
              .toList();

          print('✅ フィルタリング完了: ${picked.length}件が条件に一致');

          // 条件に完全一致する山がない場合はフォールバックを用意
          if (picked.isEmpty) {
            print('⚠️ 条件に一致する山がありません（picked = 0）');
            if (excludedMountains.isNotEmpty) {
              print('— 除外理由（最大10件）—');
              for (final r in excludedMountains.take(10)) {
                print('   ・$r');
              }
              if (excludedMountains.length > 10) {
                print('   …他 ${excludedMountains.length - 10} 件');
              }
            }

            // 指定タグを持つものだけを抽出してフォールバック（排他的モード対応）
            List<Map<String, dynamic>> matchedByTags;
            if (requiredTags.isNotEmpty) {
              matchedByTags = base.where((m) {
                final t = (m['tags'] is List)
                    ? (m['tags'] as List).map((e) => e.toString()).toList()
                    : <String>[];
                return requiredTags.any((rt) => t.contains(rt));
              }).toList();
            } else if (nihyakumeizanOnly) {
              // 二百のみ：二百タグのみ対象（百は除外）
              matchedByTags = base.where((m) {
                final t = (m['tags'] is List)
                    ? (m['tags'] as List).map((e) => e.toString()).toList()
                    : <String>[];
                return t.contains('日本二百名山') && !t.contains('日本百名山');
              }).toList();
            } else if (hyakumeizanOnly) {
              matchedByTags = base.where((m) {
                final t = (m['tags'] is List)
                    ? (m['tags'] as List).map((e) => e.toString()).toList()
                    : <String>[];
                return t.contains('日本百名山');
              }).toList();
            } else {
              matchedByTags = base.where((m) {
                final t = (m['tags'] is List)
                    ? (m['tags'] as List).map((e) => e.toString()).toList()
                    : <String>[];
                return t.contains('日本百名山');
              }).toList();
            }

            if (matchedByTags.isNotEmpty) {
              final tagLabel = nihyakumeizanOnly
                  ? '日本二百名山'
                  : hyakumeizanOnly
                      ? '日本百名山'
                      : 'タグ一致';
              print(
                  '↩︎ フォールバック: $tagLabel 指定 ${matchedByTags.length}件 → 上位3件を返却');
              wasRelaxed = true;
              return matchedByTags.take(3).toList();
            }

            // baseに一致がない場合、二百/百モードではFirestoreタグクエリでプール拡張
            if (nihyakumeizanOnly || hyakumeizanOnly) {
              try {
                final tag = nihyakumeizanOnly ? '日本二百名山' : '日本百名山';
                final fetched = await FirestoreService.listMountainsByTag(
                    tag: tag, limit: 300);
                print('↩︎ フォールバック: Firestoreタグ検索($tag)で${fetched.length}件取得');
                if (fetched.isNotEmpty) {
                  // 二百のみは百を除外
                  final filtered = nihyakumeizanOnly
                      ? fetched.where((m) {
                          final t = (m['tags'] is List)
                              ? (m['tags'] as List)
                                  .map((e) => e.toString())
                                  .toList()
                              : <String>[];
                          return t.contains('日本二百名山') && !t.contains('日本百名山');
                        }).toList()
                      : fetched;
                  if (filtered.isNotEmpty) {
                    wasRelaxed = true;
                    return filtered.take(3).toList();
                  }
                }
              } catch (e) {
                print('⚠️ タグ検索フォールバックでエラー: $e');
              }
            }

            if (unmatchedConditions.isNotEmpty) {
              print('↩︎ フォールバック: 類似候補（条件緩和） baseから3件');
              wasRelaxed = true;
              return base.take(3).toList();
            }

            print('↩︎ フォールバック: baseから3件');
            wasRelaxed = true;
            return base.take(3).toList();
          }

          return picked;
        }

        Future<Map<String, dynamic>> enrichFuture() async {
          final consider = await considerFuture();
          final out = <Map<String, dynamic>>[];
          for (final m in consider) {
            final copy = Map<String, dynamic>.from(m);
            // すでに Firestore ベースなので追加オーバーレイは不要
            double? lat =
                (m['lat'] is num) ? (m['lat'] as num).toDouble() : null;
            double? lng =
                (m['lng'] is num) ? (m['lng'] as num).toDouble() : null;
            // 実ルートの目的地（登山口）座標があれば優先
            if (m['computed_dest_lat'] is num &&
                m['computed_dest_lng'] is num) {
              lat = (m['computed_dest_lat'] as num).toDouble();
              lng = (m['computed_dest_lng'] as num).toDouble();
            }
            if (lat != null && lng != null) {
              Log.v(
                  '🌤️ [ResultPage] Fetching weather for ${copy['name']} at ($lat, $lng)');
              final daily =
                  await OpenMeteoService.fetchDaily(lat, lng, days: 7);
              Log.v(
                  '🌤️ [ResultPage] Received ${daily.length} days of weather data');
              final picked = OpenMeteoService.chooseBestOrDate(
                daily,
                target: plannedStartDate,
              );
              if (picked != null) {
                final pop = (picked['pop'] as num?) ?? 0;
                final weathercode = (picked['weathercode'] as int?) ?? 0;
                final windMs = (picked['wind_m_s'] as num?) ?? 0;
                final cloudPct = (picked['cloud_pct'] as num?) ?? 0;
                final tempC = (picked['temp_c'] as num?) ?? 0;

                Log.v(
                    '🌤️ [ResultPage] Weather for ${copy['name']}: POP=${(pop * 100).round()}%, code=$weathercode, wind=$windMs m/s, cloud=$cloudPct%, temp=$tempC°C');

                // 現在の表示用（当日または選択日の概要）
                copy['weathercode'] = weathercode; // フィルタ用に保存
                copy['weather'] =
                    OpenMeteoService.emojiFromWeatherCode(weathercode);
                // 参考用: 日別の降水確率（0-100）
                final int dailyPopPercent = (pop * 100).round().clamp(0, 100);
                copy['_pop_percent'] = dailyPopPercent;
                // 午前/午後の降水確率は「時間別」から算出（なければ日別を使用）
                try {
                  final DateTime? day = (picked['date'] is DateTime)
                      ? picked['date'] as DateTime
                      : null;
                  final hourly = await OpenMeteoService.fetchHourly(
                    lat,
                    lng,
                    hours: 24,
                    day: day,
                  );
                  if (hourly.isNotEmpty) {
                    int toPct(num? v) =>
                        (((v ?? 0) * 100).round()).clamp(0, 100);
                    bool inRange(DateTime t, int start, int endExclusive) =>
                        t.hour >= start && t.hour < endExclusive;
                    final am = hourly
                        .where((h) =>
                            h['time'] is DateTime &&
                            inRange(h['time'] as DateTime, 6, 12))
                        .map<num?>((h) => (h['pop'] as num?))
                        .whereType<num>()
                        .toList();
                    final pm = hourly
                        .where((h) =>
                            h['time'] is DateTime &&
                            inRange(h['time'] as DateTime, 12, 18))
                        .map<num?>((h) => (h['pop'] as num?))
                        .whereType<num>()
                        .toList();
                    final amPct = am.isNotEmpty
                        ? am
                            .map((e) => toPct(e))
                            .reduce((a, b) => a > b ? a : b)
                        : dailyPopPercent;
                    final pmPct = pm.isNotEmpty
                        ? pm
                            .map((e) => toPct(e))
                            .reduce((a, b) => a > b ? a : b)
                        : dailyPopPercent;
                    copy['rain_am'] = '$amPct%';
                    copy['rain_pm'] = '$pmPct%';
                    copy['_am_pop_pct'] = amPct;
                    copy['_pm_pop_pct'] = pmPct;
                  } else {
                    copy['rain_am'] = '$dailyPopPercent%';
                    copy['rain_pm'] = '$dailyPopPercent%';
                    copy['_am_pop_pct'] = dailyPopPercent;
                    copy['_pm_pop_pct'] = dailyPopPercent;
                  }
                } catch (_) {
                  copy['rain_am'] = '$dailyPopPercent%';
                  copy['rain_pm'] = '$dailyPopPercent%';
                  copy['_am_pop_pct'] = dailyPopPercent;
                  copy['_pm_pop_pct'] = dailyPopPercent;
                }
                copy['wind'] = '${windMs.toDouble().toStringAsFixed(1)}m/s';
                copy['cloud_pct'] = cloudPct.toDouble();
                copy['temp_c'] = tempC.toDouble();
              } else {
                Log.v(
                    '⚠️ [ResultPage] No weather data picked for ${copy['name']}');
              }
            } else {
              Log.v(
                  '⚠️ [ResultPage] Missing coordinates for ${copy['name']}: lat=$lat, lng=$lng');
            }
            // null 安全化（UI が必須とする項目）
            copy['course'] = (copy['course'] ?? '').toString();
            // 説明が空なら簡易デフォルト文を生成
            final descRaw = (copy['description'] ?? '').toString().trim();
            if (descRaw.isEmpty) {
              final name = (copy['name'] ?? '').toString();
              final pref = (copy['pref'] ?? '').toString();
              copy['description'] =
                  '$nameは$prefに位置する人気の山です。四季の自然や展望を楽しめるコースがあり、初心者から上級者まで楽しめます。';
            } else {
              copy['description'] = descRaw;
            }
            out.add(copy);
          }

          // 🔄 重複排除: 同じ名前+都道府県の山は1つだけ残す
          final seenMountains = <String>{};
          final uniqueMountains = <Map<String, dynamic>>[];
          for (final m in out) {
            final key = '${m['name']}_${m['pref']}';
            if (!seenMountains.contains(key)) {
              seenMountains.add(key);
              uniqueMountains.add(m);
            } else {
              Log.v('🔄 [Dedup] 重複を除外: ${m['name']} (${m['pref']})');
            }
          }

          Log.v('🔄 [Dedup] 重複排除: ${out.length}件 → ${uniqueMountains.length}件');

          // 🌤 「晴れ山SEARCH」コンセプト: 晴れor曇りの山のみを紹介
          // 天気コード < 40 (雨・雪を除外) かつ 降水確率 < 30%
          final sunnyOrCloudyMountains = uniqueMountains.where((m) {
            final weathercode = (m['weathercode'] as int?) ?? 999;
            final int popPercent = (m['_am_pop_pct'] as int?) ??
                (int.tryParse((m['rain_am'] ?? '0%')
                        .toString()
                        .replaceAll('%', '')) ??
                    0);

            final isSunnyOrCloudy = weathercode < 40; // 晴れ/ほぼ晴れ/一部曇り/曇り
            final isLowRain = popPercent < 30; // 降水確率30%未満

            if (!isSunnyOrCloudy || !isLowRain) {
              Log.v(
                  '❌ [Filter] ${m['name']}: code=$weathercode, pop=$popPercent% → 除外（雨・雪の予報）');
            }

            return isSunnyOrCloudy && isLowRain;
          }).toList();

          Log.v(
              '🌤️ [Filter] 晴れ/曇りフィルタ: ${out.length}件 → ${sunnyOrCloudyMountains.length}件');

          // 🔄 3件未満の場合は段階的に天気条件を緩和して最大3件に充足
          if (sunnyOrCloudyMountains.length < 3 && uniqueMountains.isNotEmpty) {
            debugPrint(
                '🔍 [Relax] 晴れ/曇り + 降水<30% で${sunnyOrCloudyMountains.length}件 → 条件を段階的に緩和');

            List<Map<String, dynamic>> stagePick(List<Map<String, dynamic>> src,
                {required int codeMax, required int popMax}) {
              return src.where((mm) {
                final wc = (mm['weathercode'] as int?) ?? 999;
                final pop = (mm['_am_pop_pct'] as int?) ??
                    (int.tryParse((mm['rain_am'] ?? '101%')
                            .toString()
                            .replaceAll('%', '')) ??
                        101);
                return wc < codeMax && pop < popMax;
              }).toList();
            }

            final relaxed = <Map<String, dynamic>>[];
            // Pass1: 現行条件（安全のため再評価）
            relaxed.addAll(sunnyOrCloudyMountains);
            // Pass2: 少し緩和（にわか雨許容） code<60, POP<60
            if (relaxed.length < 3) {
              final remain = 3 - relaxed.length;
              final p2 = stagePick(uniqueMountains, codeMax: 60, popMax: 60)
                  .where((m) => !relaxed.contains(m))
                  .toList();
              relaxed.addAll(p2.take(remain));
            }
            // Pass3: さらに緩和（POP昇順→code昇順）
            if (relaxed.length < 3) {
              final remain = 3 - relaxed.length;
              final rest =
                  uniqueMountains.where((m) => !relaxed.contains(m)).toList()
                    ..sort((a, b) {
                      int popA = (a['_am_pop_pct'] as int?) ??
                          (int.tryParse((a['rain_am'] ?? '101%')
                                  .toString()
                                  .replaceAll('%', '')) ??
                              101);
                      int popB = (b['_am_pop_pct'] as int?) ??
                          (int.tryParse((b['rain_am'] ?? '101%')
                                  .toString()
                                  .replaceAll('%', '')) ??
                              101);
                      if (popA != popB) return popA.compareTo(popB);
                      final ca = (a['weathercode'] as int?) ?? 999;
                      final cb = (b['weathercode'] as int?) ?? 999;
                      return ca.compareTo(cb);
                    });
              relaxed.addAll(rest.take(remain));
            }

            if (relaxed.isNotEmpty) {
              wasRelaxed = true;
              return {
                'items': relaxed.take(3).toList(),
                'wasRelaxed': wasRelaxed,
                'totalBeforeFilter': out.length,
                'isFallback': false,
              };
            }
          }

          // 🔄 該当がない場合は、他の条件で晴れの山を3件取得
          if (sunnyOrCloudyMountains.isEmpty && out.isNotEmpty) {
            debugPrint('🔍 [Fallback] 検索条件に該当する晴れの山がないため、代替候補を取得します...');

            // 全国の山から候補を取得（nihyakumeizanOnly/hyakumeizanOnly は専用クエリを優先）
            List<Map<String, dynamic>> allMountains = [];
            if (nihyakumeizanOnly) {
              allMountains = await FirestoreService.listMountainsByTag(
                  tag: '日本二百名山', limit: 300);
              debugPrint('🔍 [Fallback] 日本二百名山タグ限定で${allMountains.length}件を取得');
            } else if (hyakumeizanOnly) {
              allMountains = await FirestoreService.listMountainsByTag(
                  tag: '日本百名山', limit: 300);
              debugPrint('🔍 [Fallback] 日本百名山タグ限定で${allMountains.length}件を取得');
            } else {
              allMountains = await FirestoreService.listMountains(
                limit: 200,
              );
              debugPrint('🔍 [Fallback] 汎用取得で${allMountains.length}件を取得');
            }

            final fallbackCandidates = <Map<String, dynamic>>[];
            final seenFallback = <String>{}; // フォールバック候補の重複チェック
            final assessed = <Map<String, dynamic>>[]; // 天気評価済の候補（天気指標付き）
            for (final m in allMountains) {
              // 重複チェック
              final key = '${m['name']}_${m['pref']}';
              if (seenFallback.contains(key)) {
                debugPrint(
                    '🔄 [Fallback-Dedup] 重複をスキップ: ${m['name']} (${m['pref']})');
                continue;
              }

              // 日本百名山・日本二百名山フィルターを適用
              final tags = (m['tags'] is List)
                  ? (m['tags'] as List).map((e) => e.toString()).toList()
                  : <String>[];
              if (hyakumeizanOnly && !tags.contains('日本百名山')) {
                debugPrint('🔄 [Fallback] ${m['name']}: 日本百名山フィルター不一致 → スキップ');
                continue;
              }
              if (nihyakumeizanOnly && !tags.contains('日本二百名山')) {
                debugPrint('🔄 [Fallback] ${m['name']}: 日本二百名山フィルター不一致 → スキップ');
                continue;
              }
              // 「二百のみ」では百名山を除外（ユーザー要望に基づく排他仕様）
              if (nihyakumeizanOnly && tags.contains('日本百名山')) {
                debugPrint('🔄 [Fallback] ${m['name']}: 百名山は二百のみ選択時は除外 → スキップ');
                continue;
              }

              // 天気データを取得
              final lat =
                  (m['lat'] is num) ? (m['lat'] as num).toDouble() : null;
              final lng =
                  (m['lng'] is num) ? (m['lng'] as num).toDouble() : null;

              if (lat != null && lng != null) {
                try {
                  final daily =
                      await OpenMeteoService.fetchDaily(lat, lng, days: 7);
                  if (daily.isNotEmpty) {
                    final picked = OpenMeteoService.chooseBestOrDate(
                      daily,
                      target: plannedStartDate,
                    );

                    if (picked != null) {
                      final weathercode =
                          (picked['weathercode'] as int?) ?? 999;
                      final pop = (picked['pop'] as num?) ?? 0;
                      final popPercent = (pop * 100).round();
                      // 一旦すべて天気指標付きで評価リストに追加（後段で段階選抜）
                      final copy = Map<String, dynamic>.from(m);
                      copy['weathercode'] = weathercode;
                      copy['weather'] =
                          OpenMeteoService.emojiFromWeatherCode(weathercode);
                      // フォールバックでも可能な限り時間別からAM/PMを算出
                      try {
                        final DateTime? day = (picked['date'] is DateTime)
                            ? picked['date'] as DateTime
                            : null;
                        final hourly = await OpenMeteoService.fetchHourly(
                          lat,
                          lng,
                          hours: 24,
                          day: day,
                        );
                        int toPct(num? v) =>
                            (((v ?? 0) * 100).round()).clamp(0, 100);
                        bool inRange(DateTime t, int s, int e) =>
                            t.hour >= s && t.hour < e;
                        if (hourly.isNotEmpty) {
                          final am = hourly
                              .where((h) =>
                                  h['time'] is DateTime &&
                                  inRange(h['time'] as DateTime, 6, 12))
                              .map<num?>((h) => (h['pop'] as num?))
                              .whereType<num>()
                              .toList();
                          final pm = hourly
                              .where((h) =>
                                  h['time'] is DateTime &&
                                  inRange(h['time'] as DateTime, 12, 18))
                              .map<num?>((h) => (h['pop'] as num?))
                              .whereType<num>()
                              .toList();
                          final amPct = am.isNotEmpty
                              ? am
                                  .map((e) => toPct(e))
                                  .reduce((a, b) => a > b ? a : b)
                              : popPercent;
                          final pmPct = pm.isNotEmpty
                              ? pm
                                  .map((e) => toPct(e))
                                  .reduce((a, b) => a > b ? a : b)
                              : popPercent;
                          copy['rain_am'] = '$amPct%';
                          copy['rain_pm'] = '$pmPct%';
                          copy['_am_pop_pct'] = amPct;
                          copy['_pm_pop_pct'] = pmPct;
                        } else {
                          copy['rain_am'] = '$popPercent%';
                          copy['rain_pm'] = '$popPercent%';
                          copy['_am_pop_pct'] = popPercent;
                          copy['_pm_pop_pct'] = popPercent;
                        }
                      } catch (_) {
                        copy['rain_am'] = '$popPercent%';
                        copy['rain_pm'] = '$popPercent%';
                        copy['_am_pop_pct'] = popPercent;
                        copy['_pm_pop_pct'] = popPercent;
                      }
                      copy['wind'] =
                          '${(picked['wind_m_s'] as num?)?.toDouble().toStringAsFixed(1) ?? "0.0"}m/s';
                      copy['cloud_pct'] =
                          (picked['cloud_pct'] as num?)?.toDouble() ?? 0.0;
                      copy['temp_c'] =
                          (picked['temp_c'] as num?)?.toDouble() ?? 15.0;
                      copy['_popPercent'] = popPercent;
                      copy['_weathercode'] = weathercode;

                      seenFallback.add(key); // 重複防止
                      assessed.add(copy);
                    }
                  }
                } catch (e) {
                  debugPrint('⚠️ [Fallback] ${m['name']}の天気取得エラー: $e');
                }
              }
            }

            // 段階的に選抜
            List<Map<String, dynamic>> stagePick(List<Map<String, dynamic>> src,
                {required int codeMax, required int popMax}) {
              return src
                  .where((mm) =>
                      (mm['_weathercode'] as int? ?? 999) < codeMax &&
                      (mm['_popPercent'] as int? ?? 101) < popMax)
                  .toList();
            }

            // Pass1: 晴れ/曇り・降水30%未満
            final pass1 = stagePick(assessed, codeMax: 40, popMax: 30);
            fallbackCandidates.addAll(pass1.take(3));

            // Pass2: 少し緩和（にわか雨程度を許容）code<60, POP<60
            if (fallbackCandidates.length < 3) {
              final remain = 3 - fallbackCandidates.length;
              final pass2 = stagePick(assessed, codeMax: 60, popMax: 60)
                  .where((m) => !fallbackCandidates.contains(m))
                  .toList();
              fallbackCandidates.addAll(pass2.take(remain));
            }

            // Pass3: さらに緩和（天気に関わらずPOP昇順→code昇順で充足）
            if (fallbackCandidates.length < 3 && assessed.isNotEmpty) {
              final remain = 3 - fallbackCandidates.length;
              final rest = assessed
                  .where((m) => !fallbackCandidates.contains(m))
                  .toList()
                ..sort((a, b) {
                  final pa = (a['_popPercent'] as int? ?? 101);
                  final pb = (b['_popPercent'] as int? ?? 101);
                  if (pa != pb) return pa.compareTo(pb);
                  final ca = (a['_weathercode'] as int? ?? 999);
                  final cb = (b['_weathercode'] as int? ?? 999);
                  return ca.compareTo(cb);
                });
              fallbackCandidates.addAll(rest.take(remain));
            }

            debugPrint('🔍 [Fallback] 代替候補: ${fallbackCandidates.length}件取得');

            return {
              'items': fallbackCandidates,
              'wasRelaxed': wasRelaxed,
              'totalBeforeFilter': out.length,
              'isFallback': true, // フォールバックフラグ
            };
          }

          return {
            'items': sunnyOrCloudyMountains,
            'wasRelaxed': wasRelaxed,
            'totalBeforeFilter': out.length,
            'isFallback': false,
          };
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: enrichFuture(),
          builder: (context, snap2) {
            final data = snap2.data ??
                const {
                  'items': <Map<String, dynamic>>[],
                  'wasRelaxed': false,
                  'isFallback': false
                };
            final enriched =
                (data['items'] as List).cast<Map<String, dynamic>>();
            wasRelaxed = (data['wasRelaxed'] as bool?) ?? false;
            final isFallback = (data['isFallback'] as bool?) ?? false;
            final bool isLoadingWeather =
                snap2.connectionState == ConnectionState.waiting;
            final bool weatherFailed = snap2.hasError;
            final scoredMountains = enriched.map((m) {
              final f = _toForecast(m);
              final scoreRes = WeatherScore.scoreDay(f);
              int bonus = 0;
              final List<String> bonusLabels = [];
              final prefs = priorityPrefs ?? const {};
              final tags = (m['tags'] is List)
                  ? (m['tags'] as List).map((e) => e.toString()).toList()
                  : <String>[];
              final acc = (m['access'] is List)
                  ? (m['access'] as List).map((e) => e.toString()).toList()
                  : <String>[];
              final course = (m['course'] ?? '').toString();
              final desc = (m['description'] ?? '').toString();

              if ((prefs['onsen'] ?? 'none') == 'prefer' &&
                  tags.contains('温泉')) {
                bonus += bonusPreferTag;
                bonusLabels.add('温泉 +$bonusPreferTag');
              }
              if ((prefs['mountainHut'] ?? 'none') == 'prefer' &&
                  tags.contains('山小屋')) {
                bonus += bonusPreferTag;
                bonusLabels.add('山小屋 +$bonusPreferTag');
              }
              if ((prefs['tent'] ?? 'none') == 'prefer' &&
                  tags.contains('テント泊')) {
                bonus += bonusPreferTag;
                bonusLabels.add('テント泊 +$bonusPreferTag');
              }
              if ((prefs['localFood'] ?? 'none') == 'prefer' &&
                  tags.contains('郷土料理')) {
                bonus += bonusPreferTag;
                bonusLabels.add('郷土料理 +$bonusPreferTag');
              }
              if ((prefs['publicTransportOnly'] ?? 'none') == 'prefer' &&
                  acc.contains('公共交通機関')) {
                bonus += bonusPreferPT;
                bonusLabels.add('公共交通 +$bonusPreferPT');
              }
              if ((prefs['ropeway'] ?? 'none') == 'prefer' &&
                  tags.contains('ロープウェイ')) {
                bonus += bonusPreferTag;
                bonusLabels.add('ロープウェイ +$bonusPreferTag');
              }
              if ((prefs['cableCar'] ?? 'none') == 'prefer' &&
                  tags.contains('ケーブルカー')) {
                bonus += bonusPreferTag;
                bonusLabels.add('ケーブルカー +$bonusPreferTag');
              }

              bool containsAny(String text, List<String> kws) =>
                  kws.any((k) => text.contains(k));
              bool tagsAny(List<String> kws) =>
                  kws.any((k) => tags.contains(k));

              final selStyles = selectedStyles ?? const [];
              if (selStyles.contains('稜線')) {
                if (tags.contains('縦走') ||
                    containsAny(course + desc, ['縦走', '主脈', '尾根'])) {
                  bonus += bonusStyleStrong;
                  bonusLabels.add('スタイル:稜線 +$bonusStyleStrong');
                }
              }
              if (selStyles.contains('岩場')) {
                if (tagsAny(['岩場']) || containsAny(desc, ['岩', 'ゴツゴツ'])) {
                  bonus += bonusStyleStrong;
                  bonusLabels.add('スタイル:岩場 +$bonusStyleStrong');
                }
              }
              if (selStyles.contains('鎖場')) {
                if (tagsAny(['鎖場']) || containsAny(desc, ['鎖'])) {
                  bonus += bonusStyleStrong;
                  bonusLabels.add('スタイル:鎖場 +$bonusStyleStrong');
                }
              }
              if (selStyles.contains('自然')) {
                if (containsAny(
                    desc, ['自然', '森', '森林', '林', '湿原', '花', '高山植物'])) {
                  bonus += bonusStyleSoft;
                  bonusLabels.add('スタイル:自然 +$bonusStyleSoft');
                }
              }
              if (selStyles.contains('絶景')) {
                if (containsAny(desc, ['絶景', '展望', '眺め', '一望', '富士山'])) {
                  bonus += bonusStyleSoft;
                  bonusLabels.add('スタイル:絶景 +$bonusStyleSoft');
                }
              }

              final selPurposes = selectedPurposes ?? const [];
              if (selPurposes.contains('冒険')) {
                if (tagsAny(['岩場', '鎖場', '縦走']) ||
                    containsAny(desc, ['岩', '鎖'])) {
                  bonus += bonusStyleStrong;
                  bonusLabels.add('目的:冒険 +$bonusStyleStrong');
                }
              }
              if (selPurposes.contains('癒し')) {
                if (tagsAny(['温泉']) || containsAny(desc, ['森', '静か'])) {
                  bonus += bonusStyleSoft;
                  bonusLabels.add('目的:癒し +$bonusStyleSoft');
                }
              }
              if (selPurposes.contains('リフレッシュ')) {
                if (acc.contains('公共交通機関')) {
                  bonus += bonusStyleSoft;
                  bonusLabels.add('目的:リフレッシュ +$bonusStyleSoft');
                }
              }

              final copy = Map<String, dynamic>.from(m);
              final base = (scoreRes['score'] as int);
              copy['_scoreRes'] = {
                ...scoreRes,
                'augScore': (base + bonus).clamp(0, 120),
                'bonus': bonus,
                'bonusLabels': bonusLabels,
              };
              return copy;
            }).toList();

            if (scoredMountains.isNotEmpty) {
              scoredMountains.sort((a, b) {
                final sa = ((a['_scoreRes'] as Map)['augScore'] as int?) ??
                    ((a['_scoreRes'] as Map)['score'] as int);
                final sb = ((b['_scoreRes'] as Map)['augScore'] as int?) ??
                    ((b['_scoreRes'] as Map)['score'] as int);
                return sb.compareTo(sa);
              });
              // 無料プラン: 上位3件に絞り込み（表示側でもcapしているが、ここでも明示）
              if (scoredMountains.length > 3) {
                scoredMountains.removeRange(3, scoredMountains.length);
              }
            }

            print('\n${"=" * 80}');
            Log.v('📊 最終結果: ${scoredMountains.length}件');
            print("=" * 80);

            final topCardKey = GlobalKey();
            final expandSignal = ValueNotifier<int>(0);

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
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 150),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ステータス表示: 結果構築中のみ表示
                            if (snap2.connectionState ==
                                ConnectionState.waiting)
                              _LoadingIndicator(),
                            SizedBox(height: 16),
                            Align(
                              alignment: Alignment.topLeft,
                              child: InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(24),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF2E7D32),
                                        Color(0xFF7CB342),
                                        Color(0xFF104E41)
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                          color: const Color(0xFF104E41)
                                              .withValues(alpha: 0.25),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4)),
                                    ],
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.arrow_back_ios,
                                          color: Colors.white, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        '検索条件を変更する',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                                height: MediaQuery.of(context).size.width < 360
                                    ? 6
                                    : 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SimpleSunIcon(size: 28),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '晴れ山 SEARCH',
                                    style: TextStyle(
                                      fontSize: _titleFontSize(context),
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                                height: MediaQuery.of(context).size.width < 360
                                    ? 14
                                    : 20),
                            if (isLoadingWeather) _buildWeatherLoadingBanner(),
                            if (!isLoadingWeather && weatherFailed)
                              _buildWeatherErrorBanner(),
                            // 上部の「おすすめ」バナーは wasRelaxed=true の時のみ表示
                            if (wasRelaxed) _buildAIComment(true),
                            const SizedBox(height: 24),
                            if (wasRelaxed)
                              Container(
                                key: const ValueKey('relax-note'),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          Colors.orange.withValues(alpha: 0.5)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: Colors.orange),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '※検索条件にマッチする山が見つからない場合には、条件を緩やかにしてご紹介しております。',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            if (wasRelaxed) const SizedBox(height: 12),
                            // 🔄 フォールバック時の説明バナー
                            if (isFallback && scoredMountains.isNotEmpty)
                              Container(
                                key: const ValueKey('fallback-note'),
                                padding: const EdgeInsets.all(14),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue.withValues(alpha: 0.15),
                                      Colors.blue.withValues(alpha: 0.08),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          Colors.blue.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.wb_sunny,
                                        color: Colors.orange, size: 28),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'あなたのご希望に沿う山を探していますが、条件に合う山が出てこないときには、幅広くゆるい条件で山をご紹介します',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              height: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // 🌤 晴れ・曇りの山が見つからなかった場合のポップアップは削除
                            // 旧: フィルタ結果（青）ボタンは非表示に変更
                            // Rank labels for top 3 cards + ページング（表示件数でスライス）
                            ValueListenableBuilder<int>(
                              valueListenable: _displayCount,
                              builder: (context, count, _) {
                                // 無料プラン: 上位3件のみ表示
                                const int cap = 3;
                                final int safeCount = count > cap ? cap : count;
                                final visible =
                                    scoredMountains.take(safeCount).toList();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ...visible.asMap().entries.map((entry) {
                                      final idx = entry.key;
                                      final item = entry.value;
                                      final label = idx == 0
                                          ? '第一候補'
                                          : idx == 1
                                              ? '第二候補'
                                              : idx == 2
                                                  ? '第三候補'
                                                  : '候補';
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (idx < 3) ...[
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                label,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                          _MountainCard(
                                            key: idx == 0 ? topCardKey : null,
                                            item: item,
                                            departureLabel: departureLabel,
                                            departureLat: departureLat,
                                            departureLng: departureLng,
                                            selectedAccessMethods:
                                                selectedAccessMethods ??
                                                    const [],
                                            selectedOptions: selectedOptions,
                                            plannedDate: plannedStartDate,
                                            selectedCourseTime:
                                                selectedCourseTime,
                                            expandSignal:
                                                idx == 0 ? expandSignal : null,
                                          ),
                                        ],
                                      );
                                    }),
                                    // 無料プランでは「もっと見る」は表示しない
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 120),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildFooterButton(context),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWeatherLoadingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F4F4),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF00939C).withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '天気データを読み込み中… 少々お待ちください',
              style: TextStyle(color: Colors.black87),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildWeatherErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFF57C00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '天気データの取得に失敗しました。通信状況をご確認のうえ、時間をおいて再度お試しください。',
              style: TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // 上部おすすめバナーは仕様変更により廃止

  Widget _buildAIComment(bool wasRelaxed) {
    final level = (selectedLevel != null && selectedLevel!.isNotEmpty)
        ? selectedLevel!
        : 'レベル未指定';
    final access =
        (selectedAccessMethods != null && selectedAccessMethods!.isNotEmpty)
            ? selectedAccessMethods!.join('・')
            : '交通手段未指定';
    final purpose = (selectedPurposes != null && selectedPurposes!.isNotEmpty)
        ? selectedPurposes!.join('・')
        : 'リフレッシュ';

    String datePart = '登山日：未指定';
    if (plannedStartDate != null && plannedEndDate != null) {
      datePart =
          '登山日：${DateTime(plannedStartDate!.year, plannedStartDate!.month, plannedStartDate!.day).toIso8601String().split('T')[0]} ～ ${DateTime(plannedEndDate!.year, plannedEndDate!.month, plannedEndDate!.day).toIso8601String().split('T')[0]}';
    } else if (plannedStartDate != null) {
      datePart =
          '登山日：${DateTime(plannedStartDate!.year, plannedStartDate!.month, plannedStartDate!.day).toIso8601String().split('T')[0]}';
    }

    final String message;
    if (wasRelaxed) {
      // 条件不一致時のメッセージ
      final prefs = priorityPrefs ?? const {};
      final List<String> unmatchedList = [];
      if ((prefs['publicTransportOnly'] ?? 'none') == 'must') {
        unmatchedList.add('公共交通機関');
      }
      if ((prefs['onsen'] ?? 'none') == 'must') unmatchedList.add('温泉');
      if ((prefs['mountainHut'] ?? 'none') == 'must') unmatchedList.add('山小屋');
      if ((prefs['tent'] ?? 'none') == 'must') unmatchedList.add('テント泊');
      if ((prefs['localFood'] ?? 'none') == 'must') unmatchedList.add('郷土料理');
      if ((prefs['ropeway'] ?? 'none') == 'must') unmatchedList.add('ロープウェイ');
      if ((prefs['cableCar'] ?? 'none') == 'must') unmatchedList.add('ケーブルカー');

      final unmatchedText = unmatchedList.isNotEmpty
          ? '【${unmatchedList.join('、')}】の条件に完全一致する山が見つかりませんでした。'
          : '指定された条件に完全一致する山が見つかりませんでした。';

      message = '⚠️ $unmatchedText\n\n'
          '代わりに、$departureLabel から「$level」向けで類似条件の山を3つご提案します。\n'
          '$datePart\n'
          '「$purpose」気分の日にお楽しみいただけるコースです。\n\n'
          '💡 条件を緩和することで、より多くの候補をご提案できます。';
    } else {
      // 通常メッセージ
      message =
          '🚩 出発地：$departureLabel から、$access でアクセスしやすい「$level」向けの山を選びました。\n'
          '$datePart\n'
          '今回は「$purpose」気分の日にぴったりのコースをご紹介します。\n\n'
          '🗓 スケジュール（天気）に合わせて、AIがあなたと一緒に最適なプランを考えていきます🌿☀️\n'
          '（無料プランのため、候補は最大3件まで表示されます）';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: wasRelaxed
            ? const Color(0xFFFFF3E0).withValues(alpha: 0.95)
            : _card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: wasRelaxed
            ? Border.all(color: const Color(0xFFFFB74D), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 16,
          color: wasRelaxed ? const Color(0xFF6D4C41) : Colors.black87,
          height: 1.7,
          fontWeight: wasRelaxed ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildFooterButton(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF7CB342), Color(0xFF104E41)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
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
                  '検索条件に戻る',
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
}

class _MountainCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final String departureLabel;
  final ValueNotifier<int>? expandSignal;
  final List<String> selectedAccessMethods;
  final List<String>? selectedOptions;
  final DateTime? plannedDate;
  final double departureLat;
  final double departureLng;
  final String? selectedCourseTime;

  const _MountainCard({
    super.key,
    required this.item,
    required this.departureLabel,
    required this.departureLat,
    required this.departureLng,
    required this.selectedAccessMethods,
    this.selectedOptions,
    this.expandSignal,
    this.plannedDate,
    this.selectedCourseTime,
  });

  @override
  State<_MountainCard> createState() => _MountainCardState();
}

class _MountainCardState extends State<_MountainCard> {
  bool _expanded = false;
  bool _ctaHover = false;
  bool _ctaPressed = false;

  String _localizeMetric(String input) {
    var text = input;
    final replacements = <RegExp, String>{
      RegExp(r'Temp', caseSensitive: false): '気温',
      RegExp(r'Wind', caseSensitive: false): '風',
      RegExp(r'Cloud\s*cover', caseSensitive: false): '雲量',
      RegExp(r'Cloud', caseSensitive: false): '雲量',
      RegExp(r'Precip', caseSensitive: false): '降水量',
      RegExp(r'POP', caseSensitive: false): '降水確率',
      RegExp(r'Humidity', caseSensitive: false): '湿度',
      RegExp(r'UV', caseSensitive: false): '紫外線',
      RegExp(r'Morning', caseSensitive: false): '午前',
      RegExp(r'Afternoon', caseSensitive: false): '午後',
      RegExp(r'Score', caseSensitive: false): 'スコア',
    };
    replacements.forEach((pattern, jp) {
      text = text.replaceAll(pattern, jp);
    });
    return text;
  }

  @override
  void initState() {
    super.initState();
    widget.expandSignal?.addListener(_onExpandSignal);
  }

  @override
  void didUpdateWidget(covariant _MountainCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandSignal != widget.expandSignal) {
      oldWidget.expandSignal?.removeListener(_onExpandSignal);
      widget.expandSignal?.addListener(_onExpandSignal);
    }
  }

  @override
  void dispose() {
    widget.expandSignal?.removeListener(_onExpandSignal);
    super.dispose();
  }

  void _onExpandSignal() {
    if (mounted) setState(() => _expanded = true);
  }

  Widget _weatherVisual(int weatherCode, String emoji) {
    // 晴天/ほぼ快晴 → オレンジ色の太陽
    if (weatherCode == 0 || weatherCode == 1) {
      return const SimpleSunIcon(size: 36);
    }
    // 一部曇り・曇りは雲アイコン
    if (weatherCode == 2) {
      return const Icon(Icons.wb_cloudy, color: Color(0xFF90A4AE), size: 40);
    }
    if (weatherCode == 3) {
      return const Icon(Icons.cloud, color: Color(0xFF90A4AE), size: 40);
    }
    // 雨や雪などは絵文字をそのまま表示（視認性重視）
    return Text(emoji, style: const TextStyle(fontSize: 44));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    // デバッグ: 山の情報を出力（verbose時のみ）
    Log.v('🏔️ Mountain Card Debug: ${item['name']}');
    Log.v('  name_kana: "${item['name_kana']}"');
    Log.v('  pref: "${item['pref']}"');
    Log.v('  course: "${item['course']}"');
    Log.v('  description: "${item['description']}"');
    Log.v('  courseTime: "${item['courseTime']}"');
    Log.v('  time_car: "${item['time_car']}"');
    Log.v('  time_public: "${item['time_public']}"');
    Log.v('  time: "${item['time']}"');
    Log.v('  access: ${item['access']}');
    Log.v('  Full item keys: ${item.keys.toList()}');

    final Map<String, dynamic> scoreRes = (item['_scoreRes'] is Map)
        ? Map<String, dynamic>.from(item['_scoreRes'] as Map)
        : WeatherScore.scoreDay({});
    final int score = (scoreRes['augScore'] is int)
        ? (scoreRes['augScore'] as int)
        : ((scoreRes['score'] as int?) ?? 0);
    final String reason = (scoreRes['reason'] as String?) ?? '';
    final int bonus =
        (scoreRes['bonus'] is int) ? (scoreRes['bonus'] as int) : 0;
    final Map breakdown = (scoreRes['breakdown'] is Map)
        ? (scoreRes['breakdown'] as Map)
        : const {};

    Color badgeColor;
    if (score >= 75) {
      badgeColor = const Color(0xFF2E7D32);
    } else if (score >= 50) {
      badgeColor = const Color(0xFFF9A825);
    } else {
      badgeColor = const Color(0xFFD32F2F);
    }

    return Container(
      key: ValueKey('mountain-card-${item['name']}'),
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: ResultPage._card.withValues(alpha: 0.97),
        border: Border.all(
            color: ResultPage._teal.withValues(alpha: 0.18), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ふりがな（小さく表示）
              if ((item['name_kana'] ?? '').toString().isNotEmpty)
                Text(
                  (item['name_kana'] ?? '').toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF267365),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              // 山名
              Text(
                () {
                  final name = (item['name'] ?? '').toString();
                  final pref = (item['pref'] ?? '').toString();
                  final prefClean = pref.trim();
                  final showPref = prefClean.isNotEmpty &&
                      prefClean.toLowerCase() != 'null' &&
                      prefClean.toUpperCase() != 'NULL';
                  return showPref ? "$name（$prefClean）" : name;
                }(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF267365),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              // 名称下にタグバッジ（日本百名山 / 日本二百名山）
              Builder(builder: (context) {
                final List tags =
                    (item['tags'] is List) ? (item['tags'] as List) : const [];
                final bool is100 = tags.contains('日本百名山');
                final bool is200 = tags.contains('日本二百名山');
                if (!is100 && !is200) return const SizedBox.shrink();
                List<Widget> chips = [];
                if (is100) {
                  chips.add(Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF116A5B),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1976D2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('日本二百名山',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ));
                }
                return Wrap(spacing: 6, runSpacing: 4, children: chips);
              }),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (item['course'] ?? '').toString(),
            style: const TextStyle(
                color: Color(0xFF267365),
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            (item['description'] ?? '').toString(),
            style: const TextStyle(
                fontSize: 15, height: 1.7, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _weatherVisual(
              (item['weathercode'] as int?) ?? 999,
              (item['weather']?.toString() ?? ''),
            ),
            const SizedBox(width: 12),
            Builder(builder: (context) {
              final num? tnum =
                  (item['temp_c'] is num) ? item['temp_c'] as num : null;
              final String tempStr =
                  tnum != null ? '${tnum.toStringAsFixed(0)}°C' : '';
              String amPct = (item['_am_pop_pct'] is int)
                  ? '${item['_am_pop_pct']}%'
                  : (item['rain_am']?.toString() ?? '—');
              String pmPct = (item['_pm_pop_pct'] is int)
                  ? '${item['_pm_pop_pct']}%'
                  : (item['rain_pm']?.toString() ?? '—');
              // 念のため%が無い場合は付与
              if (amPct != '—' && !amPct.trim().endsWith('%'))
                amPct = '$amPct%';
              if (pmPct != '—' && !pmPct.trim().endsWith('%'))
                pmPct = '$pmPct%';
              const smallStyle = TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500);
              const lineStyle =
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      const TextSpan(
                          text: '午前: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: amPct, style: lineStyle),
                      const TextSpan(text: ' '),
                      const TextSpan(
                          text: '（降水確率）',
                          style:
                              TextStyle(fontSize: 12, color: Colors.black54)),
                      if (tempStr.isNotEmpty)
                        TextSpan(text: ' ・ 気温: $tempStr', style: smallStyle),
                    ])),
                    const SizedBox(height: 2),
                    Text.rich(TextSpan(children: [
                      const TextSpan(
                          text: '午後: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: pmPct, style: lineStyle),
                      const TextSpan(text: ' '),
                      const TextSpan(
                          text: '（降水確率）',
                          style:
                              TextStyle(fontSize: 12, color: Colors.black54)),
                      if (tempStr.isNotEmpty)
                        TextSpan(text: ' ・ 気温: $tempStr', style: smallStyle),
                    ])),
                    const SizedBox(height: 2),
                    Text("風速: ${(item['wind']?.toString() ?? '—')}",
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black87)),
                  ]);
            })
          ]),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      constraints: const BoxConstraints(minWidth: 44),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: badgeColor.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Text(
                        '$score',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize:
                              MediaQuery.of(context).size.width < 360 ? 16 : 18,
                        ),
                      ),
                    ),
                    if (bonus > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: ResultPage._teal,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text('+$bonus',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _localizeMetric(reason),
                        style: const TextStyle(color: Colors.black87),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          // 折りたたみ時にも簡易の一致理由を1行表示
          if ((item['_matchReasons'] is List) &&
              (item['_matchReasons'] as List).isNotEmpty) ...[
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final List r = (item['_matchReasons'] as List);
              final summary = r.take(2).map((e) => e.toString()).join(' / ');
              return Text('一致: $summary',
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black87));
            }),
          ],
          if (score >= 85) ...[
            const SizedBox(height: 6),
            const Text(
              '今日は絶好の山日和！展望や稜線歩きが楽しめそうです。',
              style: TextStyle(
                  color: Color(0xFF2E7D32), fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 16),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('理由を見る',
                    style: TextStyle(
                        color: Color(0xFF267365),
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF267365)),
              ],
            ),
          ),
          AnimatedCrossFade(
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 180),
            firstChild: Padding(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).size.width < 360 ? 8 : 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // === 選定理由（検索条件との一致） ===
                    if (item['_matchReasons'] != null &&
                        (item['_matchReasons'] as List).isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF4CAF50)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle_outline,
                                    color: Color(0xFF2E7D32), size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'この山が候補に選ばれた理由',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E7D32),
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...(item['_matchReasons'] as List)
                                .map((reason) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('✓ ',
                                              style: TextStyle(
                                                  color: Color(0xFF4CAF50),
                                                  fontWeight: FontWeight.bold)),
                                          Expanded(
                                            child: Text(
                                              reason.toString(),
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.black87),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Text('最終スコア: $score',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        Text('加点合計: +$bonus',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Builder(
                      builder: (context) {
                        final int base = (scoreRes['score'] is int)
                            ? (scoreRes['score'] as int)
                            : score;
                        return Text('（ベース $base + 加点 $bonus）');
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text('天気スコア内訳',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...breakdown.entries.map((e) {
                      final k = _localizeMetric(e.key.toString());
                      final v = (e.value is num)
                          ? (e.value as num).toStringAsFixed(1)
                          : _localizeMetric(e.value.toString());
                      return Text('- $k: $v');
                    }),
                    const SizedBox(height: 8),
                    const Text('加点項目',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Builder(
                      builder: (context) {
                        final List bonusLabels =
                            (scoreRes['bonusLabels'] is List)
                                ? (scoreRes['bonusLabels'] as List)
                                : const [];
                        if (bonusLabels.isEmpty) return const Text('—');
                        return Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: bonusLabels
                              .map(
                                (e) => Chip(
                                  label: Text(e.toString()),
                                  backgroundColor: const Color(0xFFEFF7F7),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text('要約',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_localizeMetric(reason)),
                  ],
                ),
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
          SizedBox(height: MediaQuery.of(context).size.width < 360 ? 8 : 10),
          const SizedBox(height: 16),
          Builder(builder: (context) {
            final List<String> sel = widget.selectedAccessMethods;
            final int? compCar = (item['computed_time_car'] is num)
                ? (item['computed_time_car'] as num).toInt()
                : null;
            final int? compPT = (item['computed_time_public'] is num)
                ? (item['computed_time_public'] as num).toInt()
                : null;
            String? carTime = compCar != null
                ? compCar.toString()
                : ((item['time_car']?.toString().isNotEmpty ?? false)
                    ? item['time_car'].toString()
                    : null);
            String? publicTime = compPT != null
                ? compPT.toString()
                : ((item['time_public']?.toString().isNotEmpty ?? false)
                    ? item['time_public'].toString()
                    : null);
            String? combined = (item['time']?.toString().isNotEmpty ?? false)
                ? item['time'].toString()
                : null;

            // デバッグ出力（verbose時のみ）
            Log.v('🚗 Access Time Debug for ${item['name']}:');
            Log.v('  sel (selected): $sel');
            Log.v('  time_car: "$carTime"');
            Log.v('  time_public: "$publicTime"');
            Log.v('  time (combined): "$combined"');

            String? parseCombinedFor(String method) {
              if (combined == null) return null;
              final idx = combined.indexOf('（');
              final idx2 = combined.indexOf('）');
              if (idx > 0 && idx2 > idx) {
                final label = combined.substring(idx + 1, idx2);
                final timePart = combined.substring(0, idx).trim();
                if (method == 'car' && label.contains('車')) return timePart;
                if (method == 'public' &&
                    (label.contains('電車') || label.contains('公共交通機関'))) {
                  return timePart;
                }
              }
              return null;
            }

            carTime ??= parseCombinedFor('car');
            publicTime ??= parseCombinedFor('public');

            final List<Widget> lines = [];
            const TextStyle lineStyle = TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black87);

            // 常に表示（選択に関係なく、データがあれば表示）
            bool showCar = true;
            bool showPublic = true;

            if (showCar && (carTime != null && carTime.isNotEmpty)) {
              // 時間に「分」を追加（数値のみの場合）
              final displayTime = carTime.contains('分') ? carTime : '$carTime分';
              lines.add(Row(
                children: [
                  const Icon(Icons.directions_car,
                      color: Colors.grey, size: 22),
                  const SizedBox(width: 8),
                  Text('車: $displayTime${compCar != null ? '（実ルート）' : ''}',
                      style: lineStyle),
                ],
              ));
            }
            if (showPublic && (publicTime != null && publicTime.isNotEmpty)) {
              if (lines.isNotEmpty) lines.add(const SizedBox(height: 6));
              // 時間に「分」を追加（数値のみの場合）
              final displayTime =
                  publicTime.contains('分') ? publicTime : '$publicTime分';
              lines.add(Row(
                children: [
                  const Icon(Icons.train, color: Color(0xFF267365), size: 22),
                  const SizedBox(width: 8),
                  Text('公共交通機関: $displayTime${compPT != null ? '（実ルート）' : ''}',
                      style: lineStyle),
                ],
              ));
            }

            if (lines.isEmpty && combined != null) {
              // Fallback to original single-line display if we have nothing parsed
              lines.add(Row(
                children: [
                  if ((item['access'] as List).contains('車'))
                    const Icon(Icons.directions_car,
                        color: Colors.grey, size: 22),
                  if ((item['access'] as List).contains('公共交通機関'))
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child:
                          Icon(Icons.train, color: Color(0xFF267365), size: 22),
                    ),
                  const SizedBox(width: 10),
                  Text(combined, style: lineStyle),
                ],
              ));
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            );
          }),
          const SizedBox(height: 12),
          Text('コースタイム: ${item['courseTime']}',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailPage(
                      mountain: item,
                      departureLabel: widget.departureLabel,
                      plannedDate: widget.plannedDate,
                      departureLat: widget.departureLat,
                      departureLng: widget.departureLng,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent),
              child: _fancyCTA(onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailPage(
                      mountain: item,
                      departureLabel: widget.departureLabel,
                      plannedDate: widget.plannedDate,
                      departureLat: widget.departureLat,
                      departureLng: widget.departureLng,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fancyCTA({required VoidCallback onTap}) {
    // オレンジ×黄色の濃いめグラデーション（ホバー時は少し明るめ）
    final baseColors = _ctaHover
        ? const [Color(0xFFFF8F00), Color(0xFFFFB300), Color(0xFFFFD54F)]
        : const [Color(0xFFF57C00), Color(0xFFFFA000), Color(0xFFFFC107)];
    final shadow = _ctaHover ? 14.0 : 10.0;
    final scale = _ctaPressed ? 0.98 : (_ctaHover ? 1.02 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _ctaHover = true),
      onExit: (_) => setState(() => _ctaHover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _ctaPressed = true),
        onTapCancel: () => setState(() => _ctaPressed = false),
        onTapUp: (_) => setState(() => _ctaPressed = false),
        onTap: onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: baseColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFF8F00).withValues(alpha: 0.45),
                    blurRadius: shadow,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: const SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  '詳細はこちら',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.0),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ローディングインジケーター: ロゴをぐるぐる回転させて表示
class _LoadingIndicator extends StatefulWidget {
  const _LoadingIndicator();

  @override
  State<_LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<_LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _controller.value * 2 * 3.14159,
                child: child,
              );
            },
            child: const SimpleSunIcon(size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            '空のご機嫌検索中',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
