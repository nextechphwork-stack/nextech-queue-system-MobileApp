const { onValueUpdated } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Fires whenever a ticket's node under /queue/{pushId} changes.
 * Sends a real phone push on the two moments that matter most:
 *   - status becomes "serving"  -> "It's your turn"
 *   - status becomes "done"     -> "You've been served"
 *
 * Token lookup matches your app: queue_tokens/{ticketId} = { token, ... }
 */
exports.sendTicketStatusPush = onValueUpdated("/queue/{pushId}", async (event) => {
  const before = event.data.before.val();
  const after = event.data.after.val();

  if (!after || !before) return;
  if (before.status === after.status) return; // no real change

  const ticketId = after.ticketId;
  if (!ticketId) return;

  let title, body;
  if (after.status === "serving") {
    title = "It's your turn!";
    body = `Please proceed to the ${after.deptLabel || after.department} counter now.`;
  } else if (after.status === "done") {
    title = "You've been served";
    body = `Thank you for visiting ${after.deptLabel || after.department}.`;
  } else {
    return; // only push for these two transitions
  }

  const tokenSnap = await admin.database().ref(`queue_tokens/${ticketId}`).get();
  const token = tokenSnap.val()?.token;
  if (!token) return; // no device registered for this ticket

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: { ticketId, status: after.status },
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    });
  } catch (err) {
    console.error("Push send failed for", ticketId, err);
    // Common cause: token is stale (app uninstalled, etc). You could
    // delete queue_tokens/{ticketId} here if the error code indicates
    // an unregistered token, so it isn't retried forever.
  }
});