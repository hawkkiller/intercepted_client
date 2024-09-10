# Intercepted Client

[![codecov](https://codecov.io/gh/hawkkiller/intercepted_client/graph/badge.svg?token=lCJwHqNC1E)](https://codecov.io/gh/hawkkiller/intercepted_client)

This is a simple HTTP client that supports interceptors and concurrent requests. It is built on top of the `http` package and implements the `Client` interface.

## Example

```dart
import 'package:http/http.dart';
import 'package:intercepted_client/intercepted_client.dart';

class AuthInterceptor extends SequentialHttpInterceptor {
  final String token;

  AuthInterceptor(this.token);

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    request.headers['Authorization'] = 'Bearer $token';

    handler.next(request);
  }
}

Future<void> main() async {
  final Client client = InterceptedClient(
    interceptors: [
      AuthInterceptor('my-token'),
    ],
  );

  final response = await client.get(Uri.parse('https://example.com'));

  // prints 'Bearer my-token'
  print(response.request?.headers['Authorization']);
}
```

The interceptor above adds an `Authorization` header to every request made by the client.

## Interceptors

Interceptor is a class that has access to the request, response and error objects. It can be used to modify the request, response or error, or to perform any side effect.

For example, an interceptor can be used to add an `Authorization` header to every request made by the client, print responses to the console or retry failed requests.

**intercepted_client** provides two types of interceptors: `HttpInterceptor` and `SequentialHttpInterceptor`.

### HttpInterceptor

`HttpInterceptor` is a simple interceptor that both defines the Interceptor contract and provides a default implementation. Each request is handled independently, and the interceptor has no knowledge of the previous or next requests.

There are three methods that can be overridden:

- `interceptRequest` - called before the request is sent, and can be used to modify the request, for example to add headers.
- `interceptResponse` - called after the response is received. Note, that this method works only with StreamedResponse (not with Response). This means that you can't see the full response body in this method, but you have access to the response headers and status code.
- `interceptError` - called when an error occurs during the request. This method can be used to retry the request or to perform any side effect.

Each method receives a `RequestHandler`, `ResponseHandler` or `ErrorHandler` object, which can be used to continue, reject or resolve the request, response or error handling.

Each method can be overridden independently, so you can create an interceptor that only logs requests, for example.

Here you can see an example of a simple `HttpInterceptor` that logs the request and response:

```dart
class LogInterceptor extends HttpInterceptor {
  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    print('Request: ${request.url}');
    handler.next(request);
  }

  @override
  void interceptResponse(StreamedResponse response, ResponseHandler handler) {
    print('Response: ${response.statusCode}');
    handler.resolveResponse(response);
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    print('Error: $error');
    handler.rejectError(error);
  }
}
```

### SequentialHttpInterceptor

`SequentialHttpInterceptor` implements the `HttpInterceptor` contract, but intercepts requests sequentially.

Under the hood, this interceptor maintains 3 queues - request, response and error. Each task in queue processed in order. It means that interceptor will wait until the previous task is completed before starting the next one.

Here is an interceptor that adds a delay of 1 second to every request:

```dart
class DelayInterceptor extends SequentialHttpInterceptor {
  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    Future.delayed(Duration(seconds: 1), () {
      handler.next(request);
    });
  }
}
```

If two requests are made in parallel, the second request will be delayed by 2 seconds, as it will wait for the previous request interceptor to complete.

Same way it works for response and error interceptors.

Note, that requests (actual packets sending) are still made in parallel, so that the application won't be blocked by the interceptor.

Also, you can create your own interceptor by implementing the `HttpInterceptor` contract.

## InterceptedClient

`InterceptedClient` is a class that implements the `Client` interface from `http` and supports interceptors that implement the `HttpInterceptor` contract.

It can be used as a drop-in replacement for the `http` client.

```dart
final Client client = InterceptedClient(
  interceptors: [
    LogInterceptor(),
  ],
);

final response = await client.get(Uri.parse('https://example.com'));
```

This client will log every request and response made by the client.
