import 'package:http/http.dart';
import 'package:intercepted_client/intercepted_client.dart';

class AuthInterceptor extends SequentialHttpInterceptor {
  final String token;

  AuthInterceptor(this.token);

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    request.headers['Authorization'] = 'Bearer $token';

    handler.next(request);
  }
}

Future<void> main() async {
  final Client client = InterceptedClient(
    interceptors: [
      AuthInterceptor('my-token'),
    ],
  );

  final response = await client.get(Uri.parse('https://example.com'));

  // prints 'Bearer my-token'
  print(response.request?.headers['Authorization']);
}
