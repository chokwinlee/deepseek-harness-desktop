plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.android.compose.screenshot")
}

val taggedReleaseVersion = providers.environmentVariable("DSH_RELEASE_VERSION").orNull
val releaseVersionName = taggedReleaseVersion ?: "0.1.0"

fun semverVersionCode(version: String): Int {
    val match = Regex("""^(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?$""")
        .matchEntire(version)
        ?: error(
            "DSH_RELEASE_VERSION must be major.minor.patch or " +
                "major.minor.patch-(alpha|beta|rc).number",
        )
    val major = match.groupValues[1].toIntOrNull()
        ?: error("DSH_RELEASE_VERSION major version is too large")
    val minor = match.groupValues[2].toIntOrNull()
        ?: error("DSH_RELEASE_VERSION minor version is too large")
    val patch = match.groupValues[3].toIntOrNull()
        ?: error("DSH_RELEASE_VERSION patch version is too large")
    require(major in 0..20 && minor in 0..99 && patch in 0..99) {
        "DSH_RELEASE_VERSION exceeds the Android versionCode allocation"
    }

    val prereleaseStage = match.groupValues[4]
    val prereleaseNumber = match.groupValues[5].takeIf(String::isNotEmpty)?.toIntOrNull()
    if (prereleaseStage.isNotEmpty()) {
        require(prereleaseNumber in 1..999) {
            "Android prerelease numbers must be between 1 and 999"
        }
    }
    val stageCode = when (prereleaseStage) {
        "alpha" -> 1_000 + prereleaseNumber!!
        "beta" -> 3_000 + prereleaseNumber!!
        "rc" -> 5_000 + prereleaseNumber!!
        "" -> 9_000
        else -> error("Unsupported Android prerelease stage: $prereleaseStage")
    }

    val code = major.toLong() * 100_000_000L +
        minor.toLong() * 1_000_000L +
        patch.toLong() * 10_000L +
        stageCode
    require(code in 1..2_100_000_000L) {
        "Android versionCode $code exceeds Google Play's supported range"
    }
    return code.toInt()
}

val releaseKeystorePath = providers.environmentVariable("ANDROID_KEYSTORE_PATH").orNull
val releaseKeystorePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("ANDROID_KEY_PASSWORD").orNull
val releaseSigningValues = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val releaseSigningFieldCount = releaseSigningValues.count { !it.isNullOrBlank() }
require(releaseSigningFieldCount == 0 || releaseSigningFieldCount == releaseSigningValues.size) {
    "Android release signing requires all four ANDROID_KEYSTORE_* / ANDROID_KEY_* variables"
}
val releaseSigningConfigured = releaseSigningFieldCount == releaseSigningValues.size

android {
    namespace = "com.chokwinlee.dshremote"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.chokwinlee.dshremote"
        minSdk = 26
        targetSdk = 37
        versionCode = taggedReleaseVersion?.let(::semverVersionCode) ?: 1
        versionName = releaseVersionName

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    experimentalProperties["android.experimental.enableScreenshotTest"] = true

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

}

tasks.register("verifyReleaseVersionCodeOrdering") {
    group = "verification"
    description = "Checks alpha, beta, rc, final, and next-patch Android versionCode ordering."
    doLast {
        val orderedVersions = listOf(
            "0.4.0-alpha.1",
            "0.4.0-alpha.999",
            "0.4.0-beta.1",
            "0.4.0-beta.999",
            "0.4.0-rc.1",
            "0.4.0-rc.999",
            "0.4.0",
            "0.4.1-alpha.1",
        )
        val versionCodes = orderedVersions.map(::semverVersionCode)
        check(versionCodes.zipWithNext().all { (before, after) -> before < after }) {
            "Android prerelease/final versionCodes are not strictly increasing: $versionCodes"
        }
        check(semverVersionCode("0.4.0-beta.1") == 4_003_001)
        check(semverVersionCode("0.4.0") == 4_009_000)
        check(semverVersionCode("20.99.99") <= 2_100_000_000)
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.08.00")
    val cameraXVersion = "1.6.1"

    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.19.0")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.navigation:navigation-compose:2.9.8")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:5.3.0")
    implementation("androidx.camera:camera-core:$cameraXVersion")
    implementation("androidx.camera:camera-camera2:$cameraXVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraXVersion")
    implementation("androidx.camera:camera-view:$cameraXVersion")
    implementation("androidx.exifinterface:exifinterface:1.4.2")
    implementation("com.google.mlkit:barcode-scanning:17.3.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    testImplementation("com.squareup.okhttp3:mockwebserver3:5.3.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    screenshotTestImplementation(platform("androidx.compose:compose-bom:2026.08.00"))
    screenshotTestImplementation("com.android.tools.screenshot:screenshot-validation-api:0.0.1-alpha15")
    screenshotTestImplementation("androidx.compose.ui:ui-tooling")
}
