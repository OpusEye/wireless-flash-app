import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/device_api.dart';
import '../services/wifi_scanner.dart';

/// Экран первичной настройки устройства WirelessFlash
/// Показывается после прямого подключения к WiFi устройства
class SetupScreen extends StatefulWidget {
  final String deviceSsid;
  
  const SetupScreen({super.key, required this.deviceSsid});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _deviceNameController = TextEditingController(text: 'Моя флешка');
  
  List<String> _availableNetworks = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _showPassword = false;
  String? _error;
  DeviceStatus? _deviceStatus;
  
  // Этапы настройки
  int _currentStep = 0;
  bool _setupComplete = false;
  String? _homeNetworkIp;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final api = DeviceApi('192.168.4.1');
      final status = await api.getStatus();
      if (mounted) {
        setState(() {
          _deviceStatus = status;
          // Если устройство уже подключено к сети, показываем это
          if (status.staIp != null && status.staIp!.isNotEmpty && status.staIp != '0.0.0.0') {
            _homeNetworkIp = status.staIp;
            _ssidController.text = status.staSsid ?? '';
          }
        });
        // Загружаем список сетей
        _scanNetworks();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось подключиться к устройству: $e');
      }
    }
  }

  Future<void> _scanNetworks() async {
    setState(() {
      _isScanning = true;
      _error = null;
    });

    try {
      final api = DeviceApi('192.168.4.1');
      final networks = await api.scanWifiNetworks();
      if (mounted) {
        setState(() {
          _availableNetworks = networks;
          _isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _error = 'Ошибка сканирования сетей: $e';
        });
      }
    }
  }

  Future<void> _connectToNetwork() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final api = DeviceApi('192.168.4.1');
      final result = await api.connectToWifi(
        _ssidController.text,
        _passwordController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          // API возвращает "ip", а не "staIp"
          final staIp = result['ip'] as String?;
          
          if (staIp != null && staIp.isNotEmpty && staIp != '0.0.0.0') {
            // Успешно подключились!
            setState(() {
              _homeNetworkIp = staIp;
              _currentStep = 1;
              _isConnecting = false;
            });
          } else {
            setState(() {
              _error = 'Устройство не получило IP адрес. Проверьте пароль.';
              _isConnecting = false;
            });
          }
        } else {
          setState(() {
            _error = result['message'] ?? 'Не удалось подключиться к сети';
            _isConnecting = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _error = 'Ошибка: $e';
        });
      }
    }
  }

  Future<void> _completeSetup() async {
    if (_homeNetworkIp == null) return;

    // Сохраняем устройство как сопряжённое
    final deviceId = _deviceStatus?.deviceId ?? widget.deviceSsid;
    
    await WifiScanner.savePairedDevice(PairedDevice(
      deviceId: deviceId,
      ssid: widget.deviceSsid,
      friendlyName: _deviceNameController.text,
      lastKnownIp: _homeNetworkIp,
      lastSeen: DateTime.now(),
    ));

    setState(() => _setupComplete = true);

    // Показываем сообщение и ждём
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      // Возвращаемся на главный экран
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройка устройства'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _setupComplete ? _buildCompleteScreen() : _buildSetupContent(),
    );
  }

  Widget _buildCompleteScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 64, color: Colors.green),
          ),
          const SizedBox(height: 24),
          Text(
            'Устройство настроено!',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Теперь вы можете подключиться к домашней сети\nи управлять устройством через приложение',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 16),
          Text(
            'IP адрес: $_homeNetworkIp',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildSetupContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Прогресс
          _buildProgressIndicator(),
          const SizedBox(height: 32),

          // Информация об устройстве
          _buildDeviceInfo(),
          const SizedBox(height: 24),

          // Ошибка
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Контент в зависимости от шага
          if (_currentStep == 0) _buildNetworkSetup(),
          if (_currentStep == 1) _buildDeviceNaming(),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: [
        _buildStepCircle(0, 'Сеть'),
        Expanded(child: Container(height: 2, color: _currentStep >= 1 ? Theme.of(context).colorScheme.primary : Colors.grey.shade300)),
        _buildStepCircle(1, 'Имя'),
      ],
    );
  }

  Widget _buildStepCircle(int step, String label) {
    final isActive = _currentStep >= step;
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isActive
                ? (step < _currentStep
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : Text('${step + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                : Text('${step + 1}', style: const TextStyle(color: Colors.grey)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey)),
      ],
    );
  }

  Widget _buildDeviceInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.usb, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.deviceSsid, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (_deviceStatus != null) ...[
                    Text(
                      'SD карта: ${_deviceStatus!.sdTotalMb > 0 ? '${(_deviceStatus!.sdTotalMb / 1024).toStringAsFixed(1)} ГБ' : 'не найдена'}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ),
            if (_deviceStatus != null)
              const Icon(Icons.check_circle, color: Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkSetup() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Подключите устройство к домашней сети',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'После этого вы сможете управлять устройством из своей сети',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 24),

          // Выбор сети
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.wifi),
                      const SizedBox(width: 8),
                      const Text('Доступные сети', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_isScanning)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _scanNetworks,
                          tooltip: 'Обновить',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  if (_availableNetworks.isEmpty && !_isScanning)
                    const Text('Сети не найдены', style: TextStyle(color: Colors.grey))
                  else
                    ...List.generate(_availableNetworks.length.clamp(0, 10), (i) {
                      final network = _availableNetworks[i];
                      final isSelected = _ssidController.text == network;
                      return ListTile(
                        leading: const Icon(Icons.wifi),
                        title: Text(network),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
                        selected: isSelected,
                        onTap: () => setState(() => _ssidController.text = network),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Ввод данных
          TextFormField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'Название сети (SSID)',
              prefixIcon: Icon(Icons.wifi),
              border: OutlineInputBorder(),
            ),
            validator: (v) => v == null || v.isEmpty ? 'Введите название сети' : null,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _passwordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Пароль WiFi',
              prefixIcon: const Icon(Icons.lock),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) => v == null || v.length < 8 ? 'Минимум 8 символов' : null,
          ),
          const SizedBox(height: 24),

          // Кнопка подключения
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isConnecting ? null : _connectToNetwork,
              icon: _isConnecting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.wifi),
              label: Text(_isConnecting ? 'Подключение...' : 'Подключить к сети'),
            ),
          ),

          // Если уже подключено
          if (_homeNetworkIp != null && _currentStep == 0) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Уже подключено к сети', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('IP: $_homeNetworkIp'),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _currentStep = 1),
                      child: const Text('Далее'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceNaming() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Назовите устройство',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Это имя будет отображаться в списке устройств',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 24),

        // Успешное подключение
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Подключено к ${_ssidController.text}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('IP адрес: $_homeNetworkIp'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        TextField(
          controller: _deviceNameController,
          decoration: const InputDecoration(
            labelText: 'Имя устройства',
            prefixIcon: Icon(Icons.edit),
            border: OutlineInputBorder(),
            hintText: 'Например: Моя флешка',
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _completeSetup,
            icon: const Icon(Icons.check),
            label: const Text('Завершить настройку'),
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => setState(() => _currentStep = 0),
            child: const Text('Назад'),
          ),
        ),
      ],
    );
  }
}
