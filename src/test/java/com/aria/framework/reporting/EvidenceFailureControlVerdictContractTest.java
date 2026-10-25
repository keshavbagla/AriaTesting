package com.aria.framework.reporting;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

class EvidenceFailureControlVerdictContractTest {

    // Synthetic unit fixture; this is not a retained execution record.
    private ObjectNode fixture() throws Exception {
        return (ObjectNode) new ObjectMapper().readTree("""
            {"sourceSha":"synthetic-source","workflow":{"runId":"synthetic-run","attempt":1},
             "scope":{"id":"aria.evidence-failure-control","required":false},
             "execution":{"disposition":"failed","integrity":"complete",
               "counts":{"selected":1,"executed":1,"passed":0,"failed":1,"skipped":0,"retried":0}}}
            """);
    }

    @Test
    void acceptsOnlyTheCompleteExpectedFailure() throws Exception {
        assertDoesNotThrow(() -> EvidenceFailureControlVerdictTest.verify(
            fixture(), "synthetic-source", "synthetic-run", "1"));
        for (String field : new String[] {"selected", "executed", "passed", "failed", "skipped", "retried"}) {
            ObjectNode record = fixture();
            ((ObjectNode) record.path("execution").path("counts")).remove(field);
            assertThrows(AssertionError.class, () -> EvidenceFailureControlVerdictTest.verify(
                record, "synthetic-source", "synthetic-run", "1"), field);
        }
    }

    @Test
    void rejectsWrongDispositionIntegrityScopeAndIdentity() throws Exception {
        ObjectNode record = fixture();
        ((ObjectNode) record.path("execution")).put("disposition", "passed");
        assertRejected(record);
        record = fixture();
        ((ObjectNode) record.path("execution")).put("integrity", "unavailable");
        assertRejected(record);
        record = fixture();
        ((ObjectNode) record.path("scope")).put("required", true);
        assertRejected(record);
        for (String field : new String[] {"source", "run", "attempt"}) {
            String source = field.equals("source") ? "different" : "synthetic-source";
            String run = field.equals("run") ? "different" : "synthetic-run";
            String attempt = field.equals("attempt") ? "2" : "1";
            assertThrows(AssertionError.class, () -> EvidenceFailureControlVerdictTest.verify(
                fixture(), source, run, attempt));
        }
    }

    @Test
    void missingInputFailsInsteadOfSkipping(@TempDir Path directory) {
        assertThrows(java.io.IOException.class,
            () -> EvidenceFailureControlVerdictTest.read(directory.resolve("absent.json")));
    }

    private void assertRejected(ObjectNode record) {
        assertThrows(AssertionError.class, () -> EvidenceFailureControlVerdictTest.verify(
            record, "synthetic-source", "synthetic-run", "1"));
    }
}
