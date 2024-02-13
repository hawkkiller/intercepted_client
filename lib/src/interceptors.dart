part of 'client.dart';

typedef Interceptor<T extends Object, H extends Handler, R> = R Function(
  T value,
  H handler,
);

enum InterceptorAction {
  next,
  reject,
  rejectAllowNext,
  resolve,
  resolveAllowNext,
}

/// State of interceptor.
base class InterceptorState<T> {
  const InterceptorState({
    required this.value,
    this.action = InterceptorAction.next,
  });

  final InterceptorAction action;
  final T value;
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
      handler.next(response);

  /// Intercepts the error and returns a new error or response.
  void interceptError(
    Object error,
    ErrorHandler handler,
  ) =>
      handler.reject(error, next: true);

  Future<InterceptorState> _interceptRequest(BaseRequest request, RequestHandler handler) async {
    interceptRequest(request, handler);
    return handler.future;
  }

  Future<InterceptorState> _interceptResponse(
      StreamedResponse response, ResponseHandler handler) async {
    interceptResponse(response, handler);
    return handler.future;
  }

  Future<InterceptorState> _interceptError(Object error, ErrorHandler handler) async {
    interceptError(error, handler);
    return handler.future;
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
      handler.next(response);
    }
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    if (_$interceptError != null) {
      _$interceptError!(error, handler);
    } else {
      handler.reject(error, next: true);
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
  T value;
  final H _handler;

  final _completer = Completer<InterceptorState>();

  Future<InterceptorState> call() async {
    _interceptor(value, _handler);
    final result = await _handler.future;

    if (!_completer.isCompleted) {
      _completer.complete(result);
    }

    return result;
  }

  void reject(Object error, StackTrace stackTrace) {
    _completer.completeError(
      InterceptorState(value: error, action: InterceptorAction.next),
      stackTrace,
    );
  }

  Future<InterceptorState> get future => _completer.future;
}

final class _TaskQueue extends QueueList<_Task> {
  _TaskQueue() : super(5);

  bool get isProcessing => length > 0;
  bool _closed = false;

  Future<void>? _processing;

  @override
  Future<InterceptorState> add(_Task element) async {
    super.add(element);
    _run();
    return element.future;
  }

  Future<void> close() async {
    await _processing;
    _closed = true;
  }

  void _run() => _processing ??= Future(() async {
        while (isProcessing) {
          final elem = first;
          if (_closed) return;
          try {
            await elem();
          } on Object catch (e, stackTrace) {
            elem.reject(e, stackTrace);
          } finally {
            removeFirst();
          }
        }
        _processing = null;
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

  /// Method that enqueues the request.
  @override
  Future<InterceptorState> _interceptRequest(BaseRequest request, RequestHandler handler) =>
      _queuedHandler(_requestQueue, request, handler, interceptRequest);

  /// Method that enqueues the response.
  @override
  Future<InterceptorState> _interceptResponse(StreamedResponse response, ResponseHandler handler) =>
      _queuedHandler(_responseQueue, response, handler, interceptResponse);

  /// Method that enqueues the error.
  @override
  Future<InterceptorState> _interceptError(Object error, ErrorHandler handler) => _queuedHandler(
        _errorQueue,
        error,
        handler,
        interceptError,
      );

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
      handler.next(response);
    }
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    if (_$interceptError != null) {
      _$interceptError!(error, handler);
    } else {
      handler.reject(error, next: true);
    }
  }
}
