/// Модель файла/папки на устройстве
class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    final name = json['name'] ?? '';
    return FileItem(
      name: name,
      path: json['path'] ?? '/$name',
      isDirectory: json['isDir'] == true,
      size: json['size'] ?? 0,
      modified: json['modified'] != null 
          ? DateTime.fromMillisecondsSinceEpoch((json['modified'] as int) * 1000)
          : null,
    );
  }

  String get icon {
    if (isDirectory) return '📁';
    
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return '🖼️';
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return '🎵';
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'wmv':
        return '🎬';
      case 'pdf':
        return '📕';
      case 'doc':
      case 'docx':
        return '📄';
      case 'xls':
      case 'xlsx':
        return '📊';
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return '📦';
      case 'txt':
      case 'log':
        return '📝';
      case 'exe':
      case 'msi':
        return '⚙️';
      default:
        return '📄';
    }
  }

  String get sizeFormatted {
    if (isDirectory) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
