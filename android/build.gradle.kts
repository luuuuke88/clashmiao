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

// Gradle 9 起，模块里有测试源码却一个测试都没发现时，test 任务直接失败
// （failOnNoDiscoveredTests 默认 true）。第三方插件模块（如 in_app_review）自带
// 一个发现不到测试的测试目录，不归我们管，只对插件子项目关掉；:app 仍保持严格，
// 我们自己的测试要是一个都没跑起来照样会失败。
subprojects {
    if (name != "app") {
        tasks.withType<Test>().configureEach {
            failOnNoDiscoveredTests = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
