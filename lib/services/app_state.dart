import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/device.dart';
import '../models/file_item.dart';
import '../models/wifi_network.dart';
import 'device_api.dart';

/// Провайдер состояния приложения с оптимизациями
class AppState extends ChangeNotifier {
  final DeviceApiService _api = DeviceApiService();
  
  // Защита от утечек памяти
  bool _disposed = false;
  
  // Debounce для notifyListeners
  Timer? _notifyDebounce;
  bool _pendingNotify = false;
  
  // Состояние подключения
  bool _isConnected = false;
  bool _isConnecting = false;
  WirelessFlashDevice? _currentDevice;
  String? _error;

  // Файловый менеджер
  String _currentPath = '/';
  List<FileItem> _files = [];
  bool _isLoadingFiles = false;
  final Set<String> _selectedFiles = {};

  // WiFi настройки
  List<WifiNetwork> _wifiNetworks = [];
  bool _isScanning = false;

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  WirelessFlashDevice? get currentDevice => _currentDevice;
  String? get error => _error;
  
  String get currentPath => _currentPath;
  List<FileItem> get files => List.unmodifiable(_files);
  bool get isLoadingFiles => _isLoadingFiles;
  Set<String> get selectedFiles => Set.unmodifiable(_selectedFiles);
  bool get hasSelection => _selectedFiles.isNotEmpty;
  
  List<WifiNetwork> get wifiNetworks => List.unmodifiable(_wifiNetworks);
  bool get isScanning => _isScanning;

  DeviceApiService get api => _api;

  @override
  void dispose() {
    _disposed = true;
    _notifyDebounce?.cancel();
    super.dispose();
  }

  /// Безопасный notifyListeners с debounce
  void _safeNotify({bool immediate = false}) {
    if (_disposed) return;
    
    if (immediate) {
      _notifyDebounce?.cancel();
      notifyListeners();
      return;
    }
    
    _pendingNotify = true;
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(milliseconds: 16), () {
      if (!_disposed && _pendingNotify) {
        _pendingNotify = false;
        notifyListeners();
      }
    });
  }

  /// Подключение к устройству
  Future<bool> connectToDevice(String ip) async {
    if (_isConnecting) return false;
    
    _isConnecting = true;
    _error = null;
    _safeNotify(immediate: true);

    try {
      _api.setDeviceIp(ip);
      
      final isAvailable = await _api.isDeviceAvailable();
      if (!isAvailable) {
        _error = 'Устройство недоступно';
        _isConnecting = false;
        _safeNotify(immediate: true);
        return false;
      }

      _currentDevice = await _api.getDeviceStatus();
      _isConnected = true;
      _isConnecting = false;
      
      // Загружаем корневую директорию
      await loadFiles('/');
      
      _safeNotify(immediate: true);
      return true;
    } catch (e) {
      _error = 'Ошибка подключения: $e';
      _isConnecting = false;
      _safeNotify(immediate: true);
      return false;
    }
  }

  /// Отключение от устройства
  void disconnect() {
    _isConnected = false;
    _currentDevice = null;
    _files = [];
    _currentPath = '/';
    _selectedFiles.clear();
    _safeNotify(immediate: true);
  }

  /// Обновление статуса устройства
  Future<void> refreshDeviceStatus() async {
    if (!_isConnected || _disposed) return;
    
    try {
      _currentDevice = await _api.getDeviceStatus();
      _safeNotify();
    } catch (e) {
      debugPrint('Error refreshing device status: $e');
    }
  }

  /// Загрузка списка файлов
  Future<void> loadFiles(String path) async {
    if (_isLoadingFiles || _disposed) return;
    
    _isLoadingFiles = true;
    _selectedFiles.clear();
    _safeNotify(immediate: true);

    try {
      _files = await _api.listFiles(path);
      _currentPath = path;
      _error = null;
    } catch (e) {
      _error = 'Ошибка загрузки файлов: $e';
      debugPrint('Error loading files: $e');
    }

    _isLoadingFiles = false;
    _safeNotify(immediate: true);
  }

  /// Навигация в папку
  Future<void> navigateToFolder(String folderName) async {
    final newPath = _currentPath == '/' 
        ? '/$folderName' 
        : '$_currentPath/$folderName';
    await loadFiles(newPath);
  }

  /// Навигация назад
  Future<void> navigateBack() async {
    if (_currentPath == '/') return;
    
    final parts = _currentPath.split('/');
    parts.removeLast();
    final newPath = parts.isEmpty ? '/' : parts.join('/');
    await loadFiles(newPath.isEmpty ? '/' : newPath);
  }

  /// Выбор файла (без лишних перестроений)
  void toggleFileSelection(String path) {
    if (_selectedFiles.contains(path)) {
      _selectedFiles.remove(path);
    } else {
      _selectedFiles.add(path);
    }
    _safeNotify();
  }

  /// Выбрать все
  void selectAll() {
    _selectedFiles.clear();
    for (final f in _files) {
      if (!f.isDirectory) {
        _selectedFiles.add(f.path);
      }
    }
    _safeNotify(immediate: true);
  }

  /// Снять выделение
  void clearSelection() {
    if (_selectedFiles.isEmpty) return;
    _selectedFiles.clear();
    _safeNotify(immediate: true);
  }

  /// Загрузка файлов на устройство
  Future<bool> uploadFiles(List<File> files) async {
    var success = true;
    for (final file in files) {
      if (_disposed) break;
      final result = await _api.uploadFile(_currentPath, file);
      if (!result) success = false;
    }
    
    if (success && !_disposed) {
      await loadFiles(_currentPath);
    }
    
    return success;
  }

  /// Удаление выбранных файлов
  Future<bool> deleteSelectedFiles() async {
    var success = true;
    final filesToDelete = _selectedFiles.toList();
    
    for (final path in filesToDelete) {
      if (_disposed) break;
      final result = await _api.deleteFile(path);
      if (!result) success = false;
    }
    
    _selectedFiles.clear();
    if (!_disposed) {
      await loadFiles(_currentPath);
    }
    
    return success;
  }

  /// Создание папки
  Future<bool> createFolder(String name) async {
    final path = _currentPath == '/' ? '/$name' : '$_currentPath/$name';
    final result = await _api.createFolder(path);
    
    if (result && !_disposed) {
      await loadFiles(_currentPath);
    }
    
    return result;
  }

  /// Сканирование WiFi сетей
  Future<void> scanWifi() async {
    if (_isScanning || _disposed) return;
    
    _isScanning = true;
    _safeNotify(immediate: true);

    try {
      _wifiNetworks = await _api.scanWifiNetworks();
    } catch (e) {
      _error = 'Ошибка сканирования: $e';
      debugPrint('Error scanning WiFi: $e');
    }

    _isScanning = false;
    _safeNotify(immediate: true);
  }

  /// Подключение к WiFi сети
  Future<bool> connectToWifi(String ssid, String password) async {
    try {
      final result = await _api.connectToWifi(ssid, password);
      if (result && !_disposed) {
        await refreshDeviceStatus();
      }
      return result;
    } catch (e) {
      debugPrint('Error connecting to WiFi: $e');
      return false;
    }
  }

  /// Отключение от WiFi
  Future<bool> disconnectFromWifi() async {
    try {
      final result = await _api.disconnectWifi();
      if (result && !_disposed) {
        await refreshDeviceStatus();
      }
      return result;
    } catch (e) {
      debugPrint('Error disconnecting from WiFi: $e');
      return false;
    }
  }

  /// Очистка ошибки
  void clearError() {
    if (_error == null) return;
    _error = null;
    _safeNotify();
  }
}
