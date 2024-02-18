import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:stack_trace/stack_trace.dart';

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
  Future<StreamedResponse> send(BaseRequest request) async {
    var state = InterceptorState(request: request);

    try {
      // Iterate through request interceptors.
      for (final interceptor in _interceptors) {
        final requestHandler = RequestHandler(state);
        state = await interceptor._interceptRequest(state.request!, requestHandler);
      }

      // If the request is not resolved, send it.
      if (!state.action.resolved) {
        final response = await _inner.send(state.request!).onError(
              (error, stackTrace) => Error.throwWithStackTrace(
                InterceptorState(request: state.request, error: error),
                stackTrace,
              ),
            );

        state = InterceptorState(request: state.request, response: response);
      }

      for (final interceptor in _interceptors) {
        if (state.action == InterceptorAction.reject) {
          break;
        }

        final responseHandler = ResponseHandler(state);
        state = await interceptor._interceptResponse(state.response!, responseHandler);
      }

      return state.response!;
    } on Object catch (error, stack) {
      if (error is InterceptorState) {
        state = error;
      } else {
        state = state.copyWith(error: error);
      }

      // Iterate through error interceptors.
      for (final interceptor in _interceptors) {
        if (!state.action.canGoNext) {
          break;
        }

        try {
          final errorHandler = ErrorHandler(state);
          state = await interceptor._interceptError(state.error!, errorHandler);
        } catch (e) {
          state = e is InterceptorState ? e : state.copyWith(error: e);
        }
      }

      if (state.action.resolved) {
        return state.response!;
      }

      return Error.throwWithStackTrace(
        state.error!,
        Trace.from(stack).terse,
      );
    }
  }
}
