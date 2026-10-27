allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// The Razorpay SDK resolves through floating versions: razorpay_flutter's own
// build.gradle asks for checkout `1.6.+`, and checkout's POM asks for
// standard-core `LATEST`. Each forces a fetch of the version listing
// (maven-metadata.xml) on every build. When that listing comes back empty, the
// build fails (main CI 2026-10-21), and when Razorpay publishes, the next build
// silently ships the new SDK. Pin both to the versions every built AAB
// (+46..+48) used. Bump deliberately, with a device payment test, and update
// test/contracts/android_dynamic_dependency_pin_test.dart. Diagnose doc a6c3e9.
val pinnedAndroidDependencies = mapOf(
    "com.razorpay:checkout" to "1.6.41",
    "com.razorpay:standard-core" to "1.7.19",
)

subprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            pinnedAndroidDependencies["${requested.group}:${requested.name}"]?.let {
                useVersion(it)
                because("pinned: the SDK's own selector is a floating version")
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
