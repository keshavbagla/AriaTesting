package com.aria.framework.contracts;

import io.restassured.RestAssured;
import io.restassured.response.Response;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.parallel.Execution;
import org.junit.jupiter.api.parallel.ExecutionMode;

import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/** Small, independently asserted security and lifecycle surface for the shared APP target. */
@Tag("shared-app")
@Execution(ExecutionMode.SAME_THREAD)
class ReferenceApplicationApiTest {

    private static final String POLICY_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    private static String baseUrl;

    @BeforeAll
    static void requirePinnedTarget() {
        baseUrl = System.getenv("APP_BASE_URL");
        assertThat(baseUrl).as("APP_BASE_URL must point at the isolated pinned APP instance")
            .isNotBlank();
        assertThat(System.getenv("APP_SOURCE_REVISION"))
            .as("the app source revision must be explicit")
            .isEqualTo("e9f438e06a2b092dccfc6e9ab1820ff2562ddad7");
        assertThat(System.getenv("APP_FIXTURE_VERSION")).isEqualTo("v0.1.0");
    }

    @Test
    @DisplayName("Member can submit a claim and reviewer can advance its audited lifecycle")
    void allowedClaimLifecycle() {
        String member = session("member-a");
        String reviewer = session("reviewer");
        String claimId = submitClaim(member);

        Response underReview = request(reviewer)
            .body(Map.of("status", "under_review", "expectedVersion", 1))
            .patch("/api/v1/claims/" + claimId);
        assertThat(underReview.statusCode()).isEqualTo(200);
        assertThat(underReview.jsonPath().getString("claim.status")).isEqualTo("under_review");
        assertThat(underReview.jsonPath().getInt("claim.version")).isEqualTo(2);

        Response approved = request(reviewer)
            .body(Map.of("status", "approved", "expectedVersion", 2))
            .patch("/api/v1/claims/" + claimId);
        assertThat(approved.statusCode()).isEqualTo(200);
        assertThat(approved.jsonPath().getString("claim.status")).isEqualTo("approved");
        assertThat(approved.jsonPath().getInt("claim.version")).isEqualTo(3);
        assertThat(request(reviewer).get("/api/v1/claims/" + claimId + "/events")
            .jsonPath().getList("items")).hasSize(2);
    }

    @Test
    @DisplayName("Invalid claim payload returns the stable validation code")
    void invalidPayloadIsRejected() {
        Response response = request(session("member-a"))
            .body(Map.of("policyId", POLICY_A, "amountMinor", 0, "currency", "USD", "category", "auto"))
            .post("/api/v1/claims");

        assertThat(response.statusCode()).isEqualTo(422);
        assertThat(response.jsonPath().getString("error.code")).isEqualTo("VALIDATION_ERROR");
    }

    @Test
    @DisplayName("Missing identity cannot list policies")
    void missingIdentityIsUnauthorized() {
        Response response = RestAssured.given()
            .baseUri(baseUrl)
            .accept("application/json")
            .get("/api/v1/policies");

        assertThat(response.statusCode()).isEqualTo(401);
        assertThat(response.jsonPath().getString("error.code")).isEqualTo("AUTHENTICATION_REQUIRED");
    }

    @Test
    @DisplayName("Member role cannot transition a claim")
    void memberCannotReviewClaim() {
        String member = session("member-a");
        String claimId = submitClaim(member);

        Response response = request(member)
            .body(Map.of("status", "under_review", "expectedVersion", 1))
            .patch("/api/v1/claims/" + claimId);

        assertThat(response.statusCode()).isEqualTo(403);
        assertThat(response.jsonPath().getString("error.code")).isEqualTo("ROLE_FORBIDDEN");
    }

    @Test
    @DisplayName("Another member cannot read or list the claim")
    void crossMemberClaimAccessIsNonDisclosing() {
        String memberA = session("member-a");
        String memberB = session("member-b");
        String claimId = submitClaim(memberA);

        Response directRead = request(memberB).get("/api/v1/claims/" + claimId);
        assertThat(directRead.statusCode()).isEqualTo(404);
        assertThat(directRead.jsonPath().getString("error.code")).isEqualTo("RESOURCE_NOT_FOUND");

        Response list = request(memberB).get("/api/v1/claims");
        assertThat(list.statusCode()).isEqualTo(200);
        assertThat(list.jsonPath().getList("items.id", String.class)).doesNotContain(claimId);
    }

    private static String session(String identity) {
        Response response = RestAssured.given()
            .baseUri(baseUrl)
            .contentType("application/json")
            .body(Map.of("identityKey", identity))
            .post("/api/v1/sessions");
        assertThat(response.statusCode()).isEqualTo(201);
        return response.jsonPath().getString("token");
    }

    private static String submitClaim(String token) {
        Response response = request(token)
            .body(Map.of("policyId", POLICY_A, "amountMinor", 2450, "currency", "USD", "category", "auto"))
            .post("/api/v1/claims");
        assertThat(response.statusCode()).isEqualTo(201);
        return response.jsonPath().getString("claim.id");
    }

    private static io.restassured.specification.RequestSpecification request(String token) {
        return RestAssured.given()
            .baseUri(baseUrl)
            .contentType("application/json")
            .accept("application/json")
            .auth().oauth2(token);
    }
}
