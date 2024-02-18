part of 'client.dart';

typedef Interceptor<T extends Object, H extends Handler, R> = R Function(
  T value,
  H handler,
);

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

/// State of interceptor.
base class InterceptorState {
  InterceptorState({
    required this.request,
    this.action = InterceptorAction.next,
    this.response,
    this.error,
  });

  final InterceptorAction action;
  final BaseRequest? request;
  final StreamedResponse? response;
  final Object? error;

  InterceptorState copyWith({
    BaseRequest? request,
    StreamedResponse? response,
    Object? error,
    InterceptorAction? action,
  }) =>
      InterceptorState(
        request: request ?? this.request,
        response: response ?? this.response,
        error: error ?? this.error,
        action: action ?? this.action,
      );
}

/// Interceptor that is used for both requests and responses.
class HttpInterceptor {
  /// Creates a new [HttpInterceptor].
  const HttpInterceptor();

  /// Creates a new [HttpInterceptor] from the given handlers.
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

  /// Intercepts the request and returns a new request.
  void interceptRequest(
    BaseRequest request,
    RequestHandler handler,
  ) =>
      handler.next(request);

  /// Intercepts the response and returns a new response.
  void interceptResponse(
    StreamedResponse response,
    ResponseHandler handler,
  ) =>
      handler.resolveResponse(response);

  /// Intercepts the error and returns a new error or response.
  void interceptError(
    Object error,
    ErrorHandler handler,
  ) =>
      handler.rejectError(error, next: true);

  Future<InterceptorState> _interceptRequest(
    BaseRequest request,
    RequestHandler handler,
  ) {
    interceptRequest(request, handler);
    return handler._future;
  }

  Future<InterceptorState> _interceptResponse(
    StreamedResponse response,
    ResponseHandler handler,
  ) {
    interceptResponse(response, handler);
    return handler._future;
  }

  Future<InterceptorState> _interceptError(
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

final class _Task<T extends Object, H extends Handler> {
  _Task({
    required Interceptor<T, H, void> interceptor,
    required this.value,
    required H handler,
  })  : _interceptor = interceptor,
        _handler = handler;

  final Interceptor<T, H, void> _interceptor;
  final T value;
  final H _handler;

  Future<InterceptorState> call() {
    _interceptor(value, _handler);

    return _handler._future;
  }

  /// Returns the future of the handler.
  Future<InterceptorState> get future => _handler._future;
}

final class _TaskQueue extends QueueList<_Task> {
  _TaskQueue() : super(5);

  /// Returns `true` if the queue is processing.
  bool get isProcessing => length > 0;

  bool _closed = false;
  Future<void>? _processing;

  @override
  Future<InterceptorState> add(_Task element) async {
    super.add(element);
    _run();

    return element.future;
  }

  /// Closes the queue.
  Future<void> close() async {
    await _processing;
    _closed = true;
  }

  /// Runs the queue.
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

/// Sequential interceptor is type of [HttpInterceptor] that maintains
/// queues of requests and responses. It is used to intercept requests and
/// responses in the order they were added.
class SequentialHttpInterceptor extends HttpInterceptor {
  /// Creates a new [SequentialHttpInterceptor].
  SequentialHttpInterceptor();

  /// Creates a new [SequentialHttpInterceptor] from the given handlers.
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

  final _requestQueue = _TaskQueue();
  final _responseQueue = _TaskQueue();
  final _errorQueue = _TaskQueue();

  @override
  Future<InterceptorState> _interceptRequest(
    BaseRequest request,
    RequestHandler handler,
  ) =>
      _queuedHandler(_requestQueue, request, handler, interceptRequest);

  @override
  Future<InterceptorState> _interceptResponse(
    StreamedResponse response,
    ResponseHandler handler,
  ) =>
      _queuedHandler(_responseQueue, response, handler, interceptResponse);

  @override
  Future<InterceptorState> _interceptError(
    Object error,
    ErrorHandler handler,
  ) =>
      _queuedHandler(_errorQueue, error, handler, interceptError);

  Future<InterceptorState> _queuedHandler<T extends Object, H extends Handler>(
    _TaskQueue taskQueue,
    T value,
    H handler,
    Interceptor<T, H, void> interceptor,
  ) {
    final task = _Task(interceptor: interceptor, value: value, handler: handler);
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
