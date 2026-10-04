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
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_pcm_sound 3.3.3 hardcodes compileSdk 33. Its AndroidX deps
// require 34+, and the release AAR metadata check fails otherwise.
// AGP 9 rejects a compileSdk write after evaluation, so this uses finalizeDsl.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension>(
            "androidComponents",
        ) {
            finalizeDsl { ext ->
                if ((ext.compileSdk ?: 0) < 36) {
                    ext.compileSdk = 36
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
