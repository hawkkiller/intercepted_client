import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart';

part 'handlers.dart';
part 'interceptors.dart';

/// Base class for all clients that intercept requests and responses.
base class InterceptedClient extends BaseClient {
  /// Creates a new [InterceptedClient].
  InterceptedClient({
    Client? inner,
    List<HttpInterceptor>? interceptors,
  })  : _inner = inner ?? Client(),
        _interceptors = interceptors ?? const [];

  final Client _inner;
  final List<HttpInterceptor> _interceptors;

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    Future<InterceptorState<Object?>> future = Future.sync(
      () => InterceptorState(value: request),
    );

    for (final interceptor in _interceptors) {
      future = future.then(
        _requestInterceptorWrapper(interceptor._interceptRequest),
      );
    }

    future = future.then(
      _requestInterceptorWrapper((request, handler) {
        return _inner
            .send(request)
            .then((response) => handler.resolve(response, next: true))
            .then((value) => handler.future);
      }),
    );

    for (final interceptor in _interceptors) {
      future = future.then(
        _responseInterceptorWrapper(interceptor._interceptResponse),
      );
    }

    for (final interceptor in _interceptors) {
      future = future.catchError(
        _errorInterceptorWrapper(interceptor._interceptError),
      );
    }

    return future.then((res) {
      final response = res.value as StreamedResponse;
      return response;
    }).catchError((Object e, StackTrace stackTrace) {
      final err = e is InterceptorState ? e.value : e;

      if (e is InterceptorState) {
        if (e.action == InterceptorAction.resolve ||
            e.action == InterceptorAction.resolveAllowNext) {
          return err as StreamedResponse;
        }
      }

      Error.throwWithStackTrace(err, stackTrace);
    });
  }

  // Wrapper for request interceptors to return future.
  FutureOr<InterceptorState> Function(InterceptorState) _requestInterceptorWrapper(
    Interceptor<BaseRequest, RequestHandler, Future<InterceptorState>> interceptor,
  ) =>
      (InterceptorState state) async {
        if (state.action == InterceptorAction.next) {
          final handler = RequestHandler();
          final result = await interceptor(state.value as BaseRequest, handler);
          return result;
        }

        return state;
      };

  // Wrapper for response interceptors to return future.
  FutureOr<InterceptorState> Function(InterceptorState) _responseInterceptorWrapper(
    Interceptor<StreamedResponse, ResponseHandler, Future<InterceptorState>> interceptor,
  ) =>
      (InterceptorState state) async {
        if (state.action == InterceptorAction.next ||
            state.action == InterceptorAction.resolveAllowNext) {
          final handler = ResponseHandler();
          final res = await interceptor(state.value as StreamedResponse, handler);
          return res;
        }

        return state;
      };

  // Wrapper for error interceptors to return future.
  FutureOr<InterceptorState> Function(Object, StackTrace) _errorInterceptorWrapper(
    Interceptor<Object, ErrorHandler, Future<InterceptorState>> interceptor,
  ) =>
      (Object error, StackTrace stackTrace) async {
        final state = error is InterceptorState
            ? error
            : InterceptorState(
                value: error,
                action: InterceptorAction.rejectAllowNext,
              );

        if (state.action == InterceptorAction.rejectAllowNext) {
          final handler = ErrorHandler();
          final res = await interceptor(state.value, handler);
          return res;
        }

        Error.throwWithStackTrace(error, stackTrace);
      };
}
