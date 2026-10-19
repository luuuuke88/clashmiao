import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

KernelFailure _kf(KernelFailureCode c, [String m = '']) =>
    KernelFailure(code: c, message: m, attempt: 1);

void main() {
  group('ConnectionFailure.fromKernel', () {
    test('每个内核失败码都有归宿', () {
      expect(
        ConnectionFailure.fromKernel(_kf(KernelFailureCode.startTimeout)),
        const StartTimeout(),
      );
      expect(
        ConnectionFailure.fromKernel(_kf(KernelFailureCode.permissionDenied)),
        const PermissionDenied(),
      );
      expect(
        ConnectionFailure.fromKernel(_kf(KernelFailureCode.kernelUnresponsive)),
        const KernelUnresponsive(),
      );
      expect(
        ConnectionFailure.fromKernel(_kf(KernelFailureCode.coreUnavailable)),
        const CoreUnavailable(),
      );
      for (final c in [
        KernelFailureCode.emptyConfiguration,
        KernelFailureCode.createService,
        KernelFailureCode.startService,
        KernelFailureCode.startCommandServer,
        KernelFailureCode.kernelExited,
      ]) {
        expect(
          ConnectionFailure.fromKernel(_kf(c, 'm')),
          KernelStartFailed(c, 'm'),
          reason: c.name,
        );
      }
      expect(
        ConnectionFailure.fromKernel(_kf(KernelFailureCode.unknown, 'u')),
        const UnexpectedFailure('u'),
      );
      // 穷尽：新增失败码时这里要跟着改。
      for (final c in KernelFailureCode.values) {
        expect(() => ConnectionFailure.fromKernel(_kf(c)), returnsNormally);
      }
    });

    test(
      '致命类（P4）：emptyConfiguration/createService/startService/startCommandServer/kernelUnresponsive',
      () {
        const fatal = {
          KernelFailureCode.emptyConfiguration,
          KernelFailureCode.createService,
          KernelFailureCode.startService,
          KernelFailureCode.startCommandServer,
          KernelFailureCode.kernelUnresponsive,
        };
        for (final c in KernelFailureCode.values) {
          expect(
            ConnectionFailure.fromKernel(_kf(c)).isFatal,
            fatal.contains(c),
            reason: c.name,
          );
        }
        expect(const NativeUnresponsive().isFatal, isFalse);
        expect(const NoActiveProfile().isFatal, isFalse);
      },
    );

    test('值相等', () {
      expect(const PlatformFailure('a', 'b'), const PlatformFailure('a', 'b'));
      expect(
        const PlatformFailure('a', 'b') == const PlatformFailure('a', 'c'),
        isFalse,
      );
      expect(
        const KernelStartFailed(KernelFailureCode.startService, 'x'),
        const KernelStartFailed(KernelFailureCode.startService, 'x'),
      );
    });
  });

  group('RequestOutcome', () {
    test('四种结果的值相等', () {
      expect(const RequestSucceeded(), const RequestSucceeded());
      expect(const RequestSuperseded(), const RequestSuperseded());
      expect(const RequestInterrupted(), const RequestInterrupted());
      expect(
        const RequestFailed(StartTimeout()),
        const RequestFailed(StartTimeout()),
      );
      expect(const RequestSucceeded() == const RequestSuperseded(), isFalse);
      expect(
        const RequestFailed(StartTimeout()) ==
            const RequestFailed(PermissionDenied()),
        isFalse,
      );
    });
  });

  group('ConnectionSnapshot', () {
    test('initial：resolving、busy、无失败', () {
      const s = ConnectionSnapshot.initial;
      expect(s.phase, ConnectionPhase.resolving);
      expect(s.isBusy, isTrue);
      expect(s.failure, isNull);
      expect(s.failureSeq, 0);
      expect(s.startedAt, isNull);
      expect(s.stale, isFalse);
    });

    test('值相等与 hashCode', () {
      final t = DateTime.utc(2026);
      final a = ConnectionSnapshot(
        phase: ConnectionPhase.connected,
        startedAt: t,
        failureSeq: 2,
        origin: DesiredSource.tile,
      );
      final b = ConnectionSnapshot(
        phase: ConnectionPhase.connected,
        startedAt: t,
        failureSeq: 2,
        origin: DesiredSource.tile,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a == const ConnectionSnapshot(phase: ConnectionPhase.connected),
        isFalse,
      );
    });
  });
}
