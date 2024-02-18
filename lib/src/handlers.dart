part of 'client.dart';

/// BaseHandler
abstract base class Handler {
  Handler(this.state);

  final InterceptorState state;

  final _completer = Completer<InterceptorState>();

  /// Returns the future of the handler.
  Future<InterceptorState> get _future => _completer.future;
}

/// Handler that is used for requests
final class RequestHandler extends Handler {
  /// Creates a new [RequestHandler].
  RequestHandler(super.state);

  /// Rejects the request.
  void rejectRequest(Object error, {bool next = false}) {
    _completer.completeError(
      state.copyWith(
        error: error,
        action: next ? InterceptorAction.rejectAllowNext : InterceptorAction.reject,
      ),
      Trace.current(1),
    );
  }

  /// Goes to the next interceptor.
  void next(BaseRequest request) {
    _completer.complete(
      state.copyWith(
        request: request,
        action: InterceptorAction.next,
      ),
    );
  }

  /// Resolves the request.
  void resolveResponse(StreamedResponse response, {bool next = false}) {
    _completer.complete(
      state.copyWith(
        response: response,
        action: next ? InterceptorAction.resolveAllowNext : InterceptorAction.resolve,
      ),
    );
  }
}

/// Handler that is used for responses.
final class ResponseHandler extends Handler {
  /// Creates a new [ResponseHandler].
  ResponseHandler(super.state);

  /// Rejects the response.
  void rejectResponse(Object error, {bool next = false}) {
    _completer.completeError(
      state.copyWith(
        error: error,
        action: next ? InterceptorAction.rejectAllowNext : InterceptorAction.reject,
      ),
      Trace.current(1),
    );
  }

  /// Resolves the response.
  void resolveResponse(StreamedResponse response, {bool next = true}) {
    _completer.complete(
      state.copyWith(
        response: response,
        action: next ? InterceptorAction.resolveAllowNext : InterceptorAction.resolve,
      ),
    );
  }
}

/// Handler that is used for errors.
final class ErrorHandler extends Handler {
  /// Creates a new [ErrorHandler].
  ErrorHandler(super.state);

  /// Rejects other interceptors.
  void rejectError(Object error, {bool next = true}) {
    _completer.completeError(
      state.copyWith(
        error: error,
        action: next ? InterceptorAction.rejectAllowNext : InterceptorAction.reject,
      ),
      Trace.current(1),
    );
  }

  /// Resolves with response.
  void resolveResponse(StreamedResponse response) {
    _completer.complete(
      state.copyWith(
        response: response,
        action: InterceptorAction.resolve,
      ),
    );
  }
}
