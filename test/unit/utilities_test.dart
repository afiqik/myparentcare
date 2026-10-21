
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:image/image.dart' as img;
import 'package:my_parent_care/api/file_export.dart';
import 'package:my_parent_care/app_config.dart';
import 'package:my_parent_care/auth/google_auth_adapter.dart';
import 'package:my_parent_care/cache_cdn/cache_manager.dart';
import 'package:my_parent_care/cache_cdn/image_compressor.dart';
import 'package:my_parent_care/core/errors.dart';
import 'package:my_parent_care/database_storage/firestore_paths.dart';
import 'package:my_parent_care/error_tracking/error_tracker.dart';

import '../support/platform_fakes.dart';

Uint8List png(int width, int height, {bool noisy = false}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = noisy ? (x * 7919 + y * 104729) % 256 : (x + y) % 256;
      image.setPixelRgb(x, y, v, (v * 3) % 256, (v * 5) % 256);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('friendlyError: mesej ralat mesra pengguna', () {
    test('ralat Firebase Auth', () {
      String auth(String code) => friendlyError(FirebaseAuthException(code: code));
      expect(auth('network-request-failed'), contains('No internet'));
      expect(auth('user-disabled'), contains('disabled'));
      expect(auth('invalid-credential'), contains('incorrect'));
      expect(auth('too-many-requests'), contains('Too many attempts'));
      expect(auth('requires-recent-login'), contains('sign in again'));
      expect(auth('account-exists-with-different-credential'), contains('another sign-in'));
      expect(auth('popup-closed-by-user'), 'Sign-in was cancelled.');
      expect(auth('unauthorized-domain'), contains('not authorised'));
      expect(friendlyError(FirebaseAuthException(code: 'weird', message: 'Custom')), 'Custom');
      expect(friendlyError(FirebaseAuthException(code: 'weird')), contains('(weird)'));
    });

    test('Google Sign-In: error 10 (SHA-1), rangkaian, dibatalkan', () {
      expect(friendlyError(PlatformException(code: 'sign_in_failed', message: 'ApiException: 10: ')),
          contains('error 10'));
      expect(friendlyError(PlatformException(code: 'network_error')), contains('Google could not connect'));
      expect(friendlyError(PlatformException(code: 'sign_in_canceled')), 'Sign-in was cancelled.');
      expect(friendlyError(PlatformException(code: 'x'), google: true), 'Google sign-in failed (x).');
      expect(friendlyError(PlatformException(code: 'x')), 'Something went wrong (x).');
    });

    test('ralat Firestore termasuk kuota percuma habis', () {
      String fs(String code) => friendlyError(FirebaseException(plugin: 'cloud_firestore', code: code));
      expect(fs('permission-denied'), contains('permission'));
      expect(fs('unavailable'), contains('temporarily unavailable'));
      expect(fs('resource-exhausted'), contains('daily free quota'));
      expect(fs('not-found'), contains('no longer exists'));
      expect(friendlyError(FirebaseException(plugin: 'p', code: 'x', message: 'Detail')), 'Detail');
    });

    test('StateError, ArgumentError, FormatException dan lain-lain', () {
      expect(friendlyError(StateError('Profil tidak lengkap')), 'Profil tidak lengkap');
      expect(friendlyError(ArgumentError('Pautan salah')), 'Pautan salah');
      expect(friendlyError(const FormatException('Bukan backup')), 'Bukan backup');
      expect(friendlyError(Exception('boom')), 'Something went wrong. Please try again.');
      expect(friendlyError(Exception('boom'), google: true), contains('Google sign-in could not continue'));
    });
  });

  group('ErrorTracker: laporan ralat ke Firestore (dengan had kuota)', () {
    late FakeFirebaseFirestore db;
    String? uid;

    setUp(() {
      ErrorTracker().reset();
      db = FakeFirebaseFirestore();
      uid = 'stu1';
      ErrorTracker().configure(firestore: db, currentUid: () => uid, appVersion: '1.0.0+6');
    });

    tearDown(() => ErrorTracker().reset());

    Future<List<Map<String, dynamic>>> reports() async =>
        (await db.collection(FirestorePaths.errorReports).get()).docs.map((d) => d.data()).toList();

    test('ralat dilaporkan dengan medan yang dibenarkan oleh rules', () async {
      await ErrorTracker().logError('Join failed', error: StateError('x'), stackTrace: StackTrace.current);
      final saved = (await reports()).single;
      expect(saved.keys.toSet(),
          {'message', 'error', 'stackTrace', 'platform', 'appVersion', 'uid', 'createdAt'});
      expect(saved['message'], 'Join failed');
      expect(saved['uid'], 'stu1');
      expect(saved['appVersion'], '1.0.0+6');
      expect(saved['createdAt'], isA<Timestamp>());
    });

    test('mesej panjang dipotong; ralat sama tidak dihantar semula dalam 5 minit', () async {
      await ErrorTracker().logError('A' * 900, error: 'e' * 5000);
      await ErrorTracker().logError('A' * 900, error: 'e' * 5000);
      final saved = await reports();
      expect(saved, hasLength(1));
      expect((saved.single['message'] as String).length, 500);
      expect((saved.single['error'] as String).length, 2000);
    });

    test('maksimum 20 laporan setiap sesi; tiada laporan tanpa log masuk', () async {
      for (var i = 0; i < 30; i++) {
        await ErrorTracker().logError('Error $i');
      }
      expect(await reports(), hasLength(ErrorTracker.maxReportsPerSession));

      ErrorTracker().reset();
      uid = null;
      ErrorTracker().configure(firestore: db, currentUid: () => uid);
      await ErrorTracker().logError('anonymous');
      expect(await reports(), hasLength(ErrorTracker.maxReportsPerSession));
      ErrorTracker().logWarning('only local');
    });

    test('tanpa konfigurasi: log tempatan sahaja, tiada ralat', () async {
      ErrorTracker().reset();
      await ErrorTracker().logError('no firestore');
      expect(await reports(), isEmpty);
      expect(ErrorTracker.platform, isNotEmpty);
    });
  });

  group('ImageCompressor: gambar muat dalam satu dokumen Firestore', () {
    test('gambar kecil → JPEG, saiz asal dikekalkan', () {
      final result = ImageCompressor.compressSync(png(120, 80));
      expect(result.contentType, 'image/jpeg');
      expect(result.width, 120);
      expect(result.height, 80);
      expect(result.bytes.length, lessThanOrEqualTo(AppConfig.maxImageBytes));
      expect(img.decodeJpg(result.bytes), isNotNull);
    });

    test('gambar besar dikecilkan kepada maksimum 1600 piksel (landskap & potret)', () {
      final wide = ImageCompressor.compressSync(png(3200, 1600));
      expect(wide.width, AppConfig.maxImageDimension);
      expect(wide.height, 800);
      final tall = ImageCompressor.compressSync(png(1000, 2400));
      expect(tall.height, AppConfig.maxImageDimension);
      expect(tall.width, lessThan(AppConfig.maxImageDimension));
    });

    test('gambar "bising" besar dimampatkan berperingkat sehingga < 900 KB', () {
      final result = ImageCompressor.compressSync(png(1600, 1600, noisy: true));
      expect(result.bytes.length, lessThanOrEqualTo(AppConfig.maxImageBytes));
    });

    test('fail bukan gambar ditolak dengan mesej jelas', () {
      expect(
        () => ImageCompressor.compressSync(Uint8List.fromList(List.filled(64, 7))),
        throwsA(isA<FormatException>()),
      );
    });

    test('compress() (isolate) memberi keputusan sama', () async {
      final result = await ImageCompressor.compress(png(64, 64));
      expect(result.width, 64);
    });
  });

  group('FileExport: kongsi/simpan fail melalui helaian kongsi sistem', () {
    test('CSV dihantar dengan nama, jenis dan kandungan yang betul', () async {
      final fakes = PlatformFakes.install();
      await FileExport.save(
        bytes: Uint8List.fromList('a,b\n1,2'.codeUnits),
        fileName: 'report.csv',
        mimeType: 'text/csv',
        subject: 'Laporan',
      );
      final params = fakes.share.shared.single;
      expect(params.subject, 'Laporan');
      expect(fakes.share.lastName, 'report.csv');
      expect(params.files!.single.mimeType, 'text/csv');
      expect(String.fromCharCodes(await fakes.share.lastBytes()), 'a,b\n1,2');
    });

    test('ralat helaian kongsi disampaikan kepada pemanggil', () async {
      final fakes = PlatformFakes.install()..share.fail = true;
      expect(
        FileExport.save(bytes: Uint8List(1), fileName: 'x.pdf', mimeType: 'application/pdf'),
        throwsStateError,
      );
      expect(fakes.share.shared, isEmpty);
    });
  });

  group('DefaultGoogleAuthAdapter (plugin google_sign_in)', () {
    late PlatformFakes fakes;

    setUp(() => fakes = PlatformFakes.install());

    test('log masuk: pemilih akaun dipaparkan, token ditukar kepada Firebase credential', () async {
      final auth = MockFirebaseAuth();
      final credential = await DefaultGoogleAuthAdapter().signIn(auth);
      expect(credential, isNotNull);
      expect(auth.currentUser, isNotNull);
      expect(fakes.googleSignIn.signOuts, 1, reason: 'sesi lama dikosongkan dahulu');
      expect(fakes.googleSignIn.signIns, 1);
      expect(fakes.googleSignIn.initParams!.serverClientId, AppConfig.googleServerClientId);
      expect(fakes.googleSignIn.initParams!.scopes, contains('email'));
    });

    test('dibatalkan → null; tiada ID token → ralat jelas (SHA-1)', () async {
      fakes.googleSignIn.user = null;
      expect(await DefaultGoogleAuthAdapter().signIn(MockFirebaseAuth()), isNull);

      fakes.googleSignIn
        ..user = GoogleSignInUserData(email: 'aina@gmail.com', id: 'g-1')
        ..tokens = GoogleSignInTokenData(accessToken: 'access-only');
      expect(
        DefaultGoogleAuthAdapter().signIn(MockFirebaseAuth()),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('SHA-1'))),
      );
    });

    test('sahkan semula (padam akaun) & log keluar', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1', email: 'aina@gmail.com'), signedIn: true);
      final adapter = DefaultGoogleAuthAdapter();
      await adapter.reauthenticate(auth.currentUser!);
      await adapter.signOut();
      expect(fakes.googleSignIn.signOuts, 1);

      fakes.googleSignIn.user = null;
      expect(adapter.reauthenticate(auth.currentUser!), throwsStateError);
    });
  });

  group('CacheManager', () {
    test('tetapan cache Firestore 100 MB tidak membaling ralat', () {
      final db = FakeFirebaseFirestore();
      expect(() => CacheManager.configureFirestore(db), returnsNormally);
      expect(CacheManager.firestoreCacheBytes, 100 * 1024 * 1024);
    });
  });
}
