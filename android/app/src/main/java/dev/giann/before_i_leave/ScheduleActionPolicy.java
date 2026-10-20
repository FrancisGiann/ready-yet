package dev.giann.before_i_leave;

/** Rejects replayed notification actions, including actions from prior resets. */
public final class ScheduleActionPolicy {
    private ScheduleActionPolicy() {}
    public static boolean mayHandle(String renderEpoch, String currentEpoch,
            String token, String currentToken, String actedToken, boolean incomplete) {
        return incomplete && renderEpoch != null && !renderEpoch.isEmpty()
            && renderEpoch.equals(currentEpoch) && token != null && !token.isEmpty()
            && token.equals(currentToken) && !token.equals(actedToken);
    }
}
