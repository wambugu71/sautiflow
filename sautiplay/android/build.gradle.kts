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
    if (name == "file_picker") {
        pluginManager.withPlugin("com.android.library") {
            val builtInKotlin = findProperty("android.builtInKotlin")?.toString()?.toBooleanStrictOrNull() ?: true
            if (!builtInKotlin && !pluginManager.hasPlugin("org.jetbrains.kotlin.android")) {
                pluginManager.apply("org.jetbrains.kotlin.android")
            }
        }
        pluginManager.withPlugin("org.jetbrains.kotlin.android") {
            tasks.matching { it.name.contains("Kotlin", ignoreCase = true) }.configureEach {
                try {
                    val compilerOptions = javaClass.getMethod("getCompilerOptions").invoke(this)
                    val jvmTargetProp = compilerOptions.javaClass.getMethod("getJvmTarget").invoke(compilerOptions)
                    val jvmTargetClass = compilerOptions.javaClass.classLoader.loadClass("org.jetbrains.kotlin.gradle.dsl.JvmTarget")
                    val jvm17 = jvmTargetClass.getField("JVM_17").get(null)
                    jvmTargetProp.javaClass.getMethod("set", Any::class.java).invoke(jvmTargetProp, jvm17)
                } catch (_: Throwable) {
                    try {
                        val kotlinOptions = javaClass.getMethod("getKotlinOptions").invoke(this)
                        kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java).invoke(kotlinOptions, "17")
                    } catch (_: Throwable) {
                    }
                }
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
