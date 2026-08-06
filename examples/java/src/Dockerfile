# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app

# Resolve dependencies against the pom alone so edits to src/ reuse the cached layer.
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q package -DskipTests

FROM eclipse-temurin:21-jre AS runtime
WORKDIR /app

COPY --from=build /app/target/app.jar ./app.jar

ENV PORT=8080
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]

# SSI on: stop here; the module sets JAVA_TOOL_OPTIONS to the agent it stages in
# /datadog-lib (do not ship an agent here -- two -javaagent copies conflict).
FROM runtime AS ssi

# SSI off (default): ship the agent in the image and load it manually.
FROM runtime AS manual
ARG DD_JAVA_AGENT_VERSION=1.50.0
RUN curl -fsSL -o /app/dd-java-agent.jar \
    "https://repo1.maven.org/maven2/com/datadoghq/dd-java-agent/${DD_JAVA_AGENT_VERSION}/dd-java-agent-${DD_JAVA_AGENT_VERSION}.jar"
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/dd-java-agent.jar"

FROM manual
