import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/device.dart';
import '../models/file_item.dart';
import '../models/wifi_network.dart';

/// Упрощённый API клиент для первичной настройки
class DeviceApi {
  final String ip;
  
  DeviceApi(this.ip);
  
  String get _baseUrl => 'http://$ip';
  
  /// Получить статус устройства
  Future<DeviceStatus> getStatus() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/status'))
        .timeout(const Duration(seconds: 5));
    
    if (response.statusCode == 200) {
      return DeviceStatus.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to get status: ${response.statusCode}');
  }
  
  /// Сканировать WiFi сети
  Future<List<String>> scanWifiNetworks() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/wifi/scan'))
        .timeout(const Duration(seconds: 15));
    
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final networks = json['networks'] as List? ?? [];
      return networks.map((n) => n['ssid']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    throw Exception('Failed to scan networks: ${response.statusCode}');
  }
  
  /// Подключить устройство к WiFi
  Future<Map<String, dynamic>> connectToWifi(String ssid, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/wifi/connect'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'ssid': ssid, 'password': password}),
    ).timeout(const Duration(seconds: 30));
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to connect: ${response.statusCode}');
  }
}

/// Статус устройства
class DeviceStatus {
  final String? deviceId;
  final int sdTotalMb;
  final int sdFreeMb;
  final String? staIp;
  final String? staSsid;
  final bool staConnected;
  
  DeviceStatus({
    this.deviceId,
    this.sdTotalMb = 0,
    this.sdFreeMb = 0,
    this.staIp,
    this.staSsid,
    this.staConnected = false,
  });
  
  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    final totalBytes = json['totalBytes'] as int? ?? 0;
    final freeBytes = json['freeBytes'] as int? ?? 0;
    final wifi = json['wifi'] as Map<String, dynamic>?;
    
    return DeviceStatus(
      deviceId: json['deviceId'] ?? json['macAddress'],
      sdTotalMb: (totalBytes / (1024 * 1024)).round(),
      sdFreeMb: (freeBytes / (1024 * 1024)).round(),
      staIp: wifi?['staIp'],
      staSsid: wifi?['staSsid'],
      staConnected: wifi?['staState'] == 2,
    );
  }
}

/// Сервис для работы с API устройства Wireless Flash
class DeviceApiService {
  String _baseUrl = 'http://192.168.4.1';
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _listTimeout = Duration(seconds: 15);
  
  // Переиспользуемый HTTP клиент для keep-alive соединений
  final http.Client _client = http.Client();

  String get baseUrl => _baseUrl;
  
  /// Освобождение ресурсов
  void dispose() {
    _client.close();
  }

  void setDeviceIp(String ip) {
    _baseUrl = 'http://$ip';
  }

  /// Проверка доступности устройства
  Future<bool> isDeviceAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Получение статуса устройства
  Future<WirelessFlashDevice?> getDeviceStatus() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(_timeout);
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        // API возвращает bytes, конвертируем в MB
        final totalBytes = json['totalBytes'] as int? ?? 0;
        final freeBytes = json['freeBytes'] as int? ?? 0;
        final wifi = json['wifi'] as Map<String, dynamic>?;
        
