part of 'client.dart';

/// Handler
abstract base class Handler {
  Handler(this._state);

  final InterceptorState _state;

  final _completer = Completer<InterceptorState>();

  /// Returns the future of the handler.
  Future<InterceptorState> get _future => _completer.future;
}

/// Handler that is used for requests
final class RequestHandler extends Handler {
  /// Creates a new [RequestHandler].
  RequestHandler(super.state);

  /// Rejects the request with provided [error]
  /// 
  /// If this method was called, then response interceptors will be skipped
  /// and actual request will not be sent.
  /// 
  /// If [next] is `true`, then error interceptors will be called.
  /// Otherwise, [error] will be thrown.
  void rejectRequest(Object error, {bool next = false}) {
    _completer.completeError(
      _state.copyWith(
        error: error,
        action: next ? InterceptorAction.rejectAllowNext : InterceptorAction.reject,
      ),
      Trace.current(1),
    );
  }

  /// Proceeds to the next interceptor.
  /// 
  /// If this method was called, then the next interceptor will be called.
  void next(BaseRequest request) {
    _completer.complete(
      _state.copyWith(request: request, action: InterceptorAction.next),
    );
  }

  /// Resolves the request with provided [response].
  /// 
  /// Marks this request as completed, so actual request will not be sent.
  /// 
  /// If [next] is `true`, then response interceptors will be called.
  void resolveResponse(StreamedResponse response, {bool next = false}) {
    _completer.complete(
      _state.copyWith(
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

  /// Rejects the request with provided [error].
  /// 
  /// If this method was called, then response interceptors will be skipped.
  /// 
  /// If [next] is `true`, then error interceptors will be called.
  /// Otherwise, [error] will be thrown.
  void rejectResponse(Object error, {bool next = false}) {
    _completer.completeError(
      _state.copyWith(
        error: error,
        action: next ? InterceptorAction.rejectAllowNext : InterceptorAction.reject,
      ),
      Trace.current(1),
    );
  }

  /// Resolves the request with provided [response].
  /// 
  /// This can be used to modify the response or to return a new one.
  void resolveResponse(StreamedResponse response, {bool next = true}) {
    _completer.complete(
      _state.copyWith(
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

  /// Rejects the request with provided [error].
  /// 
  /// If this method was called, then error interceptors will be skipped.
  /// 
  /// If [next] is `true`, then error interceptors will be called.
  void rejectError(Object error, {bool next = true}) {
    _completer.completeError(
      _state.copyWith(
        error: error,
        action: next ? InterceptorAction.rejectAllowNext : InterceptorAction.reject,
      ),
      Trace.current(1),
    );
  }

  /// Resolves the request with provided [response].
  /// 
  /// If this method was called, then request will be completed with
  /// [response], no error will be thrown and no other interceptors will be called.
  void resolveResponse(StreamedResponse response) {
    _completer.complete(
      _state.copyWith(
        response: response,
        action: InterceptorAction.resolve,
      ),
    );
  }
}
