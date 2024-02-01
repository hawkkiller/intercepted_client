part of 'client.dart';

/// BaseHandler
abstract base class Handler {
  final _completer = Completer<InterceptorState>();

  /// Callback that is used to process the next interceptor in the queue.
  void Function()? _processNextInQueue;

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
    _processNextInQueue?.call();
  }

  /// Goes to the next interceptor.
  void next(BaseRequest request) {
    _completer.complete(InterceptorState(value: request));
    _processNextInQueue?.call();
  }

  /// Resolves the request.
  void resolve(Response response, {bool next = false}) {
    _completer.complete(
      InterceptorState(
        value: response,
        action: next ? InterceptorAction.resolveNext : InterceptorAction.resolve,
      ),
    );
    _processNextInQueue?.call();
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
    _processNextInQueue?.call();
  }

  /// Resolves the response.
  void resolve(Response response, {bool next = false}) {
    _completer.complete(
      InterceptorState(
        value: response,
        action: next ? InterceptorAction.resolveNext : InterceptorAction.resolve,
      ),
    );
    _processNextInQueue?.call();
  }

  /// Goes to the next interceptor.
  void next(Response response) {
    _completer.complete(InterceptorState(value: response));
    _processNextInQueue?.call();
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
    _processNextInQueue?.call();
  }

  /// Resolves with response.
  void resolve(Response response) {
    _completer.complete(
      InterceptorState(value: response, action: InterceptorAction.resolve),
    );
    _processNextInQueue?.call();
  }

  /// Goes to the next interceptor.
  void next(Object error, [StackTrace? stackTrace]) {
    _completer.completeError(InterceptorState(value: error), stackTrace);
    _processNextInQueue?.call();
  }
}
