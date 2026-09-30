import com.android.build.gradle.BaseExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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

// Some older plugins (e.g. another_telephony) don't declare a Kotlin/Java
// compile target matching this project's (17), which fails the build with
// "Inconsistent JVM-target compatibility". Force plugin subprojects only
// (never ":app", which already sets its own consistent Java/Kotlin 17
// config and must not be touched here) to compile against 17 as well.
//
// This has to override the Android Gradle Plugin's own `compileOptions`
// extension (inside afterEvaluate, once the plugin's own build script has
// already run) rather than just the JavaCompile task property directly —
// AGP re-derives the task's source/target compatibility from that
// extension, so setting only the task property gets silently overwritten.
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(BaseExtension::class.java)?.let { androidExt ->
                androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
