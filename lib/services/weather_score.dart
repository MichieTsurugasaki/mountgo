/// Lightweight weather scoring utility.
/// Produces a simple score and breakdown from a forecast map.
class WeatherScore {
  /// Accepts a map with keys like: pop (0..1), wind_m_s, cloud_pct, temp_c, precip_mm.
  /// Returns a map with: score, augScore, bonus, bonusLabels, reason, breakdown.
  static Map<String, dynamic> scoreDay(Map<String, dynamic> forecast) {
    final pop =
        (forecast['pop'] is num) ? (forecast['pop'] as num).toDouble() : 0.0;
    final wind = (forecast['wind_m_s'] is num)
        ? (forecast['wind_m_s'] as num).toDouble()
        : 2.0;
    final cloud = (forecast['cloud_pct'] is num)
        ? (forecast['cloud_pct'] as num).toDouble()
        : 20.0;
    final temp = (forecast['temp_c'] is num)
        ? (forecast['temp_c'] as num).toDouble()
        : 18.0;

    double score = 70.0;
    score -= (pop.clamp(0.0, 1.0)) * 50.0; // rain prob hurts a lot
    score -= (wind.clamp(0.0, 12.0)) * 2.0; // strong wind hurts
    score -= (cloud.clamp(0.0, 100.0)) * 0.3; // cloudiness penalized

    // gentle penalty if too cold/hot
    if (temp < 5) score -= 10;
    if (temp > 28) score -= 6;

    final clamped = score.clamp(0.0, 100.0).round();

    final breakdown = {
      'POP': '${(pop * 100).toStringAsFixed(0)}%',
      'Wind': '${wind.toStringAsFixed(1)} m/s',
      'Cloud cover': '${cloud.toStringAsFixed(0)}%',
      'Temp': '${temp.toStringAsFixed(1)} °C',
    };

    final reason = pop < 0.2
        ? '降水は少なく、風も比較的穏やかです。'
        : (pop < 0.4 ? 'やや不安定な天候の可能性があります。' : '降水リスクが高めです。計画の見直しも検討ください。');

    return {
      'score': clamped,
      'augScore': clamped,
      'bonus': 0,
      'bonusLabels': <String>[],
      'reason': reason,
      'breakdown': breakdown,
    };
  }
}
