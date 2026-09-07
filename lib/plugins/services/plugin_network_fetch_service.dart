import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';

/// תגובת HTTP פתוחה עבור `network.fetchStream`.
class PluginNetworkFetchStreamResponse {
  final int status;
  final bool ok;
  final Map<String, String> headers;

  /// מקטעי טקסט מפוענחים כ-UTF-8; הגבולות אינם גבולות שורות.
  final Stream<String> body;

  const PluginNetworkFetchStreamResponse({
    required this.status,
    required this.ok,
    required this.headers,
    required this.body,
  });
}

/// שירות לביצוע בקשות HTTP עבור `network.fetchStream`.
///
/// הבקשה רצה בצד אוצריא (Flutter) ולא ב-WebView, ולכן **אינה כפופה ל-CORS**.
/// זהו הנתיב שתוספים צריכים להשתמש בו לקריאות ל-APIs חיצוניים (במיוחד `POST`),
/// מכיוון ש-`fetch()` ישיר מה-WebView (origin `file://`) נחסם ב-CORS מול
/// שרתים שאינם מחזירים `Access-Control-Allow-Origin`.
///
/// בדיקת ההרשאה וה-allowlist מתבצעות אצל הקורא (האדפטר), לא כאן.
class PluginNetworkFetchService {
  static const defaultTimeout = Duration(seconds: 30);
  static const maxTimeout = Duration(seconds: 120);

  final http.Client _client;
  late final FutureOr<void> Function() _closer = _client.close;

  PluginNetworkFetchService({http.Client? client})
    : _client = client ?? http.Client() {
    HttpClientRegistry.register(_closer);
  }

  /// משחרר את ה-client ומסירו מ-[HttpClientRegistry].
  void dispose() {
    HttpClientRegistry.unregister(_closer);
    _client.close();
  }

  /// פותחת בקשת HTTP ומחזירה את גוף התשובה כזרם UTF-8. אינה עוקבת אחרי
  /// redirects; `Accept: */*` כברירת מחדל, וניתן לדרוס דרך [headers].
  ///
  /// השלמת [abortTrigger] מבטלת גם המתנה לכותרות וגם גוף שנמצא באמצע קריאה.
  Future<PluginNetworkFetchStreamResponse> fetchStream(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    Future<void>? abortTrigger,
  }) async {
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abortTrigger,
    )..followRedirects = false;
    request.headers['accept'] = '*/*';
    if (headers != null && headers.isNotEmpty) {
      request.headers.addAll(headers);
    }
    if (body != null && body.isNotEmpty) {
      request.body = body;
    }

    final response = await _client.send(request);
    final status = response.statusCode;
    return PluginNetworkFetchStreamResponse(
      status: status,
      ok: status >= 200 && status < 300,
      headers: Map.unmodifiable(response.headers),
      body: response.stream.transform(utf8.decoder),
    );
  }
}
