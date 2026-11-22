// Upstream CEF and ApplicationTest fixtures share incompatible global Koin state.
allprojects {
    tasks.withType<org.gradle.api.tasks.testing.Test>().configureEach {
        forkEvery = 1
    }
}
