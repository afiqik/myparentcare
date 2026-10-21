import 'dart:async';
import 'dart:io';

import 'package:image/image.dart' as img;

/// Image.network (cth. gambar kecil YouTube) dalam ujian: tiada internet,
/// jadi setiap permintaan dijawab dengan PNG 1x1 dari memori.
class FakeImageHttpOverrides extends HttpOverrides {
  final List<Uri> requested = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient(this);
}

final List<int> _png = img.encodePng(img.Image(width: 1, height: 1));

class _FakeHttpClient implements HttpClient {
  final FakeImageHttpOverrides _owner;

  _FakeHttpClient(this._owner);

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _owner.requested.add(url);
    return _FakeRequest();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _png.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_png).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
