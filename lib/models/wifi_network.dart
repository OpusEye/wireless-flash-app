/// Модель WiFi сети
class WifiNetwork {
  final String ssid;
  final int rssi;
  final bool isSecure;
  final bool isConnected;

  WifiNetwork({
    required this.ssid,
    required this.rssi,
    this.isSecure = true,
    this.isConnected = false,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: json['ssid'] ?? '',
      rssi: json['rssi'] ?? -100,
      isSecure: json['secure'] ?? true,
      isConnected: json['connected'] ?? false,
    );
  }

  double get signalPercent {
    if (rssi >= -30) return 1.0;
    if (rssi <= -100) return 0.0;
    return (rssi + 100) / 70.0;
  }

  String get signalBars {
    final percent = signalPercent;
    if (percent > 0.75) return '████';
    if (percent > 0.5) return '███░';
    if (percent > 0.25) return '██░░';
    return '█░░░';
  }
}
