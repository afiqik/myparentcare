import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Helaian kongsi sistem tiruan: merekod fail yang dieksport (CSV/PDF/backup).
class FakeSharePlatform extends SharePlatform with MockPlatformInterfaceMixin {
  final List<ShareParams> shared = [];
  bool fail = false;

  @override
  Future<ShareResult> share(ShareParams params) async {
    if (fail) throw StateError('Share sheet unavailable');
    shared.add(params);
    return const ShareResult('dev.fluttercommunity.plus/share/success', ShareResultStatus.success);
  }

  /// Kandungan fail terakhir yang dikongsi.
  Future<Uint8List> lastBytes() => shared.last.files!.single.readAsBytes();
  String get lastName => shared.last.fileNameOverrides!.single;
}

/// Pemilih gambar tiruan (galeri).
class FakeImagePickerPlatform extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  Uint8List? next;
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls++;
    final bytes = next;
    return bytes == null ? null : XFile.fromData(bytes, name: 'photo.png', mimeType: 'image/png');
  }
}

/// Fail yang dipilih (dalam memori).
final class MemoryPlatformFile extends PlatformFile {
  @override
  final String name;
  final Uint8List bytes;

  MemoryPlatformFile(this.name, this.bytes);

  @override
  Uri get uri => Uri.parse('memory:///$name');

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

/// Pemilih fail tiruan (pulihkan backup).
class FakeFilePickerPlatform extends FilePickerPlatform with MockPlatformInterfaceMixin {
  PlatformFile? next;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async =>
      next;
}

/// Plugin google_sign_in tiruan (lapisan platform, di bawah DefaultGoogleAuthAdapter).
class FakeGoogleSignInPlatform extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user = GoogleSignInUserData(email: 'aina@gmail.com', id: 'g-1', displayName: 'Nur Aina');
  GoogleSignInTokenData tokens = GoogleSignInTokenData(idToken: 'id-token', accessToken: 'access-token');
  int signOuts = 0;
  int signIns = 0;
  SignInInitParameters? initParams;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<void> initWithParams(SignInInitParameters params) async => initParams = params;

  @override
  Future<GoogleSignInUserData?> signIn() async {
    signIns++;
    return user;
  }

  @override
  Future<GoogleSignInTokenData> getTokens({required String email, bool? shouldRecoverAuth = true}) async =>
      tokens;

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isSignedIn() async => false;

  @override
  Future<void> clearAuthCache({required String token}) async {}
}

/// Pelancar pautan tiruan (video YouTube/Drive dibuka dalam aplikasi lain).
class FakeUrlLauncherPlatform extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final List<String> launched = [];
  bool succeed = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return succeed;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return succeed;
  }
}

/// Pasang semua plugin tiruan SEKALI (SharePlus menyimpan platform pertama
/// yang ditemui) dan set semula keadaannya untuk setiap ujian.
class PlatformFakes {
  static PlatformFakes? _installed;

  final share = FakeSharePlatform();
  final imagePicker = FakeImagePickerPlatform();
  final filePicker = FakeFilePickerPlatform();
  final googleSignIn = FakeGoogleSignInPlatform();
  final urlLauncher = FakeUrlLauncherPlatform();

  PlatformFakes._() {
    UrlLauncherPlatform.instance = urlLauncher;
    SharePlatform.instance = share;
    ImagePickerPlatform.instance = imagePicker;
    FilePickerPlatform.instance = filePicker;
    GoogleSignInPlatform.instance = googleSignIn;
  }

  factory PlatformFakes.install() {
    final fakes = _installed ??= PlatformFakes._();
    fakes.share
      ..shared.clear()
      ..fail = false;
    fakes.imagePicker
      ..next = null
      ..calls = 0;
    fakes.filePicker.next = null;
    fakes.urlLauncher
      ..launched.clear()
      ..succeed = true;
    fakes.googleSignIn
      ..user = GoogleSignInUserData(email: 'aina@gmail.com', id: 'g-1', displayName: 'Nur Aina')
      ..tokens = GoogleSignInTokenData(idToken: 'id-token', accessToken: 'access-token')
      ..signOuts = 0
      ..signIns = 0
      ..initParams = null;
    return fakes;
  }
}
