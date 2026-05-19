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
// Use gradle.projectsEvaluated{} so we run after every subproject is evaluated
// (afterEvaluate inside subprojects{} throws in Gradle 8.8+ for already-evaluated projects).
gradle.projectsEvaluated {
    rootProject.subprojects.forEach { p ->
        p.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                val floor = org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9
                val cur = languageVersion.orNull
                if (cur != null && cur < floor) languageVersion.set(floor)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
