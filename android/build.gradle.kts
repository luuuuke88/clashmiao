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

// sentry_flutter sets languageVersion="1.6" which Kotlin 2.2+ rejects (min is 1.7).
// Override it for every subproject after their build scripts are evaluated.
// Note: kotlinOptions{} is an error in Kotlin 2.2 .kts files; use compilerOptions{} DSL.
subprojects {
    afterEvaluate {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                val floor = org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9
                if (languageVersion.orNull?.let { it < floor } == true) {
                    languageVersion.set(floor)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
