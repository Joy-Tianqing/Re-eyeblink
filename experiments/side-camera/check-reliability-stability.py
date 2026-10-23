"""Bind offline reliability regressions to the current signed arm64 snapshot."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[2]
folder = root / 'evidence/native-tests'
prefix = 'reliability-stability'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
required = [
    'testAcquisitionRequiresWholeWindowStabilityInsteadOfAdjacentFrameStability',
    'testReacquisitionCannotWalkItsConfirmationWindowAwayFromLostAnchor',
    'testGradualYawChangeCannotMixOpenEyeBaselinesAndSettlingRecovers',
    'testGradualPitchChangeCannotMixOpenEyeBaselinesAndSettlingRecovers',
    'testEachPlatformFailureBeforeQueuedDeadlineEmitsOneFailureAndCancelsEngineMeasurement',
    'testCompletedDeadlineRejectsLaterPlatformFailureAndDuplicateCompletion',
    'testStaleFailureCannotStopReplacementLeaseAndNewLeaseCanPrimeAfterFailure',
    'testInterruptionMatchesSessionAndCollapsesFollowingRuntimeError',
    'testAlreadyQueuedFailureCannotTerminateReplacementLease',
    'testIntentionalStopAndDestructionUnregisterNotifications',
    'testBystanderCannotConsumeUsersBlinkOrResetCalibrationAcrossTenClosures',
    'testTargetLossOrAmbiguityCannotCompleteHalfBlinkAndReacquisitionRequiresCalibration',
    'testFullDurationBystanderStreamRetainsCoverageAndVersionedProvenance',
    'testActualVisionKeepsEstablishedPrimaryGeometryWhenPublicBystanderAppears',
    'testSideModeDeadlineBeforePixelAcquisitionCarriesZeroCoverageAndLatches',
    'testOriginalPixelsThroughPendingCandidateLossRecoveryAndActualReopenReference']
for suffix, expected in [('full-swift.log', 206), ('release.log', 119)]:
    log = (folder / f'{prefix}-{suffix}').read_text()
    counts = re.findall(r'Executed (\d+) tests, with 0 failures', log)
    assert counts and int(counts[-1]) == expected, (suffix, counts)
    assert 'skipped' not in log.lower()
    for test in required:
        assert test + "]' passed" in log, (suffix, test)
build = json.loads((root / 'evidence/native-build.json').read_text())
assert len(build['machO']) == 1 and build['machO'][0]['architectures'] == ['arm64']
assert sha(root / 'build/Eyeblink.app/Contents/MacOS/Eyeblink') == build['machO'][0]['sha256']
assert all(sha(root / path) == digest for path, digest in build['sources'].items())
assert 'PASS:' in (folder / f'{prefix}-package-verification.log').read_text()
package = json.loads((folder / f'{prefix}-package.json').read_text())
assert package['executableSHA256'] == build['machO'][0]['sha256']
for key in ['historyUnchanged', 'settingsUnchanged', 'originalFiveFilesUnchanged',
            'originalExecutableUnchanged', 'customIconUnchanged', 'appNotRunningAfterOfflineWork']:
    assert package[key], key
assert not package['liveCameraOpenedForThisCheckpoint']
report = {
    'date': '2026-10-22', 'status': 'PASS',
    'scope': 'Offline geometry/contour, NotificationCenter/frame-run/Core terminal ordering, public-image Vision, original regressions and signed package. No live camera.',
    'algorithm': 'side-contour-v4', 'targeting': 'spatial-primary-v2',
    'swiftTests': 206, 'coreTests': 151, 'appTests': 55,
    'releaseSelectedTests': 119, 'newTests': 8,
    'requiredTests': required,
    'executableSHA256': build['machO'][0]['sha256'],
    'contracts': [
        'Whole acquisition/reconfirmation window retains its initial rectangle',
        'Open-eye learning cannot pool a slow head turn outside its initial yaw/pitch window; settling recovers',
        'Runtime/disconnect/interruption notifications and all frame terminal events share capture FIFO and one latch',
        'First terminal event wins; later faults/completions and stale generations are ignored',
        'Failed lease cannot consume queued clocks/pixels; replacement can prime',
        'Single camera arbitration, full 180-second deadline, 85-percent quality gate and old user data retained'],
    'limitations': [
        'Synthetic closures and public images do not establish natural blink recall or timing accuracy',
        'Spatial tracking is not identity recognition; single-eye closure is an estimate',
        'Notification injection does not emulate AVFoundation hardware queueing, physical disconnect or system sleep',
        'Current-package human camera and full successful measurement acceptance explicitly deferred'],
    'sourceManifest': 'evidence/native-tests/n115-native-build.json',
    'logsSHA256': {suffix: sha(folder / f'{prefix}-{suffix}') for suffix in ['full-swift.log','release.log','targeted.log']}
}
(folder / f'{prefix}-integration-check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print('PASS: 206 Swift / 119 release; 8 new regressions; signed arm64 sources/data match. Live acceptance deferred.')
