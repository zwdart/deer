import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const appFolderName = 'xin.dart.dchat';
const legacyFolderName = 'xin.dart.zchat';

class AppPaths {
  late String dataDir;
  late String downloadDir;
  late String picturesDir;
  late String cacheDir;
  late String imagesCacheDir;
  late String transfersCacheDir;
  String shareDir = '';
  String uploadDir = '';

  String get settingsPath => p.join(dataDir, 'settings.json');
  String get statePath => p.join(dataDir, 'state.json');
  String get databasePath => p.join(dataDir, 'dchat.db');
  String get rssDatabasePath => p.join(dataDir, 'dchat_rss.db');
  String get rssSettingsPath => p.join(dataDir, 'rss_settings.json');
  String get rssBackupDir => p.join(dataDir, 'rss_backups');
  String get rssExportDir => p.join(downloadDir, 'rss');
  String get transfersPath => p.join(dataDir, 'transfers-tcp.json');
  String get httpTransfersPath => p.join(dataDir, 'transfers.json');

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    dataDir = support.path;
    await Directory(dataDir).create(recursive: true);

    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } catch (_) {}
    downloads ??= await getApplicationDocumentsDirectory();
    downloadDir = p.join(downloads.path, appFolderName);

    Directory? pictures;
    try {
      pictures = await getExternalStorageDirectory();
    } catch (_) {}
    pictures ??= await getApplicationDocumentsDirectory();
    final publicPictures = Directory(p.join(pictures.path, 'Pictures'));
    if (await publicPictures.exists()) {
      picturesDir = p.join(publicPictures.path, appFolderName);
    } else {
      picturesDir = p.join(downloadDir, 'Screenshots');
    }

    cacheDir = p.join(dataDir, 'cache');
    imagesCacheDir = p.join(cacheDir, 'images');
    transfersCacheDir = p.join(cacheDir, 'transfers');
    await Directory(downloadDir).create(recursive: true);
    await Directory(imagesCacheDir).create(recursive: true);
    await Directory(transfersCacheDir).create(recursive: true);
  }

  void applySettingsDirs(String share, String upload, String screenshot) {
    shareDir = share;
    uploadDir = upload;
    if (screenshot.isNotEmpty) picturesDir = screenshot;
  }

  String defaultServerUploadDir() =>
      uploadDir.isNotEmpty ? uploadDir : p.join(dataDir, 'uploads');
}
