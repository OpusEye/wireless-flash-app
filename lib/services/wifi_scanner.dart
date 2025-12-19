import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тип обнаруженного устройства
enum DeviceType {
  newDevice,     // Новое устройство (WiFi точка доступа)
  pairedDevice,  // Сопряжённое устройство в домашней сети
}

/// Информация о найденном устройстве WirelessFlash
class DiscoveredDevice {
  final String ssid;
  final int signalStrength;
  final String ip;
  final DeviceType type;
  final String? deviceId;       // Уникальный ID устройства
  final String? friendlyName;   // Пользовательское имя
  final bool isOnline;          // Доступно ли устройство сейчас

  DiscoveredDevice({
    required this.ssid,
    required this.signalStrength,
    this.ip = '192.168.4.1',
    this.type = DeviceType.newDevice,
    this.deviceId,
    this.friendlyName,
    this.isOnline = true,
  });

  /// Качество сигнала в процентах
  int get signalPercent {
    // RSSI обычно от -100 до -30 dBm
    if (signalStrength >= -50) return 100;
    if (signalStrength <= -100) return 0;
    return ((signalStrength + 100) * 2).clamp(0, 100);
  }

  /// Количество полосок сигнала (0-4)
  int get signalBars {
    if (signalPercent >= 80) return 4;
    if (signalPercent >= 60) return 3;
    if (signalPercent >= 40) return 2;
    if (signalPercent >= 20) return 1;
    return 0;
  }

  /// Отображаемое имя устройства
  String get displayName => friendlyName ?? ssid;

  Map<String, dynamic> toJson() => {
    'ssid': ssid,
    'ip': ip,
    'deviceId': deviceId,
    'friendlyName': friendlyName,
  };

  factory DiscoveredDevice.fromJson(Map<String, dynamic> json) {
    return DiscoveredDevice(
      ssid: json['ssid'] ?? 'WirelessFlash',
      signalStrength: -50,
      ip: json['ip'] ?? '192.168.4.1',
      type: DeviceType.pairedDevice,
      deviceId: json['deviceId'],
      friendlyName: json['friendlyName'],
      isOnline: false,
    );
  }
}

/// Сохранённое сопряжённое устройство
class PairedDevice {
  final String deviceId;     // MAC адрес или уникальный ID
  final String ssid;         // Имя WiFi сети устройства
  final String? friendlyName;
  String? lastKnownIp;
  DateTime? lastSeen;

  PairedDevice({
    required this.deviceId,
    required this.ssid,
    this.friendlyName,
    this.lastKnownIp,
    this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'ssid': ssid,
    'friendlyName': friendlyName,
    'lastKnownIp': lastKnownIp,
    'lastSeen': lastSeen?.toIso8601String(),
  };

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      deviceId: json['deviceId'] ?? '',
      ssid: json['ssid'] ?? 'WirelessFlash',
      friendlyName: json['friendlyName'],
      lastKnownIp: json['lastKnownIp'],
      lastSeen: json['lastSeen'] != null ? DateTime.tryParse(json['lastSeen']) : null,
    );
  }
}

/// Сканер WiFi сетей для обнаружения устройств WirelessFlash
class WifiScanner {
  static const String _pairedDevicesKey = 'paired_devices';

  // ==================== СОПРЯЖЁННЫЕ УСТРОЙСТВА ====================

