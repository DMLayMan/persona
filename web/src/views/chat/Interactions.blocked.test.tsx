// @vitest-environment jsdom
// A card this page can't answer says why (#7497), as iOS (#6868) and Android do: a Codex thread Persona hasn't joined
// offers Live link, which makes the card answerable; any other session says to answer on the computer. An answerable
// card has no line.
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
vi.hoisted(() => {
  window.matchMedia ??= ((query: string) => ({ matches: false, media: query, onchange: null, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {}, dispatchEvent: () => false })) as typeof window.matchMedia;
});
const attached = vi.hoisted(() => [] as string[]);
vi.mock("../../lib/api", async (original) => ({
  ...await original<typeof import("../../lib/api")>(),
  attachSession: vi.fn(async (mid: string, sid: string) => { attached.push(`${mid}/${sid}`); }),
}));
vi.mock("../../lib/store", async (original) => {
  const real = await original<typeof import("../../lib/store")>();
  // the hub's new row after the node joined the thread: it can approve now
  return { ...real, refresh: vi.fn(async () => { real.upsertSession({ ...real.getSession("m", "s")!, capabilities: { read: true, send: true, approve: true, attach: false } }); }) };
});
import { InteractionCard } from "./Interactions";
import { answerBlock } from "../../lib/format";
import { getState, reset, upsertSession } from "../../lib/store";
import { t } from "../../i18n";
import type { Interaction, Session } from "../../lib/types";

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const question = { id: "q_1", machine_id: "m", session_id: "s", kind: "question", questions: [{ question: "Which one?", options: [{ label: "A", description: "" }, { label: "B", description: "" }] }] } as Interaction;
const row = (capabilities?: Session["capabilities"], source_kind?: string) => ({ machine_id: "m", session_id: "s", title: "Demo", state: "needs_you", source_kind, capabilities }) as Session;
const unjoined = row({ read: true, send: true, approve: false, attach: true }, "codex_app_server");
const subagent = row({ read: true, send: false, approve: false, attach: false }, "codex_app_server");

describe("answerBlock", () => {
  it("is null for a card the page can answer, a sessionless one included", () => {
    expect(answerBlock(question, row())).toBeNull();
    expect(answerBlock(question, row({ read: true, approve: true }, "runtime"))).toBeNull();
    expect(answerBlock({ session_id: "" }, undefined)).toBeNull();
  });
  it("offers attach only where the session can be linked live, else the computer", () => {
    expect(answerBlock(question, unjoined)).toBe("attach");
    expect(answerBlock(question, { ...unjoined, attached: true })).toBe("computer");
    expect(answerBlock(question, subagent)).toBe("computer");
    expect(answerBlock(question, undefined)).toBe("computer");
  });
});

let host: HTMLDivElement;
let root: Root;
const flush = async () => {
  for (let i = 0; i < 5; i++) await act(async () => { await Promise.resolve(); });
};
const line = () => host.querySelector<HTMLElement>("[data-card-blocked]");
const option = (label: string) => [...host.querySelectorAll<HTMLButtonElement>("[data-card] button")].find((b) => b.textContent?.includes(label))!;
const locked = (b: HTMLButtonElement) => b.disabled || !!b.closest("fieldset[disabled]");
const render = () => act(() => root.render(<InteractionCard ix={question} />));

beforeEach(() => {
  attached.length = 0;
  Object.assign(getState(), { interactions: [question], answered: {} });
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  reset();
});

describe("a card the page can't answer", () => {
  it("an unjoined thread's card says linking answers it here, and Live link makes it answerable", async () => {
    upsertSession(unjoined);
    render();
    expect(locked(option("A"))).toBe(true);
    expect(line()?.dataset.cardBlocked).toBe("attach");
    expect(line()?.textContent).toContain(t("chat-interactions.blocked_attach"));
    const link = [...line()!.querySelectorAll("button")].find((b) => b.textContent === t("chat-chatview.attach"))!;
    expect(link.disabled).toBe(false);
    await act(async () => link.click());
    await flush();
    expect(attached).toEqual(["m/s"]);
    expect(line()).toBeNull();
    expect(locked(option("A"))).toBe(false);
  });

  it("a subagent its parent drives says to answer on the computer, with no Live link", () => {
    upsertSession(subagent);
    render();
    expect(locked(option("A"))).toBe(true);
    expect(line()?.textContent).toBe(t("chat-interactions.blocked_computer"));
    expect(line()?.querySelector("button")).toBeNull();
  });

  it("an answerable card is as before: no line", () => {
    upsertSession(row());
    render();
    expect(locked(option("A"))).toBe(false);
    expect(line()).toBeNull();
  });
});
