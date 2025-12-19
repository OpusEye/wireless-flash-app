import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/wifi_scanner.dart';
import 'device_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.4.1');
  
  // Новые устройства (WiFi точки доступа WirelessFlash)
  List<DiscoveredDevice> _newDevices = [];
  
  // Сопряжённые устройства
  List<DiscoveredDevice> _pairedDevices = [];
  
  // Текущее подключение к WiFi WirelessFlash (для настройки)
  DiscoveredDevice? _connectedToDeviceWifi;
  
  bool _isScanning = false;
  bool _mounted = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_mounted) _scanForDevices();
    });
  }

  @override
  void dispose() {
    _mounted = false;
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _scanForDevices() async {
    if (kIsWeb || !_mounted) return;

    setState(() => _isScanning = true);

    try {
      // 1. Проверяем, подключены ли мы к WiFi устройства WirelessFlash
      _connectedToDeviceWifi = await WifiScanner.getCurrentWirelessFlashConnection();
      
      if (!_mounted) return;

      // Если подключены к WiFi устройства - предлагаем настройку
      if (_connectedToDeviceWifi != null) {
        setState(() => _isScanning = false);
        return;
      }

      // 2. Полное сканирование
      final result = await WifiScanner.discoverAllDevices();
      
      if (!_mounted) return;
      
      _newDevices = result.newDevices;
      _pairedDevices = result.pairedDevices;
      
      // Если есть онлайн устройство - подставляем его IP
      final onlineDevice = _pairedDevices.where((d) => d.isOnline).firstOrNull;
      if (onlineDevice != null) {
        _ipController.text = onlineDevice.ip;
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    }

    if (_mounted) {
      setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.usb, size: 28),
            SizedBox(width: 8),
            Text('Wireless Flash'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _scanForDevices,
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          if (appState.isConnected) {
            return const DeviceScreen();
          }
          return _buildConnectionScreen(appState);
        },
      ),
    );
  }

  Widget _buildConnectionScreen(AppState appState) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Логотип
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.usb,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Wireless Flash',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Беспроводной файловый менеджер',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 32),

              // Ошибка
              if (appState.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          appState.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: appState.clearError,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ==================== ПОДКЛЮЧЕНЫ К WiFi УСТРОЙСТВА ====================
              if (_connectedToDeviceWifi != null) ...[
                _buildDirectConnectionCard(appState),
                const SizedBox(height: 24),
              ],

              // ==================== СОПРЯЖЁННЫЕ УСТРОЙСТВА ====================
              if (_pairedDevices.isNotEmpty && _connectedToDeviceWifi == null) ...[
                _buildPairedDevicesCard(appState),
                const SizedBox(height: 24),
              ],

              // ==================== НОВЫЕ УСТРОЙСТВА (WiFi) ====================
              if (_newDevices.isNotEmpty && _connectedToDeviceWifi == null) ...[
                _buildNewDevicesCard(),
                const SizedBox(height: 24),
              ],

              // ==================== СКАНИРОВАНИЕ ====================
              if (_isScanning && _newDevices.isEmpty && _pairedDevices.isEmpty && _connectedToDeviceWifi == null) ...[
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Поиск устройств...'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ==================== НЕТ УСТРОЙСТВ ====================
              if (!_isScanning && _newDevices.isEmpty && _pairedDevices.isEmpty && _connectedToDeviceWifi == null) ...[
                _buildNoDevicesCard(),
                const SizedBox(height: 24),
              ],

              // ==================== РУЧНОЕ ПОДКЛЮЧЕНИЕ ====================
              _buildManualConnectionCard(appState),
            ],
          ),
        ),
      ),
    );
  }

  /// Карточка прямого подключения к WiFi устройства
  Widget _buildDirectConnectionCard(AppState appState) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.usb, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Прямое подключение', style: TextStyle(fontSize: 12)),
                      Text(
                        _connectedToDeviceWifi!.ssid,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                _buildSignalIcon(_connectedToDeviceWifi!.signalBars),
              ],
            ),
            const SizedBox(height: 16),
            
            // Две кнопки: Настройка и Открыть файлы
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openSetupScreen(_connectedToDeviceWifi!.ssid),
                    icon: const Icon(Icons.settings),
                    label: const Text('Настроить'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: appState.isConnecting
                        ? null
                        : () => _connectToDevice(appState, '192.168.4.1'),
                    icon: appState.isConnecting
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.folder_open),
                    label: Text(appState.isConnecting ? 'Подключение...' : 'Файлы'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Карточка сопряжённых устройств
  Widget _buildPairedDevicesCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Мои устройства', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_isScanning)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            
            ..._pairedDevices.map((device) => _buildPairedDeviceTile(device, appState)),
          ],
        ),
      ),
    );
  }

  Widget _buildPairedDeviceTile(DiscoveredDevice device, AppState appState) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: device.isOnline 
              ? Colors.green.shade100 
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.usb,
          color: device.isOnline ? Colors.green : Colors.grey,
        ),
      ),
      title: Text(device.displayName),
      subtitle: Text(
        device.isOnline 
            ? 'Онлайн • ${device.ip}' 
            : 'Не в сети',
        style: TextStyle(
          color: device.isOnline ? Colors.green : Colors.grey,
        ),
      ),
      trailing: device.isOnline
          ? FilledButton(
              onPressed: appState.isConnecting
                  ? null
                  : () => _connectToDevice(appState, device.ip),
              child: const Text('Открыть'),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'remove') {
                  _removePairedDevice(device);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Удалить'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Карточка новых устройств (WiFi точки доступа)
  Widget _buildNewDevicesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_find, color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 8),
                Text('Новые устройства', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите чтобы подключиться и настроить',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 12),
            
            ..._newDevices.map((device) => ListTile(
              leading: const Icon(Icons.usb),
              title: Text(device.ssid),
              subtitle: const Text('Требуется настройка'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSignalIcon(device.signalBars),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
              onTap: () => _connectToNewDevice(device),
            )),
          ],
        ),
      ),
    );
  }

  /// Карточка "Нет устройств"
  Widget _buildNoDevicesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.devices, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('Устройства не найдены', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Убедитесь, что устройство WirelessFlash включено',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _scanForDevices,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить поиск'),
            ),
          ],
        ),
      ),
    );
  }

  /// Карточка ручного подключения
  Widget _buildManualConnectionCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit, color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 8),
                Text('Ввести IP вручную', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP адрес устройства',
                hintText: '192.168.4.1',
                prefixIcon: Icon(Icons.router),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: appState.isConnecting
                    ? null
                    : () => _connectToDevice(appState, _ipController.text),
                icon: appState.isConnecting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Подключиться'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalIcon(int bars) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        return Container(
          width: 4,
          height: 6.0 + (index * 4),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: index < bars
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  Future<void> _connectToDevice(AppState appState, String ip) async {
    await appState.connectToDevice(ip);
  }

  /// Подключение к новому устройству через WiFi
  Future<void> _connectToNewDevice(DiscoveredDevice device) async {
    final passwordController = TextEditingController(text: '12345678');
    bool isConnecting = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.wifi),
              const SizedBox(width: 8),
              Expanded(child: Text(device.ssid)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isConnecting) ...[
                const Text('Введите пароль устройства:'),
                const SizedBox(height: 8),
                Text(
                  'Заводской пароль: 12345678',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
              ] else ...[
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Подключение к устройству...'),
                      SizedBox(height: 8),
                      Text(
                        'Это может занять несколько секунд',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!isConnecting) ...[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  setDialogState(() => isConnecting = true);
                  
                  final success = await WifiScanner.connectToWifi(
                    device.ssid,
                    passwordController.text,
                  );

                  if (!context.mounted) return;
                  
                  if (success) {
                    Navigator.pop(context, true);
                  } else {
                    setDialogState(() => isConnecting = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Не удалось подключиться. Проверьте пароль.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.wifi),
                label: const Text('Подключиться'),
              ),
            ],
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      // Успешно подключились к WiFi устройства
      await Future.delayed(const Duration(seconds: 1));
      await _scanForDevices();
      
      // Открываем экран настройки
      if (_connectedToDeviceWifi != null) {
        _openSetupScreen(device.ssid);
      }
    }
  }

  /// Открыть экран настройки устройства
  Future<void> _openSetupScreen(String ssid) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SetupScreen(deviceSsid: ssid),
      ),
    );

    if (result == true && mounted) {
      // Настройка завершена, предлагаем вернуться в домашнюю сеть
      _showReturnToHomeNetworkDialog();
    }
  }

  /// Диалог возврата в домашнюю сеть
  void _showReturnToHomeNetworkDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Устройство настроено!'),
        content: const Text(
          'Теперь подключитесь к своей домашней WiFi сети, чтобы управлять устройством.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _openWifiSettings();
            },
            child: const Text('Открыть настройки WiFi'),
          ),
        ],
      ),
    );
  }

  /// Удалить сопряжённое устройство
  Future<void> _removePairedDevice(DiscoveredDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить устройство?'),
        content: Text('Устройство "${device.displayName}" будет удалено из списка.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true && device.deviceId != null) {
      await WifiScanner.removePairedDevice(device.deviceId!);
      await _scanForDevices();
    }
  }

  Future<void> _openWifiSettings() async {
    if (!kIsWeb) {
      try {
        await Process.run('explorer', ['ms-settings:network-wifi']);
      } catch (e) {
        debugPrint('Could not open WiFi settings: $e');
      }
    }
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Wireless Flash',
      applicationVersion: '2.0.0',
      applicationIcon: const Icon(Icons.usb, size: 48),
      children: [
        const Text('Приложение для управления беспроводными флешками на базе ESP32.'),
        const SizedBox(height: 16),
        const Text('© 2025 Wireless Flash', style: TextStyle(fontSize: 12)),
      ],
    );
  }
}
