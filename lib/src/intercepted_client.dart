import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:stack_trace/stack_trace.dart';

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
    var state = RequestState(request: request);

    try {
      // Iterate through request interceptors.
      for (final interceptor in _interceptors) {
        if (state.action.resolved) {
          break;
        }

        final requestHandler = RequestHandler(state);
        state = await interceptor.$interceptRequest(state.request, requestHandler);
      }

      // If the request is not resolved, send it.
      if (!state.action.resolved) {
        final response = await _inner.send(state.request).onError(
              (error, stackTrace) => Error.throwWithStackTrace(
                RequestState(request: state.request, error: error),
                stackTrace,
              ),
            );

        state = RequestState(request: state.request, response: response);
      }

      for (final interceptor in _interceptors) {
        if (!state.action.canGoNext) {
          break;
        }

        final responseHandler = ResponseHandler(state);
        state = await interceptor.$interceptResponse(state.response!, responseHandler);
      }

      return state.response!;
    } on Object catch (error, stack) {
      if (error is RequestState) {
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
          state = await interceptor.$interceptError(state.error!, errorHandler);
        } catch (e) {
          state = e is RequestState ? e : state.copyWith(error: e);
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

/// BaseHandler for the request
///
/// This is the class that is used to proceed to the next interceptor or to
/// reject the request.
///
/// It contains state of the request and provides methods to proceed to the next
/// interceptor or to reject the request.
abstract base class BaseHandler {
  BaseHandler(this._state);

  /// Returns the request
  BaseRequest get request => _state.request;

  /// Current state of a request
  final RequestState _state;

  /// Completer for the handler.
  ///
  /// This will be completed with value or error when interceptor calls one of
  /// the methods of the handler.
  final _completer = Completer<RequestState>();

  /// Returns the future of the handler (completer).
  Future<RequestState> get _future => _completer.future;
}

/// Handler that is used for requests
final class RequestHandler extends BaseHandler {
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
final class ResponseHandler extends BaseHandler {
  /// Creates a new [ResponseHandler].
  ResponseHandler(super.state);

  /// Returns the response of the request.
  StreamedResponse get response => _state.response!;

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
  ///
  /// If [next] is `true`, then following response interceptors will be called.
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
final class ErrorHandler extends BaseHandler {
  /// Creates a new [ErrorHandler].
  ErrorHandler(super.state);

  /// Returns the error of the request.
  ///
  /// This is the error that occurred during the request.
  Object get error => _state.error!;

  /// Returns the response of the request
  ///
  /// It may be `null` if request was not sent or if error occurred.
  StreamedResponse? get response => _state.response;

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

/// Interceptor signature
///
/// Value is the value that is intercepted (request, response, or error).
///
/// Handler is the handler that is used to proceed to the next interceptor or to
/// reject the request.
///
/// R is the return type of the interceptor (void for user-defined interceptors).
typedef Interceptor<T extends Object, H extends BaseHandler, R> = R Function(
  T value,
  H handler,
);

/// Action of the interceptor
///
/// This is the action that is set by the interceptor to indicate what
/// should be done next.
enum InterceptorAction {
  /// Proceed to next interceptor in chain
  next,

  /// Reject, stop interceptors, rethrow error
  reject,

  /// Reject, but allow rest of chain to handle error
  rejectAllowNext,

  /// Resolve, terminate chain, return response
  resolve,

  /// Resolve, let chain continue for more processing
  resolveAllowNext;

  /// Returns `true` if the action is resolved.
  bool get resolved => this == resolve || this == resolveAllowNext;

  /// Returns `true` if the action can go to the next interceptor.
  bool get canGoNext => this == next || this == resolveAllowNext || this == rejectAllowNext;
}

/// State of the request
base class RequestState {
  RequestState({
    required this.request,
    this.action = InterceptorAction.next,
    this.response,
    this.error,
  });

  /// The action of the interceptor.
  ///
  /// Every interceptor sets this value to indicate what should be done next.
  /// For the first one, this value is always [InterceptorAction.next] and
  /// inner machinery must treat this value to understand what to do next.
  final InterceptorAction action;

  /// The actual request to be sent.
  ///
  /// It can be modified by interceptors or changed to another request
  /// if needed (but not recommended).
  final BaseRequest request;

  /// The actual response.
  ///
  /// It can be modified by interceptors or changed to another response
  /// if needed (for example, when retrying request).
  ///
  /// It can be `null` if request was not sent or if error occurred.
  final StreamedResponse? response;

  /// The error that occurred.
  ///
  /// It can be modified by interceptors or changed to another error.
  /// You may expect to see [SocketException] or [HttpException] here.
  ///
  /// It can be `null` if request was sent successfully and if response was received.
  final Object? error;

  /// Creates a copy of this state with the given fields replaced by the new values.
  RequestState copyWith({
    BaseRequest? request,
    StreamedResponse? response,
    Object? error,
    InterceptorAction? action,
  }) =>
      RequestState(
        request: request ?? this.request,
        response: response ?? this.response,
        error: error ?? this.error,
        action: action ?? this.action,
      );
}

/// Base class for interceptor handlers.
///
/// It is used to handle the request, response, and error.
class HttpInterceptor {
  /// Creates a new [HttpInterceptor].
  const HttpInterceptor();

  /// Creates a new [HttpInterceptor] from the given handlers.
  ///
  /// This can be a convenient way to create an interceptor from a set of
  /// handlers, but it is recommended to create a subclass of [HttpInterceptor]
  /// and override the methods instead.
  factory HttpInterceptor.fromHandlers({
    Interceptor<BaseRequest, RequestHandler, void>? interceptRequest,
    Interceptor<StreamedResponse, ResponseHandler, void>? interceptResponse,
    Interceptor<Object, ErrorHandler, void>? interceptError,
  }) =>
      _HttpInterceptorWrapper(
        interceptRequest: interceptRequest,
        interceptResponse: interceptResponse,
        interceptError: interceptError,
      );

  /// Intercepts the request
  ///
  /// This method has access to the request that is about to be sent.
  ///
  /// Override this method to provide custom request handling,
  /// for example, to modify the request or to add headers.
  void interceptRequest(
    BaseRequest request,
    RequestHandler handler,
  ) =>
      handler.next(request);

  /// Intercepts the response
  ///
  /// This method has access to the response that was received during the request.
  ///
  /// Override this method to provide custom response handling,
  /// for example, to modify the response or to retry the request,
  /// refresh the token, etc.
  void interceptResponse(
    StreamedResponse response,
    ResponseHandler handler,
  ) =>
      handler.resolveResponse(response);

  /// Intercepts the error
  ///
  /// This method has access to the error that occurred during the request.
  ///
  /// Override this method to provide custom error handling,
  /// for example, to retry the request.
  void interceptError(
    Object error,
    ErrorHandler handler,
  ) =>
      handler.rejectError(error, next: true);

  /// Method that is called by inner machinery to intercept the request.
  ///
  /// This method can be overridden to provide custom behavior. For example,
  /// [SequentialHttpInterceptor] uses this method to enqueue the request.
  Future<RequestState> $interceptRequest(
    BaseRequest request,
    RequestHandler handler,
  ) {
    interceptRequest(request, handler);
    return handler._future;
  }

  /// Method that is called by inner machinery to intercept the response.
  ///
  /// This method can be overridden to provide custom behavior. For example,
  /// [SequentialHttpInterceptor] uses this method to enqueue the response.
  Future<RequestState> $interceptResponse(
    StreamedResponse response,
    ResponseHandler handler,
  ) {
    interceptResponse(response, handler);
    return handler._future;
  }

  /// Method that is called by inner machinery to intercept the error.
  ///
  /// This method can be overridden to provide custom behavior. For example,
  /// [SequentialHttpInterceptor] uses this method to enqueue the error.
  Future<RequestState> $interceptError(
    Object error,
    ErrorHandler handler,
  ) {
    interceptError(error, handler);
    return handler._future;
  }
}

final class _HttpInterceptorWrapper extends HttpInterceptor {
  _HttpInterceptorWrapper({
    Interceptor<BaseRequest, RequestHandler, void>? interceptRequest,
    Interceptor<StreamedResponse, ResponseHandler, void>? interceptResponse,
    Interceptor<Object, ErrorHandler, void>? interceptError,
  })  : _$interceptRequest = interceptRequest,
        _$interceptResponse = interceptResponse,
        _$interceptError = interceptError;

  final Interceptor<BaseRequest, RequestHandler, void>? _$interceptRequest;
  final Interceptor<StreamedResponse, ResponseHandler, void>? _$interceptResponse;
  final Interceptor<Object, ErrorHandler, void>? _$interceptError;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    if (_$interceptRequest != null) {
      _$interceptRequest!(request, handler);
    } else {
      handler.next(request);
    }
  }

  @override
  void interceptResponse(StreamedResponse response, ResponseHandler handler) {
    if (_$interceptResponse != null) {
      _$interceptResponse!(response, handler);
    } else {
      handler.resolveResponse(response);
    }
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    if (_$interceptError != null) {
      _$interceptError!(error, handler);
    } else {
      handler.rejectError(error, next: true);
    }
  }
}

/// Sequential task for the queue
///
/// This is the task that is used to enqueue the request, response, or error
///
/// [T] is the type of the value that is intercepted (request, response, or error)
///
/// [H] is the type of the handler that is used to proceed to the next interceptor
/// or to reject the request
///
/// This class is used by [SequentialHttpInterceptor] to enqueue the request,
final class _SequentialTask<T extends Object, H extends BaseHandler> {
  _SequentialTask({
    required Interceptor<T, H, void> interceptor,
    required this.value,
    required H handler,
  })  : _interceptor = interceptor,
        _handler = handler;

  final Interceptor<T, H, void> _interceptor;
  final T value;
  final H _handler;

  Future<RequestState> call() {
    _interceptor(value, _handler);

    return _handler._future;
  }

  /// Returns the future of the handler.
  Future<RequestState> get future => _handler._future;
}

/// Queue of sequential tasks.
final class _SequentialTaskQueue extends QueueList<_SequentialTask> {
  _SequentialTaskQueue() : super(5);

  /// Returns `true` if the queue is processing.
  bool get isProcessing => length > 0;

  bool _closed = false;
  Future<void>? _processing;

  @override
  Future<RequestState> add(_SequentialTask element) async {
    super.add(element);
    _run();

    return element.future;
  }

  /// Closes the queue
  ///
  /// After the queue is closed, no more tasks can be added to it.
  Future<void> close() async {
    await _processing;
    _closed = true;
  }

  /// Runs the queue
  ///
  /// This method processes the queue and runs the tasks in sequence.
  void _run() => _processing ??= Future.doWhile(() async {
        final elem = first;
        if (_closed) return false;
        try {
          await elem();
        } on Object {
          // this error can be ignored, because it is handled by the handler
        } finally {
          removeFirst();
        }

        if (isEmpty) {
          _processing = null;
        }

        return isNotEmpty;
      });
}

/// Sequential interceptor that runs interceptors in sequence.
///
/// This way, every consecutive request is put in a queue and is processed
/// only after the previous one is finished.
///
/// It uses 3 queues for requests, responses, and errors. This way, it is
/// possible to handle requests, responses, and errors in sequence.
class SequentialHttpInterceptor extends HttpInterceptor {
  /// Creates a new [SequentialHttpInterceptor].
  SequentialHttpInterceptor();

  /// Creates a new [SequentialHttpInterceptor] from the given handlers.
  ///
  /// This can be a convenient way to create an interceptor from a set of
  /// handlers, but it is recommended to create a subclass of [SequentialHttpInterceptor]
  /// and override the methods instead.
  factory SequentialHttpInterceptor.fromHandlers({
    Interceptor<BaseRequest, RequestHandler, void>? interceptRequest,
    Interceptor<StreamedResponse, ResponseHandler, void>? interceptResponse,
    Interceptor<Object, ErrorHandler, void>? interceptError,
  }) =>
      _SequentialHttpInterceptorWrapper(
        interceptRequest: interceptRequest,
        interceptResponse: interceptResponse,
        interceptError: interceptError,
      );

  /// Queue for requests
  final _requestQueue = _SequentialTaskQueue();

  /// Queue for responses
  final _responseQueue = _SequentialTaskQueue();

  /// Queue for errors
  final _errorQueue = _SequentialTaskQueue();

  @override
  Future<RequestState> $interceptRequest(
    BaseRequest request,
    RequestHandler handler,
  ) =>
      _queuedHandler(_requestQueue, request, handler, interceptRequest);

  @override
  Future<RequestState> $interceptResponse(
    StreamedResponse response,
    ResponseHandler handler,
  ) =>
      _queuedHandler(_responseQueue, response, handler, interceptResponse);

  @override
  Future<RequestState> $interceptError(
    Object error,
    ErrorHandler handler,
  ) =>
      _queuedHandler(_errorQueue, error, handler, interceptError);

  /// Enqueues the handler to the queue
  ///
  /// This method adds task to the queue and guarantees that it will be
  /// processed in sequence.
  Future<RequestState> _queuedHandler<T extends Object, H extends BaseHandler>(
    _SequentialTaskQueue taskQueue,
    T value,
    H handler,
    Interceptor<T, H, void> interceptor,
  ) {
    final task = _SequentialTask(interceptor: interceptor, value: value, handler: handler);
    return taskQueue.add(task);
  }
}

final class _SequentialHttpInterceptorWrapper extends SequentialHttpInterceptor {
  _SequentialHttpInterceptorWrapper({
    Interceptor<BaseRequest, RequestHandler, void>? interceptRequest,
    Interceptor<StreamedResponse, ResponseHandler, void>? interceptResponse,
    Interceptor<Object, ErrorHandler, void>? interceptError,
  })  : _$interceptRequest = interceptRequest,
        _$interceptResponse = interceptResponse,
        _$interceptError = interceptError;

  final Interceptor<BaseRequest, RequestHandler, void>? _$interceptRequest;
  final Interceptor<StreamedResponse, ResponseHandler, void>? _$interceptResponse;
  final Interceptor<Object, ErrorHandler, void>? _$interceptError;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    if (_$interceptRequest != null) {
      _$interceptRequest!(request, handler);
    } else {
      handler.next(request);
    }
  }

  @override
  void interceptResponse(StreamedResponse response, ResponseHandler handler) {
    if (_$interceptResponse != null) {
      _$interceptResponse!(response, handler);
    } else {
      handler.resolveResponse(response);
    }
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    if (_$interceptError != null) {
      _$interceptError!(error, handler);
    } else {
      handler.rejectError(error);
    }
  }
}
