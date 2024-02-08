import 'package:http/http.dart';
import 'package:intercepted_client/client.dart';

class AuthInterceptor extends SequentialHttpInterceptor {
  final String token;

  AuthInterceptor(this.token);

  Future<String> refreshToken() async {
    // Refresh token
    return 'newToken';
  }

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) async {
    var t = token;

    // check if token is expired, if expired refresh token
    if (token == 'expiredToken') {
      t = await refreshToken();
    }

    request.headers['Authorization'] = 'Bearer $t';

    handler.next(request);
  }

  @override
  void interceptResponse(StreamedResponse response, ResponseHandler handler) {
    if (response.statusCode == 401) {
      // Refresh token and retry request
    }

    handler.next(response);
  }
}
