val isGitHubActions = System.getenv("GITHUB_ACTIONS") == "true"

allprojects {
    repositories {
        google()
        mavenCentral()
        if (!isGitHubActions) {
            // Mainland fallback mirrors. CI stays on official repositories so
            // transient mirror 5xx responses cannot break release builds.
            maven("https://maven.aliyun.com/repository/google")
            maven("https://maven.aliyun.com/repository/public")
            maven("https://maven.aliyun.com/repository/central")
        }
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
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.test" && requested.version?.endsWith("+") == true) {
                when (requested.name) {
                    "runner" -> useVersion("1.6.2")
                    "rules" -> useVersion("1.6.1")
                }
            }
            if (requested.group == "androidx.test.espresso" &&
                requested.name == "espresso-core" &&
                requested.version?.endsWith("+") == true
            ) {
                useVersion("3.6.1")
            }
        }
    }
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
