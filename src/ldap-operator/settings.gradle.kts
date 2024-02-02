pluginManagement {
    repositories {
      mavenCentral()
      gradlePluginPortal()
      mavenLocal()
    }
    plugins {
      id("io.quarkus") version "3.6.4"
      id("io.freefair.lombok") version "8.4"
    }
}

rootProject.name = "ldap-operator"
