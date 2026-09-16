import localUnitTest from './LocalUnit.test';
import recordingSessionStoreSpec from './RecordingSessionStore.test';

export default function testsuite() {
  localUnitTest();
  recordingSessionStoreSpec();
}
