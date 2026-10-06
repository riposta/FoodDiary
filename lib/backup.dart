import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';

// ponytail: backup = baza + zdjęcia; profil i klucz API wpisuje się ponownie po odtworzeniu
Future<void> exportBackup() async {
  final tmp = await getTemporaryDirectory();
  final zipPath = '${tmp.path}/dzienniczek_kopia_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.zip';
  await Db.close(); // spójna kopia pliku bazy
  try {
    final enc = ZipFileEncoder()..create(zipPath);
    await enc.addFile(File(Db.dbPath), 'food_diary.db');
    await enc.addDirectory(Directory(Db.photosDir));
    await enc.close();
  } finally {
    await Db.open();
  }
  await Share.shareXFiles([XFile(zipPath)], subject: 'Kopia zapasowa dzienniczka');
}

/// Zwraca false, gdy użytkownik anulował wybór pliku.
Future<bool> importBackup() async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
  final path = picked?.files.single.path;
  if (path == null) return false;

  // Najpierw rozpakuj i sprawdź poza danymi aplikacji — uszkodzony plik niczego nie psuje.
  final tmp = Directory('${(await getTemporaryDirectory()).path}/restore');
  if (await tmp.exists()) await tmp.delete(recursive: true);
  await tmp.create();
  try {
    await extractFileToDisk(path, tmp.path);
    final db = File('${tmp.path}/food_diary.db');
    if (!await db.exists()) throw Exception('Plik nie jest kopią zapasową dzienniczka.');
    final check = await openDatabase(db.path, readOnly: true, singleInstance: false);
    try {
      await check.query('entries', limit: 1);
    } catch (_) {
      throw Exception('Kopia zapasowa jest uszkodzona.');
    } finally {
      await check.close();
    }

    await Db.close();
    try {
      await db.copy(Db.dbPath);
      final photos = Directory(Db.photosDir);
      await photos.delete(recursive: true);
      await photos.create();
      final src = Directory('${tmp.path}/photos');
      if (await src.exists()) {
        await for (final f in src.list()) {
          if (f is File) await f.copy('${photos.path}/${f.uri.pathSegments.last}');
        }
      }
    } finally {
      await Db.open();
    }
    return true;
  } finally {
    await tmp.delete(recursive: true);
  }
}
