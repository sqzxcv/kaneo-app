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
  if [[ -n "${FAKE_XCRUN_HANG_BOOT:-}" ]]; then
    sleep 300
  fi
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

  Future<Process> start(List<String> arguments, {int? timeout}) => Process.start(
    'bash',
    ['tool/with_device.sh', ...arguments],
    environment: {...environment, if (timeout != null) 'KANEO_DEVICE_TIMEOUT': '$timeout'},
  );

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

  group('timeout', () {
    bool isRunning(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

    Future<int> readPid(File file) async {
      while (!file.existsSync() || file.readAsStringSync().trim().isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return int.parse(file.readAsStringSync().trim());
    }

    Future<void> expectGone(int pid) async {
      for (var i = 0; i < 100 && isRunning(pid); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(isRunning(pid), isFalse, reason: 'process $pid should be gone');
    }

    test('a hung command is killed with its children, and the queue is free again', () async {
      final child = File('${directory.path}/child');
      final hung = await start([
        'bash',
        '-c',
        'sleep 300 & echo \$! > "${child.path}"; wait',
      ], timeout: 1);
      final errors = hung.stderr.transform(const SystemEncoding().decoder).join();
      expect(await hung.exitCode, 124);
      expect(await errors, contains('timed out after 1 seconds'));
      await expectGone(await readPid(child));

      final next = await start(['true']);
      expect(await next.exitCode.timeout(const Duration(seconds: 5)), 0);
    });

    test('a command that ignores TERM is killed anyway', () async {
      final pidFile = File('${directory.path}/pid');
      final stubborn = await start([
        'bash',
        '-c',
        'trap "" TERM; echo \$\$ > "${pidFile.path}"; while :; do sleep 0.1; done',
      ], timeout: 1);
      expect(await stubborn.exitCode, 124);
      await expectGone(await readPid(pidFile));
    });

    test('a process outside the command stays alive, even in the caller\'s group', () async {
      final sibling = File('${directory.path}/sibling');
      // A shell without job control keeps both its background job and the script in its own group.
      final caller = await Process.start(
        'bash',
        [
          '-c',
          // It must not keep the output open, or reading the output would wait for it.
          'sleep 300 >/dev/null 2>&1 & echo \$! > "${sibling.path}"; '
              'bash tool/with_device.sh sleep 300; echo \$?',
        ],
        environment: {...environment, 'KANEO_DEVICE_TIMEOUT': '1'},
      );
      final output = caller.stdout.transform(const SystemEncoding().decoder).join();
      final pid = await readPid(sibling);
      addTearDown(() => Process.killPid(pid));
      expect(await caller.exitCode, 0);
      expect((await output).trim(), '124');
      expect(isRunning(pid), isTrue);
    });

    test('only the simulator it started is shut down', () async {
      final hung = await start(['--boot', 'iPhone 17', 'sleep', '300'], timeout: 1);
      expect(await hung.exitCode, 124);
      final calls = xcrunCalls();
      expect(calls.where((c) => c.startsWith('simctl shutdown')), ['simctl shutdown $_iPhone']);
      expect(calls.any((c) => c.contains('shutdown all')), isFalse);
    });

    test('a simulator that never boots counts against the limit', () async {
      environment['FAKE_XCRUN_HANG_BOOT'] = '1';
      final hung = await start(['--boot', 'iPhone 17', ...job('never')], timeout: 1);
      expect(await hung.exitCode, 124);
      expect(log.existsSync(), isFalse);
      expect(xcrunCalls(), contains('simctl shutdown $_iPhone'));
    });

    test('time spent in line does not count', () async {
      final first = await start(job('a', seconds: 2));
      while (!log.existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final second = await start(job('b', seconds: 0), timeout: 1);
      expect(await first.exitCode, 0);
      expect(await second.exitCode, 0);
      expect(log.readAsLinesSync().last, 'end-b');
    });

    test('a command that itself exits with 124 is not reported as a timeout', () async {
      final process = await start(['bash', '-c', 'exit 124']);
      final errors = process.stderr.transform(const SystemEncoding().decoder).join();
      expect(await process.exitCode, 124);
      expect(await errors, isNot(contains('timed out')));
    });

    test('stopping the script stops the command, which runs in its own group', () async {
      final pids = File('${directory.path}/pids');
      final process = await start([
        'bash',
        '-c',
        'echo "\$PPID \$\$" > "${pids.path}.tmp"; mv "${pids.path}.tmp" "${pids.path}"; exec sleep 300',
      ]);
      while (!pids.existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final [script, command] = pids.readAsStringSync().trim().split(' ').map(int.parse).toList();
      Process.killPid(script);
      await expectGone(command);
      expect(await process.exitCode, 143);
    });

    test('a limit that is not a number of seconds fails before joining the queue', () async {
      environment['KANEO_DEVICE_TIMEOUT'] = '20m';
      final process = await start(job('never'));
      final errors = process.stderr.transform(const SystemEncoding().decoder).join();
      expect(await process.exitCode, 2);
      expect(await errors, contains('KANEO_DEVICE_TIMEOUT'));
      expect(log.existsSync(), isFalse);
    });
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
