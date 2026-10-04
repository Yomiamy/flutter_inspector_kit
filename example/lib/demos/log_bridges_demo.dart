import 'package:logger/logger.dart' show Logger;
import 'package:logging/logging.dart' as logging;
import 'package:talker/talker.dart' show Talker;

/// Sends one record per level through logger, talker and logging, plus one
/// error with a stack trace each, so the bridges wired in `main()` can be
/// checked in the Console tab: level colours, red error rows and
/// `⚡ Errors only`.
class LogBridgesDemo {
  LogBridgesDemo(this._talker);

  final Talker _talker;
  final Logger _logger = Logger();
  final logging.Logger _log = logging.Logger('Demo');

  void emitAll() {
    final error = StateError('Demo: bridged error');
    final stackTrace = StackTrace.current;

    _logger
      ..t('logger trace')
      ..d('logger debug')
      ..i('logger info')
      ..w('logger warning')
      ..e('logger error')
      ..f('logger fatal')
      ..e('logger caught', error: error, stackTrace: stackTrace);

    _talker
      ..verbose('talker verbose')
      ..debug('talker debug')
      ..info('talker info')
      ..warning('talker warning')
      ..error('talker error')
      ..critical('talker critical')
      ..handle(error, stackTrace, 'talker caught');

    _log
      ..finest('logging finest')
      ..finer('logging finer')
      ..fine('logging fine')
      ..config('logging config')
      ..info('logging info')
      ..warning('logging warning')
      ..severe('logging severe')
      ..shout('logging shout')
      ..severe('logging caught', error, stackTrace);
  }
}