  /// Загружает список сопряжённых устройств
  static Future<List<PairedDevice>> loadPairedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_pairedDevicesKey);
      if (json == null) return [];
      
      final list = jsonDecode(json) as List;
      return list.map((e) => PairedDevice.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error loading paired devices: $e');
      return [];
    }
  }

  /// Сохраняет сопряжённое устройство
  static Future<void> savePairedDevice(PairedDevice device) async {
    try {
      final devices = await loadPairedDevices();
      
      // Убираем старую запись с таким же deviceId
      devices.removeWhere((d) => d.deviceId == device.deviceId);
      devices.add(device);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pairedDevicesKey, jsonEncode(devices.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving paired device: $e');
    }
  }

  /// Удаляет сопряжённое устройство
  static Future<void> removePairedDevice(String deviceId) async {
    try {
      final devices = await loadPairedDevices();
      devices.removeWhere((d) => d.deviceId == deviceId);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pairedDevicesKey, jsonEncode(devices.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Error removing paired device: $e');
    }
  }

  // ==================== СКАНИРОВАНИЕ ====================

  /// Сканирует WiFi сети и возвращает найденные устройства WirelessFlash
  static Future<List<DiscoveredDevice>> scanForDevices() async {
    if (kIsWeb) {
      return []; // В веб-версии сканирование невозможно
    }

    if (Platform.isWindows) {
      return _scanWindows();
    } else if (Platform.isAndroid) {
      return _scanAndroid();
    }

    return [];
  }

  /// Полный поиск: новые устройства WiFi + сопряжённые устройства в сети
  static Future<({List<DiscoveredDevice> newDevices, List<DiscoveredDevice> pairedDevices})> discoverAllDevices() async {
    // Параллельно ищем новые WiFi и проверяем сопряжённые
    final results = await Future.wait([
      scanForDevices(),
      _checkPairedDevicesOnline(),
    ]);

    return (
      newDevices: results[0] as List<DiscoveredDevice>,
      pairedDevices: results[1] as List<DiscoveredDevice>,
    );
  }

  /// Проверяет сопряжённые устройства - доступны ли они в сети
  static Future<List<DiscoveredDevice>> _checkPairedDevicesOnline() async {
    final paired = await loadPairedDevices();
    if (paired.isEmpty) return [];

    final devices = <DiscoveredDevice>[];

    // Список IP для проверки
    final ipsToCheck = <String>{};
    
    // Добавляем известные IP от сопряжённых устройств
    for (final p in paired) {
      if (p.lastKnownIp != null && p.lastKnownIp!.isNotEmpty) {
        ipsToCheck.add(p.lastKnownIp!);
      }
    }
    
    // Добавляем стандартные IP
    ipsToCheck.add('192.168.0.17'); // Частый IP в домашних сетях
    
    // Пробуем mDNS
    try {
      final result = await InternetAddress.lookup('wirelessflash.local')
          .timeout(const Duration(seconds: 2));
      if (result.isNotEmpty) {
        ipsToCheck.add(result.first.address);
      }
    } catch (_) {
      debugPrint('mDNS lookup failed');
    }

    // Проверяем все IP параллельно
    final Map<String, Map<String, dynamic>> foundDevices = {};
    
    await Future.wait(ipsToCheck.map((ip) async {
      final info = await _getDeviceInfo(ip);
      if (info != null) {
        foundDevices[ip] = info;
      }
    }));

    for (final p in paired) {
      String? foundIp;
      Map<String, dynamic>? deviceInfo;
      
      // Ищем устройство среди найденных
      for (final entry in foundDevices.entries) {
        // Проверяем по deviceId или просто берём первое найденное
        final info = entry.value;
        final infoDeviceId = info['deviceId'] ?? info['macAddress'] ?? '';
        
        if (p.deviceId == infoDeviceId || p.deviceId == p.ssid) {
          // Если deviceId совпадает ИЛИ deviceId это просто SSID (старый формат)
          foundIp = entry.key;
          deviceInfo = info;
          break;
        }
      }
      
      // Если не нашли по ID, но есть найденное устройство - используем его
      if (foundIp == null && foundDevices.isNotEmpty) {
        final entry = foundDevices.entries.first;
        foundIp = entry.key;
        deviceInfo = entry.value;
      }

      devices.add(DiscoveredDevice(
        ssid: p.ssid,
        signalStrength: -50,
        ip: foundIp ?? p.lastKnownIp ?? '',
        type: DeviceType.pairedDevice,
        deviceId: p.deviceId,
        friendlyName: p.friendlyName,
        isOnline: foundIp != null,
      ));

      // Обновляем lastKnownIp если нашли
      if (foundIp != null && foundIp != p.lastKnownIp) {
        p.lastKnownIp = foundIp;
        p.lastSeen = DateTime.now();
        savePairedDevice(p);
      }
    }

    return devices;
  }

  /// Получает информацию об устройстве по IP
  static Future<Map<String, dynamic>?> _getDeviceInfo(String ip) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse('http://$ip/api/status'));
      final response = await request.close().timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        client.close();
        debugPrint('Found device at $ip');
        return jsonDecode(body) as Map<String, dynamic>;
      }
      client.close();
    } catch (e) {
      debugPrint('Device check failed for $ip: $e');
    }
    return null;
  }

  /// Сканирование на Windows через netsh
  static Future<List<DiscoveredDevice>> _scanWindows() async {
    try {
      // Запускаем сканирование WiFi сетей
      final result = await Process.run(
        'netsh',
        ['wlan', 'show', 'networks', 'mode=bssid'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        debugPrint('netsh failed: ${result.stderr}');
        return [];
      }

      return _parseNetshOutput(result.stdout as String);
    } catch (e) {
      debugPrint('WiFi scan error: $e');
      return [];
    }
  }

  /// Парсинг вывода netsh wlan show networks
  static List<DiscoveredDevice> _parseNetshOutput(String output) {
    final devices = <DiscoveredDevice>[];
    final lines = output.split('\n');

    String? currentSsid;
    int currentSignal = 0;

    for (final line in lines) {
      final trimmed = line.trim();

      // Ищем SSID (поддержка русского и английского)
      if (trimmed.startsWith('SSID') || trimmed.startsWith('BSSID') == false && trimmed.contains('SSID')) {
        final match = RegExp(r'SSID\s*\d*\s*:\s*(.+)').firstMatch(trimmed);
        if (match != null) {
          currentSsid = match.group(1)?.trim();
        }
      }

      // Ищем сигнал (Signal/Сигнал)
      if (trimmed.contains('%')) {
        final match = RegExp(r'(\d+)\s*%').firstMatch(trimmed);
        if (match != null) {
          currentSignal = int.tryParse(match.group(1) ?? '0') ?? 0;
          // Конвертируем процент в приблизительный RSSI
          currentSignal = -100 + currentSignal; // Упрощённая формула
        }
      }

      // Если нашли устройство WirelessFlash - добавляем как НОВОЕ
      if (currentSsid != null && 
          currentSsid.toLowerCase().contains('wirelessflash') &&
          currentSignal != 0) {
        devices.add(DiscoveredDevice(
          ssid: currentSsid,
          signalStrength: currentSignal,
          type: DeviceType.newDevice,
        ));
        currentSsid = null;
        currentSignal = 0;
      }
    }

    // Сортируем по силе сигнала (сильнее - первые)
    devices.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));

    return devices;
  }

  /// Сканирование на Android (заглушка - требует отдельную настройку)
  static Future<List<DiscoveredDevice>> _scanAndroid() async {
    // Для Android нужен wifi_scan пакет и разрешения
    // Пока возвращаем пустой список
    return [];
  }

  /// Проверяет, подключен ли компьютер к сети WirelessFlash
  static Future<DiscoveredDevice?> getCurrentWirelessFlashConnection() async {
    if (kIsWeb) return null;

    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'netsh',
          ['wlan', 'show', 'interfaces'],
          runInShell: true,
        );

        if (result.exitCode != 0) return null;

        final output = result.stdout as String;
        final lines = output.split('\n');

        String? ssid;
        int signal = 0;

        for (final line in lines) {
          final trimmed = line.trim();

          // Ищем SSID подключенной сети
          if (trimmed.startsWith('SSID') && !trimmed.contains('BSSID')) {
            final match = RegExp(r'SSID\s*:\s*(.+)').firstMatch(trimmed);
            if (match != null) {
              ssid = match.group(1)?.trim();
            }
          }

          // Ищем сигнал
          if (trimmed.contains('%')) {
            final match = RegExp(r'(\d+)\s*%').firstMatch(trimmed);
            if (match != null) {
              signal = -100 + (int.tryParse(match.group(1) ?? '0') ?? 0);
            }
          }
        }

        if (ssid != null && ssid.toLowerCase().contains('wirelessflash')) {
          return DiscoveredDevice(ssid: ssid, signalStrength: signal);
        }
      } catch (e) {
        debugPrint('Error checking current connection: $e');
      }
    }

    return null;
  }

  /// Подключается к WiFi сети на Windows
  static Future<bool> connectToWifi(String ssid, String password) async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      // Создаём XML профиль для сети
      final profileXml = '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$ssid</name>
  <SSIDConfig>
    <SSID>
      <name>$ssid</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>$password</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>''';

      // Сохраняем профиль во временный файл
      final tempDir = Directory.systemTemp;
      final profileFile = File('${tempDir.path}\\wifi_profile_$ssid.xml');
      await profileFile.writeAsString(profileXml);

      // Добавляем профиль
      final addResult = await Process.run(
        'netsh',
        ['wlan', 'add', 'profile', 'filename=${profileFile.path}'],
        runInShell: true,
      );

      debugPrint('Add profile result: ${addResult.stdout} ${addResult.stderr}');

      // Удаляем временный файл
      try {
        await profileFile.delete();
      } catch (_) {}

      if (addResult.exitCode != 0) {
        debugPrint('Failed to add profile: ${addResult.stderr}');
        // Профиль может уже существовать, пробуем подключиться
      }

      // Подключаемся к сети
      final connectResult = await Process.run(
        'netsh',
        ['wlan', 'connect', 'name=$ssid'],
        runInShell: true,
      );

      debugPrint('Connect result: ${connectResult.stdout} ${connectResult.stderr}');

      if (connectResult.exitCode == 0) {
        // Ждём подключения
        await Future.delayed(const Duration(seconds: 3));
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('WiFi connect error: $e');
      return false;
    }
  }

  /// Отключается от текущей WiFi сети
  static Future<bool> disconnectWifi() async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      final result = await Process.run(
        'netsh',
        ['wlan', 'disconnect'],
        runInShell: true,
      );

      return result.exitCode == 0;
    } catch (e) {
      debugPrint('WiFi disconnect error: $e');
      return false;
    }
  }

  /// Пытается найти устройство WirelessFlash в локальной сети
  /// Возвращает IP адрес или null
  static Future<String?> findDeviceInLocalNetwork() async {
    if (kIsWeb) return null;

    // Сначала пробуем mDNS имя
    try {
      final result = await InternetAddress.lookup('wirelessflash.local');
      if (result.isNotEmpty) {
        return result.first.address;
      }
    } catch (_) {
      debugPrint('mDNS lookup failed, trying direct IP check');
    }

    // Проверяем стандартный IP точки доступа
    if (await _checkDeviceAt('192.168.4.1')) {
      return '192.168.4.1';
    }

    // Сканируем локальную сеть
    final localIp = await _getLocalIp();
    if (localIp != null) {
      final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
      
      // Параллельно проверяем несколько IP
      final futures = <Future<String?>>[];
      for (int i = 1; i <= 254; i++) {
        final ip = '$subnet.$i';
        futures.add(_checkDeviceAt(ip).then((found) => found ? ip : null));
      }
      
      // Ждём первый найденный
      for (final future in futures) {
        final ip = await future;
        if (ip != null) return ip;
      }
    }

    return null;
  }

  /// Проверяет, есть ли устройство WirelessFlash по указанному IP
  static Future<bool> _checkDeviceAt(String ip) async {
    try {
      final socket = await Socket.connect(
        ip,
        80,
        timeout: const Duration(milliseconds: 500),
      );
      await socket.close();
      
      // Проверяем что это наше устройство через API
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 2);
      final request = await httpClient.getUrl(Uri.parse('http://$ip/api/status'));
      final response = await request.close();
      httpClient.close();
      
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Получает локальный IP адрес компьютера
  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return null;
  }
}
