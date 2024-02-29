part of 'client.dart';

/// Interceptor signature.
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
  ///
  /// It can't be null as it is always initialized.
  final BaseRequest request;

  /// The actual response.
  ///
  /// It can be modified by interceptors or changed to another response
  /// if needed (for example, when retrying request).
  ///
  /// It can be null if request was not sent or if error occurred.
  final StreamedResponse? response;

  /// The error that occurred.
  ///
  /// It can be modified by interceptors or changed to another error.
  /// You may expect to see [SocketException] or [HttpException] here.
  ///
  /// It can be null if request was sent successfully and if response was received.
  final Object? error;

  /// Creates a copy of this state with the given fields replaced by the new values.
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

/// Base class for interceptor handlers.
/// 
/// It is used to handle the request, response, and error.
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

  /// Intercepts the request
  /// 
  /// This method can update existing request or create a new one.
  void interceptRequest(
    BaseRequest request,
    RequestHandler handler,
  ) =>
      handler.next(request);

  /// Intercepts the response
  /// 
  /// This method can update existing response or create a new one.
  void interceptResponse(
    StreamedResponse response,
    ResponseHandler handler,
  ) =>
      handler.resolveResponse(response);

  /// Intercepts the error
  /// 
  /// This method can update existing error or create a new one.
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

/// Sequential task for the queue.
final class _SequentialTask<T extends Object, H extends Handler> {
  _SequentialTask({
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

/// Queue of sequential tasks.
final class _SequentialTaskQueue extends QueueList<_SequentialTask> {
  _SequentialTaskQueue() : super(5);

  /// Returns `true` if the queue is processing.
  bool get isProcessing => length > 0;

  bool _closed = false;
  Future<void>? _processing;

  @override
  Future<InterceptorState> add(_SequentialTask element) async {
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

  final _requestQueue = _SequentialTaskQueue();
  final _responseQueue = _SequentialTaskQueue();
  final _errorQueue = _SequentialTaskQueue();

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
