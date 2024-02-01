part of 'client.dart';

typedef Interceptor<T extends Object, H extends Handler> = void Function(
  T value,
  H handler,
);

enum InterceptorAction {
  next,
  reject,
  rejectNext,
  resolve,
  resolveNext,
}

/// State of interceptor.
final class InterceptorState {
  const InterceptorState({
    required this.value,
    this.action = InterceptorAction.next,
  });

  final InterceptorAction action;
  final Object value;
}

/// Interceptor that is used for both requests and responses.
class HttpInterceptor {
  /// Creates a new [HttpInterceptor].
  const HttpInterceptor();

  /// Creates a new [HttpInterceptor] from the given handlers.
  factory HttpInterceptor.fromHandlers({
    Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    Interceptor<Response, ResponseHandler>? interceptResponse,
    Interceptor<Object, ErrorHandler>? interceptError,
  }) =>
      _HttpInterceptorWrapper(
        interceptRequest: interceptRequest,
        interceptResponse: interceptResponse,
        interceptError: interceptError,
      );

  /// Intercepts the request and returns a new request.
  void interceptRequest(BaseRequest request, RequestHandler handler) => handler.next(request);

  /// Intercepts the response and returns a new response.
  void interceptResponse(Response response, ResponseHandler handler) => handler.next(response);

  /// Intercepts the error and returns a new error or response.
  void interceptError(Object error, ErrorHandler handler) => handler.next(error);
}

final class _HttpInterceptorWrapper extends HttpInterceptor {
  _HttpInterceptorWrapper({
    Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    Interceptor<Response, ResponseHandler>? interceptResponse,
    Interceptor<Object, ErrorHandler>? interceptError,
  })  : _interceptRequest = interceptRequest,
        _interceptResponse = interceptResponse,
        _interceptError = interceptError;

  final Interceptor<BaseRequest, RequestHandler>? _interceptRequest;
  final Interceptor<Response, ResponseHandler>? _interceptResponse;
  final Interceptor<Object, ErrorHandler>? _interceptError;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    if (_interceptRequest != null) {
      _interceptRequest!(request, handler);
    } else {
      handler.next(request);
    }
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    if (_interceptResponse != null) {
      _interceptResponse!(response, handler);
    } else {
      handler.next(response);
    }
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    if (_interceptError != null) {
      _interceptError!(error, handler);
    } else {
      handler.next(error);
    }
  }
}

final class _TaskQueue<T> extends QueueList<T> {
  bool _isRunning = false;
}

/// Pair of value and handler.
typedef _ValueHandler<T extends Object, H extends Handler> = ({
  T value,
  H handler,
});

/// Sequential interceptor is type of [HttpInterceptor] that maintains
/// queues of requests and responses. It is used to intercept requests and
/// responses in the order they were added.
class SequentialHttpInterceptor extends HttpInterceptor {
  /// Creates a new [SequentialHttpInterceptor].
  SequentialHttpInterceptor();

  /// Creates a new [SequentialHttpInterceptor] from the given handlers.
  factory SequentialHttpInterceptor.fromHandlers({
    Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    Interceptor<Response, ResponseHandler>? interceptResponse,
    Interceptor<Object, ErrorHandler>? interceptError,
  }) =>
      _SequentialHttpInterceptorWrapper(
        interceptRequest: interceptRequest,
        interceptResponse: interceptResponse,
        interceptError: interceptError,
      );

  final _requestQueue = _TaskQueue<_ValueHandler<BaseRequest, RequestHandler>>();
  final _responseQueue = _TaskQueue<_ValueHandler<Response, ResponseHandler>>();
  final _errorQueue = _TaskQueue<_ValueHandler<Object, ErrorHandler>>();

  /// Method that enqueues the request.
  void _interceptRequest(BaseRequest request, RequestHandler handler) =>
      _queuedHandler(_requestQueue, request, handler, interceptRequest);

  /// Method that enqueues the response.
  void _interceptResponse(Response response, ResponseHandler handler) =>
      _queuedHandler(_responseQueue, response, handler, interceptResponse);

  /// Method that enqueues the error.
  void _interceptError(Object error, ErrorHandler handler) => _queuedHandler(
        _errorQueue,
        error,
        handler,
        interceptError,
      );

  void _queuedHandler<T extends Object, H extends Handler>(
    _TaskQueue<_ValueHandler<T, H>> taskQueue,
    T value,
    H handler,
    void Function(T value, H handler) intercept,
  ) {
    final task = (value: value, handler: handler);
    task.handler._processNextInQueue = () {
      if (taskQueue.isNotEmpty) {
        final nextTask = taskQueue.removeFirst();
        intercept(nextTask.value, nextTask.handler);
      } else {
        taskQueue._isRunning = false;
      }
    };

    taskQueue.add(task);

    if (!taskQueue._isRunning) {
      taskQueue._isRunning = true;
      final task = taskQueue.removeFirst();
      intercept(task.value, task.handler);
    }
  }
}

final class _SequentialHttpInterceptorWrapper extends SequentialHttpInterceptor {
  _SequentialHttpInterceptorWrapper({
    Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    Interceptor<Response, ResponseHandler>? interceptResponse,
    Interceptor<Object, ErrorHandler>? interceptError,
  })  : _$interceptRequest = interceptRequest,
        _$interceptResponse = interceptResponse,
        _$interceptError = interceptError;

  final Interceptor<BaseRequest, RequestHandler>? _$interceptRequest;
  final Interceptor<Response, ResponseHandler>? _$interceptResponse;
  final Interceptor<Object, ErrorHandler>? _$interceptError;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    if (_$interceptRequest != null) {
      _$interceptRequest!(request, handler);
    } else {
      handler.next(request);
    }
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
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
      handler.next(error);
    }
  }
}
