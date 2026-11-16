plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val kioskAllowedManifestPermissions = setOf(
    "android.permission.INTERNET",
    "android.permission.CAMERA",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.BLUETOOTH",
    "android.permission.BLUETOOTH_ADMIN",
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.REQUEST_INSTALL_PACKAGES",
)

val kioskPermissionPolicyCheck by tasks.registering {
    group = "verification"
    description = "Fails the Android build if kiosk permissions escape the approved setup policy."
    doLast {
        val appRoot = rootProject.projectDir.parentFile
        val manifest = rootProject.file("app/src/main/AndroidManifest.xml").readText()
        val permissionTags = Regex("""<uses-permission(?:-sdk-23)?\b[\s\S]*?/>""")
            .findAll(manifest)
            .map { it.value }
            .toList()
        val declaredPermissions = permissionTags
            .filter { "tools:node=\"remove\"" !in it }
            .mapNotNull { Regex("""android:name="([^"]+)"""").find(it)?.groupValues?.get(1) }
            .toSet()
        check(declaredPermissions.all { it in kioskAllowedManifestPermissions }) {
            "Undeclared kiosk permission found: " +
                "${declaredPermissions - kioskAllowedManifestPermissions}"
        }
        val mergedPermissionRemovals = setOf(
            "android.permission.RECORD_AUDIO",
            "android.permission.READ_EXTERNAL_STORAGE",
        )
        check(
            mergedPermissionRemovals.all { permission ->
                permissionTags.any {
                    "android:name=\"$permission\"" in it &&
                        "tools:node=\"remove\"" in it
                }
            }
        ) {
            "The manifest must remove plugin-contributed microphone and broad storage permissions."
        }

        val dartFiles = appRoot.resolve("lib").walkTopDown()
            .filter { it.isFile && it.extension == "dart" }
            .filter { it.name != "kiosk_permissions.dart" }
        dartFiles.forEach { source ->
            val text = source.readText()
            check(".request(" !in text && "openAppSettings(" !in text) {
                "Permission or system-settings UI escaped the setup service: ${source.path}"
            }
        }
        val mainSource = appRoot.resolve("lib/main.dart").readText()
        check(
            Regex("""_showKioskSetup\(dialogContext\)""")
                .findAll(mainSource)
                .count() == 1
        ) {
            "The permission setup screen must only be opened from authenticated admin UI."
        }
    }
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(kioskPermissionPolicyCheck)
}

tasks.matching {
    it.name.startsWith("process") &&
        it.name.endsWith("Manifest") &&
        !it.name.endsWith("MainManifest")
}.configureEach {
    doLast {
        val mergedManifestRoot =
            layout.buildDirectory.dir("intermediates/merged_manifests").get().asFile
        val variantName = name.removePrefix("process").removeSuffix("Manifest")
            .replaceFirstChar { it.lowercase() }
        val mergedManifest = mergedManifestRoot
            .resolve("$variantName/$name/AndroidManifest.xml")
        val forbiddenMergedPermissions = listOf(
            "android.permission.RECORD_AUDIO",
            "android.permission.READ_EXTERNAL_STORAGE",
        )
        check(mergedManifest.isFile) {
            "Merged manifest was not generated for $name: ${mergedManifest.path}"
        }
        val mergedText = mergedManifest.readText()
        val mergedPermissions = Regex("""<uses-permission(?:-sdk-23)?\b[\s\S]*?/>""")
            .findAll(mergedText)
            .mapNotNull { Regex("""android:name="([^"]+)"""").find(it.value)?.groupValues?.get(1) }
            .toSet()
        val mergedAllowedPermissions = kioskAllowedManifestPermissions + setOf(
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.WAKE_LOCK",
            "com.photobooth.kiosk.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
        )
        check(mergedPermissions.all { it in mergedAllowedPermissions }) {
            "Undeclared plugin permission found in merged manifest: " +
                "${mergedPermissions - mergedAllowedPermissions} (${mergedManifest.path})"
        }
        check(forbiddenMergedPermissions.none { it in mergedText }) {
            "Forbidden plugin permission survived manifest merge: ${mergedManifest.path}"
        }
    }
}

android {
    namespace = "com.photobooth.kiosk"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.photobooth.kiosk"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    val media3Version = "1.8.0"
    implementation("androidx.media3:media3-common:$media3Version")
    implementation("androidx.media3:media3-effect:$media3Version")
    implementation("androidx.media3:media3-transformer:$media3Version")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
