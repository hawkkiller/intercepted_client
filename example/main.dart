import 'package:http/http.dart';
import 'package:intercepted_client/intercepted_client.dart';

Future<void> main() async {
  final client = InterceptedClient(
    inner: Client(),
    interceptors: [
      HttpInterceptor.fromHandlers(
        interceptRequest: (value, handler) {
          print('Request: $value');
          handler.reject(value, next: true);
        },
        interceptError: (value, handler) {
          print('Error: $value');
          handler.reject('Hello World', next: true);
        },
      ),
    ],
  );

  final response = await client.get(Uri.parse('https://jsonplaceholder.typicode.com/todos/1'));

  print('Response: ${response.body}');
}
