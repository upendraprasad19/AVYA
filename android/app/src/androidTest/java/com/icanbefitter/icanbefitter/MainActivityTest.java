// Tech-debt audit 2026-05-20 / T1: Patrol native test runner entry-point.
//
// Patrol 3.x requires a JUnit test class in the androidTest source set
// that delegates to the PatrolJUnitRunner. The `@RunWith` annotation +
// `PatrolTestRule` wiring is the standard scaffold per
// https://patrol.leancode.co/getting-started.
//
// This file is wired by AndroidManifest's testInstrumentationRunner
// (set in android/app/build.gradle.kts).
//
// Founder runs the suite via scripts/run-device-tests.sh; the runner
// then drives `flutter test integration_test/device/` against the
// Pixel over USB.
package com.icanbefitter.icanbefitter;

import androidx.test.platform.app.InstrumentationRegistry;
import pl.leancode.patrol.PatrolJUnitRunner;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.JUnit4;

@RunWith(JUnit4.class)
public class MainActivityTest {
    @Test
    public void runAllTests() {
        PatrolJUnitRunner instrumentation =
                (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.setUp(MainActivity.class);
        instrumentation.waitForPatrolAppService();
        // Bundle is set by the patrol CLI at run time.
    }
}
