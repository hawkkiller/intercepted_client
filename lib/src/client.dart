// ignore_for_file: avoid-unnecessary-reassignment, argument_type_not_assignable_to_error_handler

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart';

part 'handlers.dart';
part 'interceptors.dart';

/// Base class for all clients that intercept requests and responses.
base class InterceptedClient extends BaseClient {
  /// Creates a new [InterceptedClient].
  InterceptedClient({
    required Client inner,
    List<HttpInterceptor>? interceptors,
  })  : _inner = inner,
        _interceptors = interceptors ?? const [];

  final Client _inner;
  final List<HttpInterceptor> _interceptors;

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    Future<InterceptorState> future = Future.sync(
      () => InterceptorState(value: request),
    );

    for (final interceptor in _interceptors) {
      future = future.then(
        _requestInterceptorWrapper(
          interceptor is SequentialHttpInterceptor
              ? interceptor._interceptRequest
              : interceptor.interceptRequest,
        ),
      );
    }

    future = future.then(
      _requestInterceptorWrapper((request, handler) {
        _inner
            .send(request)
            .then(Response.fromStream)
            .then((response) => handler.resolve(response, next: true));
      }),
    );

    for (final interceptor in _interceptors) {
      future = future.then(
        _responseInterceptorWrapper(
          interceptor is SequentialHttpInterceptor
              ? interceptor._interceptResponse
              : interceptor.interceptResponse,
        ),
      );
    }

    for (final interceptor in _interceptors) {
      future = future.catchError(
        _errorInterceptorWrapper(
          interceptor is SequentialHttpInterceptor
              ? interceptor._interceptError
              : interceptor.interceptError,
        ),
      );
    }

    return future.then((res) {
      final response = res.value as Response;
      return _convertToStreamed(response);
    }).catchError((Object e, StackTrace stackTrace) {
      final err = e is InterceptorState ? e.value : e;

      if (e is InterceptorState) {
        if (e.action == InterceptorAction.resolve) {
          return _convertToStreamed(err as Response);
        }
      }

      Error.throwWithStackTrace(err, stackTrace);
    });
  }

  StreamedResponse _convertToStreamed(Response response) => StreamedResponse(
        ByteStream.fromBytes(response.bodyBytes),
        response.statusCode,
        contentLength: response.contentLength,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        request: response.request,
      );

  // Wrapper for request interceptors to return future.
  FutureOr<InterceptorState> Function(InterceptorState)
      _requestInterceptorWrapper(
    Interceptor<BaseRequest, RequestHandler> interceptor,
  ) =>
          (InterceptorState state) {
            if (state.action == InterceptorAction.next) {
              final handler = RequestHandler();
              interceptor(state.value as BaseRequest, handler);
              return handler.future;
            }

            return state;
          };

  // Wrapper for response interceptors to return future.
  FutureOr<InterceptorState> Function(InterceptorState)
      _responseInterceptorWrapper(
    Interceptor<Response, ResponseHandler> interceptor,
  ) =>
          (InterceptorState state) {
            if (state.action == InterceptorAction.next ||
                state.action == InterceptorAction.resolveNext) {
              final handler = ResponseHandler();
              interceptor(state.value as Response, handler);
              return handler.future;
            }

            return state;
          };

  // Wrapper for error interceptors to return future.
  FutureOr<InterceptorState> Function(
      InterceptorState) _errorInterceptorWrapper(
    Interceptor<Object, ErrorHandler> interceptor,
  ) =>
      (Object error) {
        final state =
            error is InterceptorState ? error : InterceptorState(value: error);

        if (state.action == InterceptorAction.next ||
            state.action == InterceptorAction.rejectNext) {
          final handler = ErrorHandler();
          interceptor(state.value, handler);
          return handler.future;
        }

        throw state;
      };
}
