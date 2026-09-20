package dev.langchain4j.quarkus.workshop;

import dev.langchain4j.guardrail.InputGuardrailException;
import dev.langchain4j.service.guardrail.InputGuardrails;
import io.quarkiverse.langchain4j.mcp.runtime.McpToolBox;
import jakarta.enterprise.context.SessionScoped;

import org.eclipse.microprofile.faulttolerance.ExecutionContext;
import org.eclipse.microprofile.faulttolerance.Fallback;
import org.eclipse.microprofile.faulttolerance.FallbackHandler;
import org.eclipse.microprofile.faulttolerance.Retry;
import org.eclipse.microprofile.faulttolerance.Timeout;

import dev.langchain4j.service.SystemMessage;
import io.quarkiverse.langchain4j.RegisterAiService;
import io.quarkiverse.langchain4j.ToolBox;

@SessionScoped
@RegisterAiService
public interface CustomerSupportAgent {

    @SystemMessage("""
            You are a customer support agent of a car rental company 'Miles of Smiles'.
            You are friendly, polite and concise.
            If the question is unrelated to car rental, you should politely redirect the customer to the right department.

            When calling tools or functions, strictly use JSON objects,
            do not wrap in quotes or use plain strings.

            When asked to provide details about a reservation,
            provide weather details and gently try to upsell the customer based on this info.

            Today is {current_date}.
            """)
    @InputGuardrails(PromptInjectionGuard.class)
    @ToolBox(BookingRepository.class)
    @McpToolBox("weather")
    // 60s, not 5s. A single warm call to the model takes about 1s, so the budget
    // is not about raw provider latency: this method is a guardrail LLM round
    // trip, then a vector search, then the main call generating a long answer,
    // and measured end to end it lands around 34s. At 5s the fallback is the only
    // thing this step would ever demonstrate.
    //
    // On a faster paid endpoint you would tune this down. MicroProfile lets you do
    // that without touching the code:
    //   dev.langchain4j.quarkus.workshop.CustomerSupportAgent/chat/Timeout/value=10000
    @Timeout(60000)
    // One retry, not three. Retrying a slow call multiplies load on an API with a
    // per-minute limit, which is how a timeout turns into a 429.
    @Retry(maxRetries = 1, delay = 2000, abortOn = InputGuardrailException.class)
    @Fallback(value = CustomerSupportAgentFallback.class, skipOn = InputGuardrailException.class)
    String chat(String userMessage);

    public static class CustomerSupportAgentFallback implements FallbackHandler<String> {

        private static final String EMPTY_RESPONSE = "Failed to get a response from the AI Model. Are you sure it's up and running, and configured correctly?";
        @Override
        public String handle(ExecutionContext context) {
            return EMPTY_RESPONSE;
        }

    }
}
