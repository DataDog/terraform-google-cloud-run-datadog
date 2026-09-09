# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app

# Resolve dependencies against the pom alone so edits to src/ reuse the cached layer.
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app

COPY --from=build /app/target/app.jar ./app.jar

ENV PORT=8080
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
