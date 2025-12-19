/// Модель устройства Wireless Flash
class WirelessFlashDevice {
  final String ssid;
  final String ip;
  final int signalStrength;
  final bool isConnected;
  final String? staIp; // IP в домашней сети
  final String? staSSID; // Имя домашней сети
  final int? apClients; // Количество подключенных клиентов
  final int? sdTotalMb;
  final int? sdFreeMb;

  WirelessFlashDevice({
    required this.ssid,
    required this.ip,
    this.signalStrength = 0,
    this.isConnected = false,
    this.staIp,
    this.staSSID,
    this.apClients,
    this.sdTotalMb,
    this.sdFreeMb,
  });

  factory WirelessFlashDevice.fromJson(Map<String, dynamic> json) {
    return WirelessFlashDevice(
      ssid: json['ssid'] ?? 'WirelessFlash',
      ip: json['ip'] ?? '192.168.4.1',
      signalStrength: json['rssi'] ?? 0,
      isConnected: json['connected'] ?? false,
      staIp: json['sta_ip'],
      staSSID: json['sta_ssid'],
      apClients: json['ap_clients'],
      sdTotalMb: json['sd_total_mb'],
      sdFreeMb: json['sd_free_mb'],
    );
  }

  String get displayName => ssid;
  
  String get signalIcon {
    if (signalStrength > -50) return '📶';
    if (signalStrength > -70) return '📶';
    if (signalStrength > -85) return '📶';
    return '📶';
  }

  double get signalPercent {
    // RSSI обычно от -100 (плохой) до -30 (отличный)
    if (signalStrength >= -30) return 1.0;
    if (signalStrength <= -100) return 0.0;
    return (signalStrength + 100) / 70.0;
  }

  String get storageInfo {
    if (sdTotalMb == null) return 'N/A';
    final total = (sdTotalMb! / 1024).toStringAsFixed(2);
    final free = ((sdFreeMb ?? 0) / 1024).toStringAsFixed(2);
    return '$free / $total GB свободно';
  }
}
