/// The kinds of failure the UI needs to tell apart.
enum OpenAiErrorKind {
  /// No API key has been saved yet.
  missingKey,

  /// 401 — the key is wrong, revoked, or from another account.
  badKey,

  /// 429 with `insufficient_quota` — the account is out of credit.
  insufficientQuota,

  /// 429 — too many requests; worth retrying.
  rateLimited,

  /// 403/404 — the account can't use this model or endpoint.
  notAvailable,

  /// 400 — the request was rejected; the message says why.
  badRequest,

  /// 5xx — OpenAI's problem, worth retrying.
  serverError,

  /// No connectivity.
  network,

  /// The request took too long.
  timeout,

  /// A 200 whose body wasn't what we asked for.
  badResponse,
}

/// A failure talking to OpenAI, carrying a message that is safe and useful to
/// show the user.
///
/// Nothing here ever contains the API key: only response bodies and status
/// codes are quoted, never request headers.
class OpenAiException implements Exception {
  const OpenAiException(this.kind, this.message, {this.statusCode, this.retryAfter});

  final OpenAiErrorKind kind;
  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  /// Whether retrying the identical request could plausibly succeed.
  bool get isTransient =>
      kind == OpenAiErrorKind.rateLimited ||
      kind == OpenAiErrorKind.serverError ||
      kind == OpenAiErrorKind.network ||
      kind == OpenAiErrorKind.timeout;

  @override
  String toString() => message;
}
