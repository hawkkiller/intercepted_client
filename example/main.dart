import 'package:http/http.dart';
import 'package:intercepted_client/intercepted_client.dart';
import 'package:intercepted_client/src/intercepted_client.dart';

class AuthInterceptor extends SequentialHttpInterceptor {
  final String token;

  AuthInterceptor(this.token);

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    request.headers['Authorization'] = 'Bearer $token';

    handler.next(request);
  }
}

class LogInterceptor extends HttpInterceptor {
  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    print('Request: ${request.url}');
    handler.next(request);
  }

  @override
  void interceptResponse(StreamedResponse response, ResponseHandler handler) {
    print('Request: ${handler.request.url} - Status: ${response.statusCode}');
    handler.resolveResponse(response);
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    print('Error: $error');
    handler.rejectError(error);
  }
}

Future<void> main() async {
  final Client client = InterceptedClient(
    interceptors: [
      AuthInterceptor('my-token'),
      LogInterceptor(),
    ],
  );

  final response = await client.get(Uri.parse('https://example.com'));

  // prints 'Bearer my-token'
  print(response.request?.headers['Authorization']);
}
