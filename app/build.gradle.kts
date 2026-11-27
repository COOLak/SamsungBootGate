plugins {
    id("com.android.application")
}

android {
    namespace = "com.coolak.samsungbootgate"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.coolak.samsungbootgate"
        minSdk = 31
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        create("release") {
            val storePath = System.getenv("KEYSTORE_FILE").orEmpty()
            if (storePath.isNotEmpty()) {
                storeFile = rootProject.file(storePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
