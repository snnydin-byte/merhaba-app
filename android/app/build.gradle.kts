import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play Store için gerçek (release) imzalama - şifreler/keystore yolu git'e
// asla eklenmeyen android/key.properties dosyasından okunuyor (bkz.
// KURULUM.md "Play Store Yayın Hazırlığı" bölümü). Bu dosya yoksa (ör.
// henüz keystore oluşturulmadıysa) release build debug anahtarına geri
// düşer - böylece `flutter run --release` yine de çalışmaya devam eder,
// ama gerçek yayın için MUTLAKA key.properties oluşturulmuş olmalı.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.merhaba"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications v21+ bunu şart koşuyor (bkz.
        // "requires core library desugaring to be enabled" hatası) -
        // Java 8+ API'lerinin eski Android sürümlerinde de çalışmasını
        // sağlıyor, aşağıdaki coreLibraryDesugaring bağımlılığıyla birlikte.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Play Console'a KALICI olarak bağlı benzersiz kimlik - yayınlandıktan
        // sonra bir daha ASLA değiştirilemez (bkz. KURULUM.md).
        applicationId = "com.merhaba.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // flutter_local_notifications'ın resmi kurulum notlarında öneriliyor -
        // Firebase + WebRTC + socket.io birlikte 64K metod sınırını
        // aşabileceği için güvenlik payı olarak ekliyoruz.
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                // rootProject.file(...) kullanıyoruz (düz file(...) değil) -
                // bu, yolu android/app/ değil android/ klasörüne göre
                // çözer; keystore dosyası ve key.properties ikisi de
                // android/ kökünde duruyor (bkz. KURULUM.md).
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Gerçek yayın anahtarı (key.properties) mevcutsa onunla imzala;
            // yoksa (henüz oluşturulmadıysa) debug anahtarına geri düş - bkz.
            // yukarıdaki hasReleaseKeystore notu. Play Store'a yüklemeden önce
            // key.properties MUTLAKA oluşturulmuş olmalı, aksi halde bu debug
            // imzasıyla derlenmiş bir .aab Play Console'da kabul edilmez.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // flutter_local_notifications v21+ için core library desugaring desteği.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
