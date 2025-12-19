import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/app_state.dart';
import '../models/file_item.dart';
import 'settings_screen.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  bool _isOperationInProgress = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Column(
          children: [
            _buildDeviceInfoBar(context, appState),
            _buildNavigationBar(context, appState),
            if (appState.hasSelection)
              _buildSelectionBar(context, appState),
            Expanded(
              child: appState.isLoadingFiles
                  ? const Center(child: CircularProgressIndicator())
                  : _buildFileList(context, appState),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceInfoBar(BuildContext context, AppState appState) {
    final device = appState.currentDevice;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Row(
        children: [
          const Icon(Icons.usb, size: 20),
          const SizedBox(width: 8),
          Text(device?.displayName ?? 'WirelessFlash', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (device?.storageInfo != null) ...[
            const Icon(Icons.sd_card, size: 16),
            const SizedBox(width: 4),
            Text(device!.storageInfo, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.settings, size: 20),
            onPressed: () => _openSettings(context),
            tooltip: 'Настройки WiFi',
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => appState.disconnect(),
            tooltip: 'Отключиться',
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar(BuildContext context, AppState appState) {
    final pathParts = appState.currentPath.split('/').where((p) => p.isNotEmpty).toList();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: appState.currentPath == '/' ? null : () => appState.navigateBack(),
            tooltip: 'Назад',
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.home, size: 18),
                    label: const Text('Корень'),
                    onPressed: () => appState.loadFiles('/'),
                  ),
                  for (int i = 0; i < pathParts.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 16),
                    TextButton(
                      onPressed: () {
                        final path = '/${pathParts.sublist(0, i + 1).join('/')}';
                        appState.loadFiles(path);
                      },
                      child: Text(pathParts[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => appState.loadFiles(appState.currentPath),
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            onPressed: () => _showCreateFolderDialog(context, appState),
            tooltip: 'Новая папка',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.upload),
            tooltip: 'Загрузить',
            onSelected: (value) {
              if (value == 'files') {
                _uploadFiles(context, appState);
              } else if (value == 'folder') {
                _uploadFolder(context, appState);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'files', child: Row(children: [Icon(Icons.file_upload), SizedBox(width: 8), Text('Загрузить файлы')])),
              const PopupMenuItem(value: 'folder', child: Row(children: [Icon(Icons.folder_open), SizedBox(width: 8), Text('Загрузить папку')])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context, AppState appState) {
    final hasDirectories = appState.files.any((f) => f.isDirectory && appState.selectedFiles.contains(f.path));
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer),
      child: Row(
        children: [
          Text('Выбрано: ${appState.selectedFiles.length}', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          TextButton.icon(icon: const Icon(Icons.select_all), label: const Text('Все'), onPressed: appState.selectAll),
          TextButton.icon(icon: const Icon(Icons.deselect), label: const Text('Снять'), onPressed: appState.clearSelection),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: Text(hasDirectories ? 'Скачать (с папками)' : 'Скачать'),
            onPressed: _isOperationInProgress ? null : () => _downloadSelected(context, appState),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.delete),
            label: const Text('Удалить'),
            onPressed: _isOperationInProgress ? null : () => _deleteSelected(context, appState),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(BuildContext context, AppState appState) {
    if (appState.files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('Папка пуста', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 8),
            FilledButton.icon(icon: const Icon(Icons.upload_file), label: const Text('Загрузить файлы'), onPressed: () => _uploadFiles(context, appState)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: appState.files.length,
      itemBuilder: (context, index) => _buildFileItem(context, appState, appState.files[index]),
    );
  }

  Widget _buildFileItem(BuildContext context, AppState appState, FileItem file) {
    final isSelected = appState.selectedFiles.contains(file.path);
    
    return ListTile(
      leading: Text(file.icon, style: const TextStyle(fontSize: 28)),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: file.isDirectory ? null : Text(file.sizeFormatted, style: Theme.of(context).textTheme.bodySmall),
      trailing: Checkbox(
        value: isSelected,
        onChanged: (_) => appState.toggleFileSelection(file.path),
      ),
      selected: isSelected,
      onTap: () {
        if (file.isDirectory) {
          appState.navigateToFolder(file.name);
        } else {
          appState.toggleFileSelection(file.path);
        }
      },
      onLongPress: () => appState.toggleFileSelection(file.path),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SettingsScreen()));
  }

  Future<void> _showCreateFolderDialog(BuildContext context, AppState appState) async {
    final controller = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать папку'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Имя папки', hintText: 'Новая папка')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Создать')),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty && mounted) {
      final success = await appState.createFolder(result);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка создания папки'), backgroundColor: Colors.red));
      }
    }
    controller.dispose();
  }

  Future<void> _uploadFiles(BuildContext context, AppState appState) async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
      if (result == null || result.files.isEmpty) return;
      
      final files = result.paths.where((p) => p != null).map((p) => File(p!)).toList();
      if (files.isEmpty) return;
      
      if (!mounted) return;
      await _doUpload(context, appState, files);
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _uploadFolder(BuildContext context, AppState appState) async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Выберите папку для загрузки');
      if (selectedDirectory == null) return;
      
      final dir = Directory(selectedDirectory);
      final files = <File>[];
      
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          files.add(entity);
        }
      }
      
      if (files.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Папка пуста')));
        return;
      }
      
      if (!mounted) return;
      await _doUpload(context, appState, files, basePath: selectedDirectory);
    } catch (e) {
      debugPrint('Upload folder error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _doUpload(BuildContext context, AppState appState, List<File> files, {String? basePath}) async {
    if (_isOperationInProgress) return;
    setState(() => _isOperationInProgress = true);
    
    int successCount = 0;
    int current = 0;
    bool cancelled = false;
    
    final api = appState.api;
    if (api == null) {
      setState(() => _isOperationInProgress = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Устройство не подключено'), backgroundColor: Colors.red));
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(children: [Icon(Icons.upload_file, color: Colors.blue), SizedBox(width: 8), Text('Загрузка')]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Файл $current из ${files.length}'),
                const SizedBox(height: 8),
                if (current < files.length)
                  Text(files[current].path.split(Platform.pathSeparator).last, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: files.isEmpty ? 0 : current / files.length),
                const SizedBox(height: 8),
                Text('${(files.isEmpty ? 0 : current / files.length * 100).toStringAsFixed(0)}%'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Отмена'),
              ),
            ],
          );
        },
      ),
    );
    
    try {
      for (int i = 0; i < files.length && !cancelled; i++) {
        current = i;
        
        // Определяем путь назначения
        String destPath = appState.currentPath;
        if (basePath != null) {
          // Сохраняем структуру папок
          final relativePath = files[i].parent.path.replaceFirst(basePath, '').replaceAll('\\', '/');
          if (relativePath.isNotEmpty) {
            destPath = appState.currentPath == '/' 
                ? relativePath 
                : '${appState.currentPath}$relativePath';
            // Создаём папки если нужно
            await api.createFolder(destPath);
          }
        }
        
        final success = await api.uploadFile(destPath, files[i]);
        if (success) successCount++;
      }
    } catch (e) {
      debugPrint('Upload exception: $e');
    }
    
    // Закрываем диалог если он ещё открыт
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    
    setState(() => _isOperationInProgress = false);
    await appState.loadFiles(appState.currentPath);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cancelled ? 'Отменено. Загружено $successCount' : 'Загружено $successCount из ${files.length}'),
          backgroundColor: successCount == files.length ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _downloadSelected(BuildContext context, AppState appState) async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Выберите папку для сохранения');
      if (selectedDirectory == null) return;
      
      final api = appState.api;
      if (api == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Устройство не подключено'), backgroundColor: Colors.red));
        return;
      }
      
      if (_isOperationInProgress) return;
      setState(() => _isOperationInProgress = true);
      
      // Собираем все файлы для скачивания (включая содержимое папок)
      final filesToDownload = <String>[];
      final selectedPaths = appState.selectedFiles.toList();
      
      for (final path in selectedPaths) {
        final file = appState.files.firstWhere((f) => f.path == path, orElse: () => FileItem(name: '', path: path, isDirectory: false, size: 0));
        if (file.isDirectory) {
          // Для папки получаем содержимое рекурсивно
          final folderFiles = await _getFilesInFolder(api, path);
          filesToDownload.addAll(folderFiles);
        } else {
          filesToDownload.add(path);
        }
      }
      
      if (filesToDownload.isEmpty) {
        setState(() => _isOperationInProgress = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет файлов для скачивания')));
        return;
      }
      
      int successCount = 0;
      int current = 0;
      bool cancelled = false;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(children: [Icon(Icons.download, color: Colors.green), SizedBox(width: 8), Text('Скачивание')]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Файл $current из ${filesToDownload.length}'),
                  const SizedBox(height: 8),
                  if (current < filesToDownload.length)
                    Text(filesToDownload[current].split('/').last, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: filesToDownload.isEmpty ? 0 : current / filesToDownload.length),
                  const SizedBox(height: 8),
                  Text('${(filesToDownload.isEmpty ? 0 : current / filesToDownload.length * 100).toStringAsFixed(0)}%'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelled = true;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Отмена'),
                ),
              ],
            );
          },
        ),
      );
      
      try {
        for (int i = 0; i < filesToDownload.length && !cancelled; i++) {
          current = i;
          final filePath = filesToDownload[i];
          
          final data = await api.downloadFile(filePath);
          if (data != null) {
            // Сохраняем с сохранением структуры папок
            final relativePath = filePath.startsWith('/') ? filePath.substring(1) : filePath;
            final destPath = '$selectedDirectory${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}';
            
            final destFile = File(destPath);
            await destFile.parent.create(recursive: true);
            await destFile.writeAsBytes(data);
            successCount++;
          }
        }
      } catch (e) {
        debugPrint('Download exception: $e');
      }
      
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      setState(() => _isOperationInProgress = false);
      appState.clearSelection();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cancelled ? 'Отменено. Скачано $successCount' : 'Скачано $successCount из ${filesToDownload.length}'),
            backgroundColor: successCount == filesToDownload.length ? Colors.green : Colors.orange,
            action: successCount > 0 ? SnackBarAction(
              label: 'Открыть',
              onPressed: () => Process.run('explorer', [selectedDirectory]),
            ) : null,
          ),
        );
      }
    } catch (e) {
      debugPrint('Download error: $e');
      setState(() => _isOperationInProgress = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<List<String>> _getFilesInFolder(dynamic api, String folderPath) async {
    final files = <String>[];
    try {
      final items = await api.listFiles(folderPath);
      for (final item in items) {
        if (item.isDirectory) {
          files.addAll(await _getFilesInFolder(api, item.path));
        } else {
          files.add(item.path);
        }
      }
    } catch (e) {
      debugPrint('Error listing folder $folderPath: $e');
    }
    return files;
  }

  Future<void> _deleteSelected(BuildContext context, AppState appState) async {
    final count = appState.selectedFiles.length;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить?'),
        content: Text('Удалить $count элементов? Папки будут удалены со всем содержимым.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    if (_isOperationInProgress) return;
    setState(() => _isOperationInProgress = true);
    
    final api = appState.api;
    if (api == null) {
      setState(() => _isOperationInProgress = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Устройство не подключено'), backgroundColor: Colors.red));
      return;
    }
    
    int successCount = 0;
    final paths = appState.selectedFiles.toList();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Удаление...'),
          ],
        ),
      ),
    );
    
    try {
      for (final path in paths) {
        final success = await api.deleteFile(path);
        if (success) successCount++;
      }
    } catch (e) {
      debugPrint('Delete exception: $e');
    }
    
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    
    setState(() => _isOperationInProgress = false);
    appState.clearSelection();
    await appState.loadFiles(appState.currentPath);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Удалено $successCount из ${paths.length}'),
          backgroundColor: successCount == paths.length ? Colors.green : Colors.orange,
        ),
      );
    }
  }
}
