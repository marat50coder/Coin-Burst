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

    // ─────────────────────────────────────────────────────────────────
    // gray_part_pitfalls.md §2 — force every Android library plugin to
    // compile against the same compileSdk the app uses (36+). Some
    // plugins still ship with compileSdk=34 but their transitive deps
    // require 36, so CheckAarMetadata aborts without this override.
    //
    // §7 — must be registered BEFORE evaluationDependsOn(":app") in a
    // DIFFERENT subprojects block, otherwise Gradle rejects the
    // afterEvaluate callback as "project already evaluated".
    // ─────────────────────────────────────────────────────────────────
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
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
