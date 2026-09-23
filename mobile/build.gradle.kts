// Versions match what the Flutter projects on this machine already cache
// (AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14) so a build works on a flaky link.
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("com.android.library") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false
}
