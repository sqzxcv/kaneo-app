import 'dart:convert';

import 'package:dio/dio.dart';

import '../i18n/i18n.dart';
import '../session/session.dart';

/// A failed request. [message] is ready to show a person.
class ApiError implements Exception {
  const ApiError(this.message, {this.status, this.body});

  final String message;

  /// Null when the request never got a response.
  final int? status;
  final Object? body;

  @override
  String toString() => 'ApiError($status): $message';
}

/// Credentials for a request made outside the current session, such as while signing in.
class ApiCredentials {
  const ApiCredentials(this.type, this.token);

  final CredentialType type;
  final String token;
}

/// A response with its headers, for callers that need more than the body.
class ApiResponse {
  const ApiResponse(this.status, this.headers, this.body);

  final int status;
  final Map<String, List<String>> headers;
  final Object? body;

  bool get isOk => status >= 200 && status < 300;

  String? header(String name) => headers[name.toLowerCase()]?.firstOrNull;
}

/// Normalizes what a person typed into an instance origin: adds a scheme, drops a trailing slash
/// and a trailing `/api`, so both `kaneo.example.com` and `https://kaneo.example.com/api` work.
String normalizeServerUrl(String input) {
  var url = input.trim().replaceFirst(RegExp(r'/+$'), '');
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) url = 'https://$url';
  if (url.endsWith('/api')) url = url.substring(0, url.length - 4);
  return url.replaceFirst(RegExp(r'/+$'), '');
}

/// Resolves a possibly relative asset path, such as `/api/asset/...`, against the instance.
String? resolveUrl(String serverUrl, String? path) {
  if (path == null || path.isEmpty) return null;
  if (RegExp(r'^(https?:|data:)').hasMatch(path)) return path;
  return '${serverUrl.replaceFirst(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}';
}

/// The headers that authenticate a request. API keys go in `x-api-key`.
Map<String, String> credentialHeaders(CredentialType type, String token) =>
    type == CredentialType.apiKey ? {'x-api-key': token} : {'Authorization': 'Bearer $token'};

/// Kaneo's validators mostly treat absent fields as "leave unset" and reject `null`, so null
/// properties are dropped unless a route needs an explicit null (unassign, clear avatar).
Object? _withoutNulls(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.value != null) entry.key: _withoutNulls(entry.value),
    };
  }
  if (value is List) return value.map(_withoutNulls).toList();
  return value;
}

/// Sends requests to the signed-in server and turns failures into [ApiError].
class ApiClient {
  ApiClient({
    required this._session,
    required this._i18n,
    required this._onSessionExpired,
    this._onServerReach,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 30),
           sendTimeout: const Duration(seconds: 30),
           responseType: ResponseType.plain,
           validateStatus: (_) => true,
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final Session? Function() _session;
  final I18n _i18n;
  final void Function(Session expired) _onSessionExpired;

  /// Told after each request to the signed-in server whether it got there: true for any answer,
  /// errors too, and false when there was none.
  final void Function(bool reached)? _onServerReach;
  final Dio _dio;

  /// Sends a request and returns the parsed body, or throws [ApiError] on any failure.
  ///
  /// [serverUrl] and [credentials] override the session, for signing in before one exists.
  Future<Object?> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? query,
    Object? body,
    String? serverUrl,
    ApiCredentials? credentials,
    bool keepNulls = false,
  }) async {
    final session = _session();
    final response = await requestRaw(
      path,
      method: method,
      query: query,
      body: body,
      serverUrl: serverUrl,
      credentials: credentials,
      keepNulls: keepNulls,
    );
    if (response.isOk) return response.body;

    // Only expire the session the request was made with, not one signed in since.
    if (response.status == 401 &&
        session != null &&
        _session()?.token == session.token &&
        !path.startsWith('api/auth/') &&
        credentials == null) {
      _onSessionExpired(session);
    }
    throw ApiError(
      httpMessage(response.status, response.body),
      status: response.status,
      body: response.body,
    );
  }

  /// Like [request], but returns the response whatever its status, with its headers.
  Future<ApiResponse> requestRaw(
    String path, {
    String method = 'GET',
    Map<String, Object?>? query,
    Object? body,
    String? serverUrl,
    ApiCredentials? credentials,
    bool keepNulls = false,
  }) async {
    final session = _session();
    final server = serverUrl ?? session?.serverUrl;
    if (server == null) throw ApiError(_i18n.t('mobile:errors.notSignedIn'));
    final creds =
        credentials ??
        (session != null && server == session.serverUrl
            ? ApiCredentials(session.credentialType, session.token)
            : null);

    final headers = <String, String>{
      'Accept': 'application/json',
      if (creds != null) ...credentialHeaders(creds.type, creds.token),
      if (body != null) 'Content-Type': 'application/json',
    };

    // Requests to another server, such as while signing in, say nothing about this one.
    final reach = session != null && server == session.serverUrl ? _onServerReach : null;
    final Response<String> response;
    try {
      response = await _dio.request<String>(
        '$server/${path.replaceFirst(RegExp(r'^/+'), '')}',
        queryParameters: {
          if (query != null)
            for (final entry in query.entries)
              if (entry.value != null) entry.key: entry.value.toString(),
        },
        data: body == null ? null : jsonEncode(keepNulls ? body : _withoutNulls(body)),
        options: Options(method: method, headers: headers),
      );
    } on DioException {
      reach?.call(false);
      throw ApiError(_i18n.t('mobile:errors.unreachable'));
    }
    reach?.call(true);
    return ApiResponse(response.statusCode ?? 0, response.headers.map, _parse(response.data));
  }

  Object? _parse(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  /// The readable message for a failed status: the server's own if it sent one.
  String httpMessage(int status, Object? body) {
    final message = _messageFrom(body);
    if (message != null) return message;
    if (status == 401) return _i18n.t('mobile:errors.sessionExpired');
    if (status == 403) return _i18n.t('mobile:errors.forbidden');
    if (status == 404) return _i18n.t('mobile:errors.notFound');
    if (status == 429) return _i18n.t('mobile:errors.tooManyRequests');
    if (status >= 500) return _i18n.t('mobile:errors.serverProblem', {'status': status});
    return _i18n.t('mobile:errors.requestFailed', {'status': status});
  }

  String? _messageFrom(Object? body) {
    if (body is String) return body.length < 200 && !body.trimLeft().startsWith('<') ? body : null;
    if (body is! Map) return null;
    final message = body['message'];
    if (message is String) return message;
    final error = body['error'];
    if (error is Map && error['message'] is String) return error['message'] as String;
    if (error is String) return error;
    return null;
  }
}
