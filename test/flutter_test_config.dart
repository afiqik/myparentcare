import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dijalankan sebelum setiap fail ujian. Fon sebenar aplikasi (Manrope)
/// dimuatkan supaya saiz teks – dan pengesanan limpahan (overflow) – sama
/// seperti di telefon, bukan fon ujian lalai yang setiap hurufnya kotak penuh.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manrope = FontLoader('Manrope')
    ..addFont(rootBundle.load('assets/fonts/Manrope-VariableFont_wght.ttf'));
  await manrope.load();
  await testMain();
}
