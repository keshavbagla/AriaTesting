package com.aria.framework.contracts;

import au.com.dius.pact.consumer.MockServer;
import au.com.dius.pact.consumer.dsl.PactBuilder;
import au.com.dius.pact.consumer.junit5.PactConsumerTestExt;
import au.com.dius.pact.consumer.junit5.PactTestFor;
import au.com.dius.pact.core.model.V4Pact;
import au.com.dius.pact.core.model.annotations.Pact;
import io.restassured.RestAssured;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.parallel.Execution;
import org.junit.jupiter.api.parallel.ExecutionMode;

import static org.assertj.core.api.Assertions.assertThat;

/** Consumer-owned contract for the shared reference application's unauthenticated boundary. */
@ExtendWith(PactConsumerTestExt.class)
@Execution(ExecutionMode.SAME_THREAD)
class ReferenceApplicationConsumerPactTest {

    @Pact(consumer = "aria-api-framework", provider = "quality-reference-application")
    V4Pact unauthenticatedPolicyListPact(PactBuilder builder) {
        return builder
            .expectsToReceiveHttpInteraction("an unauthenticated policy list request", interaction -> interaction
                .withRequest(request -> request
                    .method("GET")
                    .path("/api/v1/policies"))
                .willRespondWith(response -> response
                    .status(401)
                    .header("Content-Type", "application/json; charset=utf-8")
                    .body("""
                        {"error":{"code":"AUTHENTICATION_REQUIRED"}}
                        """, "application/json; charset=utf-8")))
            .toPact();
    }

    @Test
    @Tag("contract")
    @DisplayName("Unauthenticated policy access satisfies the shared APP consumer contract")
    @PactTestFor(pactMethod = "unauthenticatedPolicyListPact")
    void unauthenticatedPolicyListMatchesContract(MockServer mockServer) {
        var response = RestAssured.given()
            .baseUri(mockServer.getUrl())
            .accept("application/json")
            .get("/api/v1/policies");

        assertThat(response.statusCode()).isEqualTo(401);
        assertThat(response.jsonPath().getString("error.code")).isEqualTo("AUTHENTICATION_REQUIRED");
    }
}
