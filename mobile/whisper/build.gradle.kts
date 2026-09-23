plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "ai.najwa.whisper"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        minSdk = 31
        ndk { abiFilters += listOf("arm64-v8a") } // Pura 70 Ultra; keeps the APK small
        externalNativeBuild {
            cmake {
                val dir = rootProject.file(project.property("whisperCppDir") as String).canonicalPath
                arguments += listOf("-DWHISPER_CPP_DIR=$dir", "-DANDROID_STL=c++_shared")
                cppFlags += "-std=c++17"
            }
        }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
