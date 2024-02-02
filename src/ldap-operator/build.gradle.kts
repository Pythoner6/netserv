/*
 * This file was generated by the Gradle 'init' task.
 */

plugins {
    `java-library`
    `maven-publish`
    distribution
    id("io.quarkus")
    id("io.freefair.lombok")
}

repositories {
  mavenCentral {
    mavenContent {
      releasesOnly()
    }
  }
  mavenLocal {
    mavenContent {
      releasesOnly()
    }
  }
}

dependencies {
  implementation(enforcedPlatform("io.quarkus:quarkus-bom:3.6.4"))
  implementation("io.fabric8:generator-annotations:6.9.2")
  api("io.quarkiverse.operatorsdk:quarkus-operator-sdk:6.5.0")
  api("io.quarkiverse.operatorsdk:quarkus-operator-sdk-bundle-generator:6.5.0")
  api("io.quarkus:quarkus-micrometer-registry-prometheus:3.6.4")
  api("org.bouncycastle:bcprov-jdk18on:1.77")
  api("org.bouncycastle:bcpkix-jdk18on:1.77")
  api("com.unboundid:unboundid-ldapsdk:6.0.11")
}

group = "dev.pythoner6"
version = "0.0.1-SNAPSHOT"
description = "ldap-operator"
java.sourceCompatibility = JavaVersion.VERSION_11


tasks.withType<GenerateModuleMetadata> {
    // The value 'enforced-platform' is provided in the validation
    // error message you got
    suppressedValidationErrors.add("enforced-platform")
}

publishing {
  publications.create<MavenPublication>("maven") {
    from(components["java"])
  }
}

tasks.register("cacheToMavenLocal", Copy::class) {
  dependsOn("installDist")
  from(File(gradle.gradleUserHomeDir, "caches/modules-2/files-2.1"))
  into(repositories.mavenLocal().url)
  eachFile {
      val parts = path.split("/")
      path = listOf(parts[0].replace(".", "/"), parts[1], parts[2], parts[4]).joinToString("/")
  }
  includeEmptyDirs = false
}

tasks.withType<AbstractArchiveTask>().configureEach {
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
}

tasks.withType<JavaCompile>() {
  options.encoding = "UTF-8"
}

tasks.withType<Javadoc>() {
  options.encoding = "UTF-8"
}

dependencyLocking {
    lockAllConfigurations()
}

buildscript {
  dependencyLocking {
    lockAllConfigurations()
  }
}