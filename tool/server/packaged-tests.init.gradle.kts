// Use with -Dtsumiru.server.jar=/absolute/path/to/candidate.jar.
val candidate = File(requireNotNull(System.getProperty("tsumiru.server.jar"))).canonicalFile
require(candidate.isFile)

gradle.projectsEvaluated {
    val server = rootProject.findProject(":server") ?: return@projectsEvaluated
    server.tasks.named<org.gradle.api.tasks.testing.Test>("test") {
        classpath = server.files(candidate, classpath)
        doFirst {
            require(classpath.files.first().canonicalFile == candidate)
            java.net.URLClassLoader(arrayOf(candidate.toURI().toURL()), ClassLoader.getPlatformClassLoader()).use { loader ->
                for (name in listOf(
                    "suwayomi.tachidesk.manga.impl.Manga",
                    "suwayomi.tachidesk.manga.impl.update.Updater",
                    "suwayomi.tachidesk.manga.impl.update.LibraryUpdateRetries",
                    "suwayomi.tachidesk.manga.impl.update.ExtensionUpdateSchedule",
                    "suwayomi.tachidesk.manga.impl.update.RecoveryRetrySchedule",
                    "suwayomi.tachidesk.manga.impl.update.ServerRecoveryManager",
                )) {
                    val type = loader.loadClass(name)
                    require(File(type.protectionDomain.codeSource.location.toURI()).canonicalFile == candidate)
                    type.declaredMethods // Link method signatures against the packaged dependencies.
                }
            }
        }
    }
}
