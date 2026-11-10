import 'dart:js_interop';
import 'dart:typed_data';

/// Nel browser la registrazione resta in memoria: il registratore restituisce un
/// indirizzo `blob:` da cui si leggono i byte, e che va liberato quando non serve più.

@JS('fetch')
external JSPromise<_Response> _fetch(String url);

extension type _Response._(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('URL.revokeObjectURL')
external void _revoke(String url);

/// Il browser non registra in un file: il percorso non serve.
Future<String> recordingPath(String name) async => '';

Future<Uint8List> readRecording(String url) async {
  final response = await _fetch(url).toDart;
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

/// Libera la memoria della registrazione.
Future<void> discardRecording(String url) async {
  if (url.startsWith('blob:')) _revoke(url);
}
