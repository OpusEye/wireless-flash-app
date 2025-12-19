import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/wifi_network.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _passwordController = TextEditingController();
  String? _selectedSsid;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    // Запускаем сканирование при открытии
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().scanWifi();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки WiFi'),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Текущее подключение
                _buildCurrentConnectionCard(appState),
                const SizedBox(height: 24),
                
                // Доступные сети
                _buildAvailableNetworksCard(appState),
                const SizedBox(height: 24),
                
                // Форма подключения
                if (_selectedSsid != null)
                  _buildConnectForm(appState),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCurrentConnectionCard(AppState appState) {
    final device = appState.currentDevice;
    final isConnectedToHome = device?.staIp != null && device!.staIp!.isNotEmpty;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnectedToHome ? Icons.home : Icons.wifi_tethering,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Текущее подключение',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            
            // Точка доступа
            _buildInfoRow(
              'Точка доступа',
              'WirelessFlash (192.168.4.1)',
              Icons.wifi_tethering,
            ),
            
            // Домашняя сеть
            if (isConnectedToHome) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                'Домашняя сеть',
                '${device.staSSID} (${device.staIp})',
                Icons.home,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.link_off),
                  label: const Text('Отключиться от домашней сети'),
                  onPressed: () => _disconnectFromHome(appState),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                'Домашняя сеть',
                'Не подключено',
                Icons.home_outlined,
                isWarning: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Подключите устройство к домашней сети, чтобы получить доступ к нему с любого устройства в вашей сети.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, {bool isWarning = false}) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isWarning 
              ? Theme.of(context).colorScheme.outline 
              : Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isWarning ? Theme.of(context).colorScheme.outline : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvailableNetworksCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_find,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Доступные сети',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (appState.isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => appState.scanWifi(),
                    tooltip: 'Обновить',
                  ),
              ],
            ),
            const Divider(),
            
            if (appState.isScanning && appState.wifiNetworks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Сканирование сетей...'),
                    ],
                  ),
                ),
              )
            else if (appState.wifiNetworks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      const Text('Сети не найдены'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Повторить сканирование'),
                        onPressed: () => appState.scanWifi(),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: appState.wifiNetworks.length,
                itemBuilder: (context, index) {
                  final network = appState.wifiNetworks[index];
                  return _buildNetworkItem(network);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkItem(WifiNetwork network) {
    final isSelected = _selectedSsid == network.ssid;
    
    return ListTile(
      leading: Icon(
        network.isSecure ? Icons.wifi_lock : Icons.wifi,
        color: isSelected 
            ? Theme.of(context).colorScheme.primary 
            : null,
      ),
      title: Text(
        network.ssid,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      subtitle: Text(
        'Сигнал: ${network.signalBars}  ${network.rssi} dBm',
      ),
      trailing: network.isConnected
          ? Chip(
              label: const Text('Подключено'),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            )
          : isSelected
              ? const Icon(Icons.check_circle)
              : null,
      selected: isSelected,
      onTap: () {
        setState(() {
          _selectedSsid = network.ssid;
          _passwordController.clear();
        });
      },
    );
  }

  Widget _buildConnectForm(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.vpn_key,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Подключиться к $_selectedSsid',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль WiFi',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedSsid = null;
                    });
                  },
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.wifi),
                  label: Text(_isConnecting ? 'Подключение...' : 'Подключить'),
                  onPressed: _isConnecting
                      ? null
                      : () => _connectToNetwork(appState),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectToNetwork(AppState appState) async {
    if (_selectedSsid == null) return;
    
    setState(() {
      _isConnecting = true;
    });
    
    final result = await appState.api.connectToWifiWithDetails(
      _selectedSsid!,
      _passwordController.text,
    );
    
    setState(() {
      _isConnecting = false;
    });
    
    if (mounted) {
      final success = result['success'] == true;
      final message = result['message'] ?? '';
      final ip = result['ip'] ?? '';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Подключено к $_selectedSsid! IP: $ip'
              : 'Ошибка: $message'),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      
      if (success) {
        setState(() {
          _selectedSsid = null;
        });
        // Обновляем статус устройства
        await appState.refreshDeviceStatus();
        await appState.scanWifi();
      }
    }
  }

  Future<void> _disconnectFromHome(AppState appState) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отключиться от домашней сети?'),
        content: const Text(
          'Устройство будет отключено от домашней сети. '
          'Для доступа к нему нужно будет подключиться напрямую к WiFi "WirelessFlash".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      final success = await appState.disconnectFromWifi();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Отключено от домашней сети'
                : 'Ошибка отключения'),
          ),
        );
      }
    }
  }
}
