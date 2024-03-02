import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:intercepted_client/src/intercepted_client.dart';
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
  void interceptResponse(StreamedResponse response, ResponseHandler handler) {
    responseCount++;
    handler.resolveResponse(response);
  }
}

class FakeSequentialHttpInterceptorDeclining extends SequentialHttpInterceptor {
  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    handler.rejectRequest('rejected');
  }

  @override
  void interceptResponse(StreamedResponse response, ResponseHandler handler) {
    handler.rejectResponse('rejected');
  }
}

void main() {
  group('InterceptedClient', () {
    group('HttpInterceptor', () {
      group('request', () {
        test('adds headers to request', () async {
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
          final response = client.send(req);

          await expectLater(
            response,
            completion(
              predicate<StreamedResponse>((response) => response.statusCode == 200),
            ),
          );

          expect(req.headers['foo'], 'bar');
        });

        test('rejects request', () async {
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.rejectRequest('rejected 1');
                },
              ),
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));
          final response = client.send(req);

          await expectLater(response, throwsA('rejected 1'));
          expect(req.headers['foo'], null);
        });

        test('following interceptor is not called when rejected', () async {
          final sequentialInterceptor = FakeSequentialHttpInterceptorHeaders({
            'foo': 'bar',
          });

          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.rejectRequest('rejected 1');
                },
              ),
              sequentialInterceptor,
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));
          final response = client.send(req);

          await expectLater(response, throwsA('rejected 1'));
          expect(req.headers['foo'], null);
          expect(sequentialInterceptor.requestCount, isZero);
        });

        test('request interceptor resolves response', () {
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                    next: true,
                  );
                },
                interceptResponse: (response, handler) {
                  handler.resolveResponse(response);
                },
              ),
            ],
          );

          final response = client.get(Uri.parse('http://localhost'));

          expectLater(
            response,
            completion(
              predicate<Response>((response) => response.statusCode == 201),
            ),
          );
        });
        test('request is not sent if it was resolved', () async {
          int requestCount = 0;
          final client = InterceptedClient(
            inner: MockClient((request) async {
              requestCount++;
              return Response('', 200);
            }),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                    next: false,
                  );
                },
              ),
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));
          final response = client.send(req);

          await expectLater(
            response,
            completion(
              predicate<StreamedResponse>(
                (response) {
                  return response.statusCode == 201;
                },
              ),
            ),
          );

          expect(requestCount, isZero);
        });
        test('request interceptors are not called when resolved', () async {
          final sequentialInterceptor = FakeSequentialHttpInterceptorHeaders({
            'foo': 'bar',
          });

          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                    next: true,
                  );
                },
              ),
              sequentialInterceptor,
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));
          final response = client.send(req);

          await expectLater(
            response,
            completion(
              predicate<StreamedResponse>(
                (response) {
                  return response.statusCode == 201;
                },
              ),
            ),
          );

          expect(req.headers['foo'], null);
          expect(sequentialInterceptor.requestCount, isZero);
          expect(sequentialInterceptor.responseCount, equals(1));
        });
        test('when resolved without next, response interceptor is not called', () async {
          final sequentialInterceptor = FakeSequentialHttpInterceptorHeaders({
            'foo': 'bar',
          });

          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                    next: false,
                  );
                },
              ),
              sequentialInterceptor,
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));
          final response = client.send(req);

          await expectLater(
            response,
            completion(
              predicate<StreamedResponse>(
                (response) {
                  return response.statusCode == 201;
                },
              ),
            ),
          );

          expect(req.headers['foo'], null);
          expect(sequentialInterceptor.requestCount, isZero);
          expect(sequentialInterceptor.responseCount, isZero);
        });
      });
      group('response', () {
        test('response interceptor rejects', () {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptResponse: (response, handler) {
                  handler.rejectResponse('rejected', next: true);
                },
              ),
            ],
          );

          // when
          final response = client.get(Uri.parse('http://localhost'));

          // then
          expectLater(response, throwsA('rejected'));
        });
        test('response interceptor resolves response', () {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptResponse: (response, handler) {
                  expect(response.statusCode, 200);

                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                  );
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

        test('response interceptor resolves json response', () {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('{"foo": "bar"}', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptResponse: (response, handler) {
                  expect(response.statusCode, 200);

                  handler.resolveResponse(
                    StreamedResponse(
                      ByteStream.fromBytes(
                        utf8.encode('{"foo": "baz"}'),
                      ),
                      201,
                      headers: response.headers,
                    ),
                  );
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
              predicate<Response>(
                (response) => response.statusCode == 201 && response.body == '{"foo": "baz"}',
              ),
            ),
          );
        });

        test('following response interceptor is not called with next: false', () {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptResponse: (response, handler) {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                    next: false,
                  );
                },
              ),
              HttpInterceptor.fromHandlers(
                interceptResponse: (response, handler) {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 202),
                    next: false,
                  );
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
      });
      group('error', () {
        test('errors are intercepted on reject with next: true', () {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.rejectRequest('rejected 1', next: true);
                },
              ),
              HttpInterceptor.fromHandlers(
                interceptError: (error, handler) {
                  handler.rejectError(1, next: true);
                },
              ),
              HttpInterceptor.fromHandlers(
                interceptError: (error, handler) {
                  handler.rejectError(2, next: true);
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
                  handler.rejectRequest('rejected 1', next: true);
                },
              ),
              HttpInterceptor.fromHandlers(
                interceptError: (error, handler) {
                  handler.rejectError(1, next: true);
                },
              ),
              HttpInterceptor.fromHandlers(
                interceptError: (error, handler) {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                  );
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
        test('error interceptor is not called when response is resolved', () {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.rejectRequest('rejected 1', next: true);
                },
              ),
              HttpInterceptor.fromHandlers(
                interceptError: (error, handler) {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                  );
                },
              ),
              HttpInterceptor.fromHandlers(
                interceptError: (error, handler) {
                  handler.rejectError(1, next: true);
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

        test('error interceptor is not called on reject next:false', () {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              HttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) {
                  handler.rejectRequest('rejected 1', next: false);
                },
              ),
              HttpInterceptor.fromHandlers(
                interceptError: (error, handler) {
                  handler.rejectError(1, next: false);
                },
              ),
            ],
          );

          // when
          final response = client.get(Uri.parse('http://localhost'));

          // then
          expectLater(response, throwsA('rejected 1'));
        });
      });
    });

    group('SequentialInterceptor', () {
      group('request', () {
        test('sequential requests are enqueued', () async {
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
                interceptRequest: (request, handler) async {
                  await Future.delayed(Duration(milliseconds: 100));
                  handler.next(request..headers['bar'] = 'baz');
                },
              ),
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));

          // second request that should be completed 100ms after the first one
          final req2 = Request('GET', Uri.parse('http://localhost'));

          // when
          final response = client.send(req);
          final response2 = client.send(req2);

          final stopwatch = Stopwatch()..start();

          // then
          await expectLater(
            response,
            completion(
              predicate<StreamedResponse>(
                (response) =>
                    response.statusCode == 200 &&
                    req.headers['bar'] == 'baz' &&
                    req.headers['foo'] == 'bar',
              ),
            ),
          );
          expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(100));

          await expectLater(
            response2,
            completion(
              predicate<StreamedResponse>(
                (response) =>
                    response.statusCode == 200 &&
                    req2.headers['bar'] == 'baz' &&
                    req2.headers['foo'] == 'bar',
              ),
            ),
          );

          expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(200));
        });

        test('request resolves', () async {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              SequentialHttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) async {
                  await Future.delayed(Duration(milliseconds: 100));
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                    next: false,
                  );
                },
              ),
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));

          // when
          final response = client.send(req);

          final stopwatch = Stopwatch()..start();

          // then
          await expectLater(
            response,
            completion(
              predicate<StreamedResponse>(
                (response) => response.statusCode == 201,
              ),
            ),
          );

          expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(100));
        });

        test('multiple sequential request interceptors', () async {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              SequentialHttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) async {
                  await Future.delayed(Duration(milliseconds: 100));
                  handler.next(request..headers['foo'] = 'bar');
                },
              ),
              SequentialHttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) async {
                  await Future.delayed(Duration(milliseconds: 100));
                  handler.next(request..headers['bar'] = 'baz');
                },
              ),
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));

          // when
          final response = client.send(req);

          final stopwatch = Stopwatch()..start();

          // then
          await expectLater(
            response,
            completion(
              predicate<StreamedResponse>(
                (response) =>
                    response.statusCode == 200 &&
                    req.headers['bar'] == 'baz' &&
                    req.headers['foo'] == 'bar',
              ),
            ),
          );

          expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(200));
        });
      });
      group('response', () {
        test('both request and response are intercepted', () async {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              SequentialHttpInterceptor.fromHandlers(
                interceptRequest: (request, handler) async {
                  await Future.delayed(Duration(milliseconds: 100));
                  handler.next(request..headers['foo'] = 'bar');
                },
                interceptResponse: (response, handler) async {
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 202),
                  );
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
                (response) => response.statusCode == 202 && req.headers['foo'] == 'bar',
              ),
            ),
          );
        });

        test('response resolves', () async {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              SequentialHttpInterceptor.fromHandlers(
                interceptResponse: (response, handler) async {
                  await Future.delayed(Duration(milliseconds: 100));
                  handler.resolveResponse(
                    StreamedResponse(ByteStream.fromBytes([]), 201),
                    next: false,
                  );
                },
              ),
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));

          // when
          final response = client.send(req);

          final stopwatch = Stopwatch()..start();

          // then
          await expectLater(
            response,
            completion(
              predicate<StreamedResponse>(
                (response) => response.statusCode == 201,
              ),
            ),
          );

          expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(100));
        });

        test('response is rejected', () async {
          // given
          final client = InterceptedClient(
            inner: MockClient((request) async => Response('', 200)),
            interceptors: [
              SequentialHttpInterceptor.fromHandlers(
                interceptResponse: (response, handler) async {
                  await Future.delayed(Duration(milliseconds: 100));
                  handler.rejectResponse('rejected');
                },
              ),
            ],
          );

          final req = Request('GET', Uri.parse('http://localhost'));

          // when
          final response = client.send(req);

          final stopwatch = Stopwatch()..start();

          // then
          await expectLater(response, throwsA('rejected'));

          expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(100));
        });
      });
    });
  });
}
