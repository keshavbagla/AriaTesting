package com.aria.framework.contracts;

import au.com.dius.pact.provider.junit5.HttpTestTarget;
import au.com.dius.pact.provider.junit5.PactVerificationContext;
import au.com.dius.pact.provider.junit5.PactVerificationInvocationContextProvider;
import au.com.dius.pact.provider.junitsupport.Provider;
import au.com.dius.pact.provider.junitsupport.loader.PactFolder;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.TestTemplate;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.parallel.Execution;
import org.junit.jupiter.api.parallel.ExecutionMode;

import java.net.URI;

/** Verifies ARIA's generated consumer contract against the running pinned APP image. */
@Provider("quality-reference-application")
@PactFolder("build/pacts")
@Tag("shared-app-pact-provider")
@Execution(ExecutionMode.SAME_THREAD)
class ReferenceApplicationPactVerificationTest {

    @BeforeEach
    void targetRunningApplication(PactVerificationContext context) {
        String baseUrl = System.getenv("APP_BASE_URL");
        if (baseUrl == null || baseUrl.isBlank()) {
            throw new IllegalStateException("APP_BASE_URL must point to the pinned reference application.");
        }
        URI uri = URI.create(baseUrl);
        String basePath = uri.getPath().isBlank() ? "/" : uri.getPath();
        context.setTarget(new HttpTestTarget(uri.getHost(), uri.getPort(), basePath));
    }

    @TestTemplate
    @ExtendWith(PactVerificationInvocationContextProvider.class)
    void verifiesAriaConsumerPactAgainstReferenceApplication(PactVerificationContext context) {
        context.verifyInteraction();
    }
}
