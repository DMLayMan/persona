// "Live link" (#7497): its own module so a card can offer it without loading the Agents list's menu actions (the
// outbox among them).
import { t } from "../i18n";
import { toast } from "../ui/atoms";
import { attachSession, errorText } from "./api";
import { sessionCan } from "./format";
import { getSession, refresh } from "./store";
import type { Session } from "./types";
import { heldChild } from "./use-child-sessions";

/** "Live link": link a session from another source (a Codex app-server thread…) live. The chat's ⋯, the row menu and a
 *  card the page can't answer call this; it reads the session again first, since the menu may have opened on an older
 *  copy, and a child's card on its parent's page reads the parent's held row (#5120). */
export async function attachLive(s: Pick<Session, "machine_id" | "session_id">) {
  if (!sessionCan(getSession(s.machine_id, s.session_id) ?? heldChild(s.machine_id, s.session_id), "attach")) return;
  try {
    await attachSession(s.machine_id, s.session_id);
    await refresh();
    toast(t("chat-chatview.attached"), "ok");
  } catch (e) {
    toast(t("chat-chatview.attach_failed", { error: errorText(e) }), "error");
  }
}
