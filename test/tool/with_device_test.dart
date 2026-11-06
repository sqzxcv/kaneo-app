@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Stands in for `xcrun` so the script's simulator handling can run anywhere.
const _fakeXcrun = r'''#!/usr/bin/env bash
state="$FAKE_XCRUN_STATE"
echo "$*" >>"$state/calls"
case "$1 $2 $3" in
"simctl list devices")
  if [[ "$4" == "booted" ]]; then
    cat "$state/booted"
  else
    echo "== Devices =="
    echo "    iPhone 17 Pro (AAAAAAAA-0000-0000-0000-000000000002) (Shutdown)"
    echo "    iPhone 17 (AAAAAAAA-0000-0000-0000-000000000001) (Shutdown)"
    echo "    iPad Pro 13-inch (M5) (AAAAAAAA-0000-0000-0000-000000000003) (Shutdown)"
  fi
  ;;
"simctl bootstatus "*)
  echo "    Booted device ($2) ($3) (Booted)" >>"$state/booted"
  ;;
esac
''';

const _appleTv = '3CF267E7-5259-4E32-B62C-BF51B3FF982F';
const _iPhone = 'AAAAAAAA-0000-0000-0000-000000000001';
const _iPad = 'AAAAAAAA-0000-0000-0000-000000000003';

void main() {
  late Directory directory;
  late File log;
  late Directory state;
  late Map<String, String> environment;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('with-device');
    addTearDown(() => directory.delete(recursive: true));
    log = File('${directory.path}/log');
    state = await Directory('${directory.path}/state').create();
    File('${state.path}/booted')
        .writeAsStringSync('    Apple TV 4K (3rd generation) ($_appleTv) (Booted)\n');
    final bin = await Directory('${directory.path}/bin').create();
    final xcrun = File('${bin.path}/xcrun')..writeAsStringSync(_fakeXcrun);
    await Process.run('chmod', ['+x', xcrun.path]);
    environment = {
      'KANEO_DEVICE_LOCK': '${directory.path}/device.lock',
      'FAKE_XCRUN_STATE': state.path,
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
    };
  });

  Future<Process> start(List<String> arguments) =>
      Process.start('bash', ['tool/with_device.sh', ...arguments], environment: environment);

  List<String> xcrunCalls() {
    final calls = File('${state.path}/calls');
    return calls.existsSync() ? calls.readAsLinesSync() : const [];
  }

  /// A command that writes when it starts and when it ends.
  List<String> job(String name, {double seconds = 1}) => [
    'bash',
    '-c',
    'echo start-$name >> "${log.path}"; sleep $seconds; echo end-$name >> "${log.path}"',
  ];

  test('a second process waits until the first has finished', () async {
    final first = await start(job('a'));
    while (!log.existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final second = await start(job('b', seconds: 0));
    final secondErrors = second.stderr.transform(const SystemEncoding().decoder).join();

    expect(await first.exitCode, 0);
    expect(await second.exitCode, 0);
    expect(log.readAsLinesSync(), ['start-a', 'end-a', 'start-b', 'end-b']);
    expect(await secondErrors, contains('waiting for the device queue'));
  });

  test('five processes run one at a time', () async {
    final jobs = [for (var i = 0; i < 5; i++) await start(job('$i', seconds: 0.1))];
    for (final process in jobs) {
      expect(await process.exitCode, 0);
    }
    final lines = log.readAsLinesSync();
    expect(lines, hasLength(10));
    for (var i = 0; i < 10; i += 2) {
      expect(lines[i + 1], lines[i].replaceFirst('start-', 'end-'));
    }
  });

  test('the command\'s exit code comes through and the queue is free afterwards', () async {
    final failed = await start(['bash', '-c', 'exit 7']);
    expect(await failed.exitCode, 7);
    final next = await start(['true']);
    expect(await next.exitCode, 0);
  });

  test('a command killed outright does not block the queue', () async {
    final pidFile = File('${directory.path}/pid');
    final holder = await start(['bash', '-c', 'echo \$\$ > "${pidFile.path}"; exec sleep 60']);
    while (!pidFile.existsSync() || pidFile.readAsStringSync().trim().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    Process.killPid(int.parse(pidFile.readAsStringSync().trim()), ProcessSignal.sigkill);
    expect(await holder.exitCode, isNonZero);
    final next = await start(['true']);
    expect(await next.exitCode.timeout(const Duration(seconds: 5)), 0);
  });

  test('without a command it explains itself and fails', () async {
    final process = await start(const []);
    final errors = process.stderr.transform(const SystemEncoding().decoder).join();
    expect(await process.exitCode, 2);
    expect(await errors, contains('--boot'));
  });

  group('simulators', () {
    test('--boot starts the named simulator and shuts down only that one', () async {
      final process = await start(['--boot', 'iPhone 17', 'true']);
      expect(await process.exitCode, 0);
      final calls = xcrunCalls();
      expect(calls, contains('simctl bootstatus $_iPhone -b'));
      expect(calls, contains('simctl shutdown $_iPhone'));
      expect(calls.where((c) => c.startsWith('simctl shutdown')), hasLength(1));
      expect(calls.any((c) => c.contains('shutdown all')), isFalse);
      expect(calls.any((c) => c.contains('shutdown $_appleTv')), isFalse);
    });

    test('names with brackets work, and --boot can repeat', () async {
      final process = await start([
        '--boot',
        'iPad Pro 13-inch (M5)',
        '--boot',
        'iPhone 17',
        'true',
      ]);
      expect(await process.exitCode, 0);
      final calls = xcrunCalls();
      expect(calls, contains('simctl shutdown $_iPad'));
      expect(calls, contains('simctl shutdown $_iPhone'));
    });

    test('a simulator that was already running stays running', () async {
      final process = await start(['--boot', _appleTv, 'true']);
      expect(await process.exitCode, 0);
      expect(xcrunCalls().any((c) => c.startsWith('simctl shutdown')), isFalse);
      expect(xcrunCalls().any((c) => c.startsWith('simctl bootstatus')), isFalse);
    });

    test('a simulator someone else starts during the command stays running', () async {
      final process = await start([
        'bash',
        '-c',
        'echo "    iPhone 17 Pro (AAAAAAAA-0000-0000-0000-000000000002) (Booted)" >> "${state.path}/booted"',
      ]);
      expect(await process.exitCode, 0);
      expect(xcrunCalls().any((c) => c.startsWith('simctl shutdown')), isFalse);
    });

    test('the simulator is shut down even when the command fails', () async {
      final process = await start(['--boot', 'iPhone 17', 'bash', '-c', 'exit 3']);
      expect(await process.exitCode, 3);
      expect(xcrunCalls(), contains('simctl shutdown $_iPhone'));
    });

    test('an unknown simulator name stops before running the command', () async {
      final process = await start(['--boot', 'iPhone 1', ...job('never')]);
      expect(await process.exitCode, 1);
      expect(log.existsSync(), isFalse);
    });
  });
}
