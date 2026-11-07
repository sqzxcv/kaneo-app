/// The shared entry points. Pages import this instead of the individual files.
///
/// `lib/core/` only grows: add to it freely, but do not change the parameters of what is here.
library;

export 'api/api_client.dart';
export 'api/board_loader.dart';
export 'api/kaneo_api.dart';
export 'api/models.dart';
export 'cache/cache_store.dart';
export 'cache/cached_query.dart';
export 'config/dev_config.dart';
export 'data/queries.dart';
export 'errors.dart';
export 'format/dates.dart';
export 'format/project_icons.dart';
export 'format/style.dart';
export 'i18n/i18n.dart';
export 'i18n/language_choice.dart';
export 'i18n/resolve_locale.dart';
export 'layout/breakpoints.dart';
export 'layout/content_width.dart';
export 'providers.dart';
export 'realtime/realtime.dart';
export 'realtime/realtime_connection.dart';
export 'router/app_router.dart';
export 'session/session.dart';
export 'session/authentication.dart';
export '../platform/authenticated_socket.dart';
export 'theme/app_theme.dart';
export 'ui/action.dart';
export 'ui/async_body.dart';
export 'ui/confirm.dart';
export 'ui/menu.dart';
export 'ui/pickers.dart';
export 'ui/placeholder_page.dart';
export 'ui/popover.dart';
export 'ui/toast.dart';

export 'notifications/settings.dart';
export '../platform/desktop/desktop_host.dart';
export '../platform/desktop/desktop_provider.dart';
export '../platform/desktop/desktop_runtime.dart';