        return WirelessFlashDevice.fromJson({
          'ssid': 'WirelessFlash',
          'ip': _baseUrl.replaceFirst('http://', ''),
          'connected': true,
          'sd_total_mb': (totalBytes / (1024 * 1024)).round(),
          'sd_free_mb': (freeBytes / (1024 * 1024)).round(),
          'sta_ip': wifi?['staIp'],
          'sta_ssid': wifi?['staSsid'],
          'sta_connected': wifi?['staState'] == 2,
          'ap_clients': wifi?['apClients'],
          'rssi': wifi?['staRssi'],
        });
      }
    } catch (e) {
      print('Error getting device status: $e');
    }
    return null;
  }

  /// Получение списка файлов в директории с retry логикой
  Future<List<FileItem>> listFiles(String directoryPath, {int retries = 3}) async {
    final encodedPath = Uri.encodeComponent(directoryPath);
    
    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        final response = await _client
            .get(Uri.parse('$_baseUrl/api/list?path=$encodedPath'))
            .timeout(_listTimeout);
        
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          final files = (json['files'] as List? ?? [])
              .map((f) => FileItem.fromJson(f))
              .toList();
          
          // Сортировка: папки сначала, затем по имени
          files.sort((a, b) {
            if (a.isDirectory && !b.isDirectory) return -1;
            if (!a.isDirectory && b.isDirectory) return 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
          
          return files;
        }
      } catch (e) {
        print('Error listing files (attempt ${attempt + 1}/$retries): $e');
        if (attempt < retries - 1) {
          // Экспоненциальная задержка перед повтором
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
      }
    }
    return [];
  }

  /// Скачивание файла
  Future<List<int>?> downloadFile(String filePath) async {
    try {
      // Путь уже начинается с /, просто добавляем к /api/download
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/download$filePath'))
          .timeout(const Duration(minutes: 5));
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('Download failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error downloading file: $e');
    }
    return null;
  }

  /// Загрузка файла на устройство
  Future<bool> uploadFile(String remotePath, File file) async {
    try {
      // Формируем путь: /api/upload/путь/имя_файла
      final fileName = path.basename(file.path);
      final uploadPath = remotePath == '/' ? '/$fileName' : '$remotePath/$fileName';
      final uri = Uri.parse('$_baseUrl/api/upload$uploadPath');
      
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
      ));
      
      final response = await request.send().timeout(const Duration(minutes: 10));
      
      // Освобождаем ресурсы соединения
      await response.stream.drain();
      
      if (response.statusCode != 200) {
        print('Upload failed: ${response.statusCode}');
      }
      return response.statusCode == 200;
    } catch (e) {
      print('Error uploading file: $e');
      return false;
    }
  }

  /// Удаление файла/папки
  Future<bool> deleteFile(String filePath) async {
    try {
      // Путь уже начинается с /, просто добавляем к /api/delete
      final response = await _client
          .delete(Uri.parse('$_baseUrl/api/delete$filePath'))
          .timeout(_timeout);
      
      if (response.statusCode != 200) {
        print('Delete failed: ${response.statusCode}');
      }
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting file: $e');
      return false;
    }
  }

  /// Создание папки
  Future<bool> createFolder(String folderPath) async {
    try {
      // Путь передаётся в URL: /api/mkdir/путь
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/mkdir$folderPath'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);
      
      return response.statusCode == 200;
    } catch (e) {
      print('Error creating folder: $e');
      return false;
    }
  }

  /// Сканирование WiFi сетей
  Future<List<WifiNetwork>> scanWifiNetworks() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/wifi/scan'))
          .timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return (json['networks'] as List? ?? [])
            .map((n) => WifiNetwork.fromJson(n))
            .toList();
      }
    } catch (e) {
      print('Error scanning WiFi: $e');
    }
    return [];
  }

  /// Подключение к WiFi сети
  Future<Map<String, dynamic>> connectToWifiWithDetails(String ssid, String password) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/wifi/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ssid': ssid, 'password': password}),
      ).timeout(const Duration(seconds: 30)); // Увеличиваем таймаут - ESP32 ждёт подключения
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return {
          'success': json['success'] == true,
          'message': json['message'] ?? '',
          'ip': json['ip'] ?? '',
        };
      }
    } catch (e) {
      print('Error connecting to WiFi: $e');
    }
    return {'success': false, 'message': 'Connection error', 'ip': ''};
  }

  /// Подключение к WiFi сети (простой вариант)
  Future<bool> connectToWifi(String ssid, String password) async {
    final result = await connectToWifiWithDetails(ssid, password);
    return result['success'] == true;
  }

  /// Отключение от WiFi
  Future<bool> disconnectWifi() async {
    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl/api/wifi/disconnect'))
          .timeout(_timeout);
      
      return response.statusCode == 200;
    } catch (e) {
      print('Error disconnecting WiFi: $e');
      return false;
    }
  }
}
