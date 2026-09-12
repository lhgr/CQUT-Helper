import 'dart:io';

import 'package:cqut_helper/manager/schedule_background_file_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('保存新背景后可删除不同扩展名的旧背景副本', () async {
    final sourceDir = await Directory.systemTemp.createTemp(
      'cqut_background_source_',
    );
    final documentsDir = await Directory.systemTemp.createTemp(
      'cqut_background_documents_',
    );
    addTearDown(() async {
      if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
      if (await documentsDir.exists()) {
        await documentsDir.delete(recursive: true);
      }
    });
    final source = File('${sourceDir.path}${Platform.pathSeparator}crop.jpg');
    final oldBackground = File(
      '${documentsDir.path}${Platform.pathSeparator}schedule_background.png',
    );
    final unrelated = File(
      '${documentsDir.path}${Platform.pathSeparator}schedule_notes.txt',
    );
    await source.writeAsBytes([1, 2, 3]);
    await oldBackground.writeAsBytes([4, 5]);
    await unrelated.writeAsBytes([6]);

    final keptPath = await ScheduleBackgroundFileManager.copyToDirectory(
      source.path,
      documentsDir,
    );
    final removed = await ScheduleBackgroundFileManager.removeObsoleteIn(
      documentsDir,
      keeping: keptPath,
    );

    expect(removed, 1);
    expect(await File(keptPath).readAsBytes(), [1, 2, 3]);
    expect(await oldBackground.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test('移除背景会删除所有受管的持久背景文件', () async {
    final documentsDir = await Directory.systemTemp.createTemp(
      'cqut_background_remove_',
    );
    addTearDown(() async {
      if (await documentsDir.exists()) {
        await documentsDir.delete(recursive: true);
      }
    });
    final jpg = File(
      '${documentsDir.path}${Platform.pathSeparator}schedule_background.jpg',
    );
    final webp = File(
      '${documentsDir.path}${Platform.pathSeparator}schedule_background.webp',
    );
    await jpg.writeAsBytes([1]);
    await webp.writeAsBytes([2]);

    expect(
      await ScheduleBackgroundFileManager.removeObsoleteIn(documentsDir),
      2,
    );
    expect(await jpg.exists(), isFalse);
    expect(await webp.exists(), isFalse);
  });
}
