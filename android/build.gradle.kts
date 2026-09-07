allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

fun java.io.File.volumeRoot(): String =
    toPath().toAbsolutePath().root?.toString().orEmpty()

fun java.io.File.isOnSameVolumeAs(other: java.io.File): Boolean =
    volumeRoot().equals(other.volumeRoot(), ignoreCase = true)

fun pubCacheRootFor(projectDirectory: java.io.File): java.io.File? {
    val configuredPubCache =
        System.getenv("PUB_CACHE")?.takeIf { it.isNotBlank() }?.let { java.io.File(it) }
    if (configuredPubCache != null && projectDirectory.isOnSameVolumeAs(configuredPubCache)) {
        return configuredPubCache
    }

    return generateSequence(projectDirectory.absoluteFile) { it.parentFile }
        .firstOrNull { it.name.equals("hosted", ignoreCase = true) || it.name.equals("git", ignoreCase = true) }
        ?.parentFile
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

val workspaceBuildKey =
    Integer.toUnsignedString(rootProject.rootDir.absolutePath.lowercase().hashCode(), 16)
val workspaceDirectory = rootProject.rootDir.parentFile.toPath().toAbsolutePath().normalize()
val crossVolumeBuildDirectories = mutableListOf<java.io.File>()

subprojects {
    val sharedSubprojectBuildDir = newBuildDir.dir(project.name)
    val projectDirectory = project.layout.projectDirectory.asFile
    val isExternalSubproject =
        !projectDirectory.toPath().toAbsolutePath().normalize().startsWith(
            workspaceDirectory,
        )
    val selectedBuildDir =
        if (projectDirectory.isOnSameVolumeAs(sharedSubprojectBuildDir.asFile)) {
            sharedSubprojectBuildDir
        } else {
            // Gradle/AGP relativizes unit-test paths. On Windows that fails when
            // the Flutter project and a plugin in Pub Cache use different drives.
            // Keep external plugin outputs in a workspace-scoped cache directory
            // on the plugin's own volume, but outside the immutable package folder.
            val pubCacheRoot =
                requireNotNull(pubCacheRootFor(projectDirectory)) {
                    "Cannot choose a same-volume build directory for ${project.path}. " +
                        "Set PUB_CACHE to a writable directory on ${projectDirectory.volumeRoot()}."
                }
            val externalBuildDir =
                pubCacheRoot.resolve(".gradle-builds/cqut/$workspaceBuildKey/${project.name}")
            crossVolumeBuildDirectories += externalBuildDir
            project.layout.dir(project.providers.provider { externalBuildDir }).get()
        }
    project.layout.buildDirectory.value(selectedBuildDir)

    if (isExternalSubproject) {
        // Pub packages do not consistently ship the fixtures required by their
        // own unit tests. The app test task should validate workspace code, not
        // rerun dependency-maintainer test suites from the global package cache.
        project.tasks.withType<org.gradle.api.tasks.testing.Test>().configureEach {
            enabled = false
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
    delete(crossVolumeBuildDirectories)
}
