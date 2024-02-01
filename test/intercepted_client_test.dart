import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:intercepted_client/src/client.dart';
import 'package:test/test.dart';

class FakeSequentialHttpInterceptorHeaders extends SequentialHttpInterceptor {
  final Map<String, String> headers;

  FakeSequentialHttpInterceptorHeaders(this.headers);

  int requestCount = 0;
  int responseCount = 0;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    request.headers.addAll(headers);
    handler.next(request);
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    responseCount++;
    handler.next(response);
  }
}

class FakeSequentialHttpInterceptorDeclining extends SequentialHttpInterceptor {
  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    handler.reject('rejected');
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    handler.reject('rejected');
  }
}

void main() {
  group('InterceptedClient', () {
    test('intercepts request', () async {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['foo'] = 'bar');
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      await expectLater(
        response,
        completion(
          predicate<StreamedResponse>((response) => response.statusCode == 200),
        ),
      );

      expect(req.headers['foo'], 'bar');
    });
    test('rejects request', () async {
      final sequentialInterceptor = FakeSequentialHttpInterceptorHeaders({
        'foo': 'bar',
      });

      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.reject('rejected 1');
            },
          ),
          sequentialInterceptor,
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      await expectLater(response, throwsA('rejected 1'));
      expect(req.headers['foo'], null);
      expect(sequentialInterceptor.requestCount, isZero);
    });

    test('intercepts response', () async {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptResponse: (response, handler) {
              final res = Response(
                response.body,
                response.statusCode,
                headers: {...response.headers, 'foo': 'bar'},
              );
              handler.next(res);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      await expectLater(
        response,
        completion(
          predicate<StreamedResponse>(
            (response) => response.statusCode == 200 && response.headers['foo'] == 'bar',
          ),
        ),
      );
    });

    test('intercepts request and response', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['foo'] = 'bar');
            },
            interceptResponse: (response, handler) {
              final res = Response(
                response.body,
                response.statusCode,
                headers: {...response.headers, 'foo': 'bar'},
              );
              handler.next(res);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      expectLater(
        response,
        completion(
          predicate<StreamedResponse>(
            (response) => response.statusCode == 200 && response.headers['foo'] == 'bar',
          ),
        ),
      );
    });

    test('sequential interceptor', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['foo'] = 'bar');
            },
          ),
          SequentialHttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['bar'] = 'baz');
            },
            interceptResponse: (response, handler) {
              final res = Response(
                response.body,
                response.statusCode,
                headers: {...response.headers, 'foo': 'bar'},
              );
              handler.next(res);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      expectLater(
        response,
        completion(
          predicate<StreamedResponse>(
            (response) =>
                response.statusCode == 200 &&
                req.headers['bar'] == 'baz' &&
                req.headers['foo'] == 'bar' &&
                response.headers['foo'] == 'bar',
          ),
        ),
      );
    });

    test('error interceptor works properly', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.reject('rejected 1', next: true);
            },
          ),
          HttpInterceptor.fromHandlers(
            interceptError: (error, handler) {
              handler.next(1);
            },
          ),
          HttpInterceptor.fromHandlers(
            interceptError: (error, handler) {
              handler.next(2);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      expectLater(response, throwsA(equals(2)));
    });

    test('error interceptor resolves response', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.reject('rejected 1', next: true);
            },
          ),
          HttpInterceptor.fromHandlers(
            interceptError: (error, handler) {
              handler.next(1);
            },
          ),
          HttpInterceptor.fromHandlers(
            interceptError: (error, handler) {
              handler.resolve(Response('', 201));
            },
          ),
        ],
      );

      // when
      final response = client.get(Uri.parse('http://localhost'));

      // then
      expectLater(
        response,
        completion(
          predicate<Response>((response) => response.statusCode == 201),
        ),
      );
    });

    test('request interceptor resolves response', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.resolve(Response('', 201), next: true);
            },
            interceptResponse: (response, handler) {
              handler.next(response);
            },
          ),
        ],
      );

      // when
      final response = client.get(Uri.parse('http://localhost'));

      // then
      expectLater(
        response,
        completion(
          predicate<Response>((response) => response.statusCode == 201),
        ),
      );
    });

    test('request interceptor rejects', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.reject('rejected', next: true);
            },
            interceptResponse: (response, handler) {
              handler.next(response);
            },
          ),
        ],
      );

      // when
      final response = client.get(Uri.parse('http://localhost'));

      // then
      expectLater(response, throwsA('rejected'));
    });

    test('response interceptor rejects', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptResponse: (response, handler) {
              handler.reject('rejected', next: true);
            },
          ),
        ],
      );

      // when
      final response = client.get(Uri.parse('http://localhost'));

      // then
      expectLater(response, throwsA('rejected'));
    });

    test('get is also intercepted', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['foo'] = 'bar');
            },
            interceptResponse: (response, handler) {
              final res = Response(
                response.body,
                response.statusCode,
                headers: {...response.headers, 'foo': 'bar'},
              );
              handler.next(res);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.get(req.url);

      // then
      expectLater(
        response,
        completion(
          predicate<Response>(
            (response) => response.statusCode == 200 && response.headers['foo'] == 'bar',
          ),
        ),
      );
    });
  });
}
