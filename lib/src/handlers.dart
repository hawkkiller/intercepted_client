part of 'client.dart';

/// BaseHandler
abstract base class Handler {
  Handler();

  final _completer = Completer<InterceptorState>();

  /// Returns the future of the handler.
  Future<InterceptorState> get future => _completer.future;
}

/// Handler that is used for requests
final class RequestHandler extends Handler {
  /// Creates a new [RequestHandler].
  RequestHandler();

  /// Rejects the request.
  void reject(Object error, {bool next = false}) {
    _completer.completeError(
      InterceptorState(
        value: error,
        action: next ? InterceptorAction.next : InterceptorAction.reject,
      ),
    );
  }

  /// Goes to the next interceptor.
  void next(BaseRequest request) {
    _completer.complete(InterceptorState(value: request));
  }

  /// Resolves the request.
  void resolve(Response response, {bool next = false}) {
    _completer.complete(
      InterceptorState(
        value: response,
        action: next ? InterceptorAction.resolveNext : InterceptorAction.resolve,
      ),
    );
  }
}

/// Handler that is used for responses.
final class ResponseHandler extends Handler {
  /// Creates a new [ResponseHandler].
  ResponseHandler();

  /// Rejects the response.
  void reject(Object error, {bool next = false}) {
    _completer.completeError(
      InterceptorState(
        value: error,
        action: next ? InterceptorAction.rejectNext : InterceptorAction.reject,
      ),
    );
  }

  /// Resolves the response.
  void resolve(Response response, {bool next = false}) {
    _completer.complete(
      InterceptorState(
        value: response,
        action: next ? InterceptorAction.resolveNext : InterceptorAction.resolve,
      ),
    );
  }

  /// Goes to the next interceptor.
  void next(Response response) {
    _completer.complete(InterceptorState(value: response));
  }
}

/// Handler that is used for errors.
final class ErrorHandler extends Handler {
  /// Creates a new [ErrorHandler].
  ErrorHandler();

  /// Rejects other interceptors.
  void reject(Object error, {bool next = false}) {
    _completer.completeError(
      InterceptorState(
        value: error,
        action: next ? InterceptorAction.rejectNext : InterceptorAction.reject,
      ),
    );
  }

  /// Resolves with response.
  void resolve(Response response) {
    _completer.complete(
      InterceptorState(value: response, action: InterceptorAction.resolve),
    );
  }

  /// Goes to the next interceptor.
  void next(Object error, [StackTrace? stackTrace]) {
    _completer.completeError(InterceptorState(value: error), stackTrace);
  }
}
