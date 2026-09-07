import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';

void main() {
  test('GET כברירת מחדל עם Accept כללי */*', () async {
    late http.BaseRequest captured;
    final service = PluginNetworkFetchService(
      client: MockClient((req) async {
        captured = req;
        return http.Response('hello', 200);
      }),
    );

    final response = await service.fetchStream(
      Uri.parse('https://api.example.com/x'),
    );

    expect(captured.method, 'GET');
    expect(captured.headers['accept'], '*/*');
    expect(response.status, 200);
    expect(response.ok, isTrue);
    expect(await response.body.join(), 'hello');
  });

  test('POST מעביר method, headers ו-body', () async {
    late http.BaseRequest captured;
    final service = PluginNetworkFetchService(
      client: MockClient((req) async {
        captured = req;
        return http.Response('{"data":[]}', 200);
      }),
    );

    final response = await service.fetchStream(
      Uri.parse('https://nakdan.dicta.org.il/api'),
      method: 'POST',
      headers: {'Content-Type': 'application/json;charset=UTF-8'},
      body: '{"task":"nakdan"}',
    );

    expect(captured.method, 'POST');
    expect(captured.headers['content-type'], 'application/json;charset=UTF-8');
    expect((captured as http.Request).body, '{"task":"nakdan"}');
    expect(response.ok, isTrue);
    expect(await response.body.join(), '{"data":[]}');
  });

  test('headers מפורשים דורסים את ברירת המחדל של Accept', () async {
    late http.BaseRequest captured;
    final service = PluginNetworkFetchService(
      client: MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      }),
    );

    await service.fetchStream(
      Uri.parse('https://api.example.com/x'),
      headers: {'Accept': 'application/json'},
    );

    expect(captured.headers['accept'], 'application/json');
  });

  test('סטטוס שאינו 2xx מחזיר ok=false עם הסטטוס והגוף', () async {
    final service = PluginNetworkFetchService(
      client: MockClient((req) async => http.Response('nope', 404)),
    );

    final response = await service.fetchStream(
      Uri.parse('https://api.example.com/x'),
    );

    expect(response.status, 404);
    expect(response.ok, isFalse);
    expect(await response.body.join(), 'nope');
  });

  test('fetchStream מזרים UTF-8 תקין גם כשהתו נחצה בין מקטעים', () async {
    final responseBody = StreamController<List<int>>();
    final service = PluginNetworkFetchService(
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          responseBody.stream,
          206,
          headers: {'content-type': 'application/x-ndjson'},
        );
      }),
    );

    final response = await service.fetchStream(
      Uri.parse('https://api.example.com/stream'),
    );
    final chunks = response.body.toList();
    final encoded = utf8.encode('א\nב');
    responseBody
      ..add(encoded.sublist(0, 1))
      ..add(encoded.sublist(1, 3))
      ..add(encoded.sublist(3));
    await responseBody.close();

    expect(response.status, 206);
    expect(response.ok, isTrue);
    expect(response.headers['content-type'], 'application/x-ndjson');
    expect((await chunks).join(), 'א\nב');
  });

  test('fetchStream משתמש בבקשה שניתנת לביטול', () async {
    final abort = Completer<void>();
    final requestStarted = Completer<void>();
    final service = PluginNetworkFetchService(
      client: MockClient.streaming((request, bodyStream) async {
        final abortable = request as http.AbortableRequest;
        requestStarted.complete();
        await abortable.abortTrigger;
        throw http.RequestAbortedException(request.url);
      }),
    );

    final response = service.fetchStream(
      Uri.parse('https://api.example.com/stream'),
      abortTrigger: abort.future,
    );
    await requestStarted.future;
    abort.complete();

    await expectLater(response, throwsA(isA<http.RequestAbortedException>()));
  });
}
