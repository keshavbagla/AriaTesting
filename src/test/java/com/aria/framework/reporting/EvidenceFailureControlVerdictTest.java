package com.aria.framework.reporting;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

@Tag("evidence-verification")
class EvidenceFailureControlVerdictTest {

    @Test
    void verifiesTheNativeFailureAndCurrentRunIdentity() throws IOException {
        String file = System.getProperty("failureControlEvidence");
        assertTrue(file != null && !file.isBlank(), "failureControlEvidence is required");
        verify(read(Path.of(file)), requiredEnvironment("GITHUB_SHA"),
            requiredEnvironment("GITHUB_RUN_ID"), requiredEnvironment("GITHUB_RUN_ATTEMPT"));
    }

    static JsonNode read(Path file) throws IOException {
        return new ObjectMapper().readTree(file.toFile());
    }

    static void verify(JsonNode record, String source, String runId, String attempt) {
        assertEquals("failed", record.path("execution").path("disposition").asText());
        assertEquals("complete", record.path("execution").path("integrity").asText());
        JsonNode counts = record.path("execution").path("counts");
        for (String field : new String[] {"selected", "executed", "passed", "failed", "skipped", "retried"}) {
            assertTrue(counts.path(field).isIntegralNumber(), field + " must be an integer");
        }
        assertEquals(1, counts.path("selected").asInt(-1));
        assertEquals(1, counts.path("executed").asInt(-1));
        assertEquals(0, counts.path("passed").asInt(-1));
        assertEquals(1, counts.path("failed").asInt(-1));
        assertEquals(0, counts.path("skipped").asInt(-1));
        assertEquals(0, counts.path("retried").asInt(-1));
        assertEquals("aria.evidence-failure-control", record.path("scope").path("id").asText());
        assertTrue(record.path("scope").path("required").isBoolean());
        assertFalse(record.path("scope").path("required").asBoolean(true));
        assertEquals(source, record.path("sourceSha").asText());
        assertEquals(runId, record.path("workflow").path("runId").asText());
        assertEquals(attempt, record.path("workflow").path("attempt").asText());
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        assertTrue(value != null && !value.isBlank(), name + " is required");
        return value;
    }
}
