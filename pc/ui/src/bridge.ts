// PC アプリ（C#）とのやりとり。WebView2 の postMessage を使う。
// ブラウザで開いたとき（開発・見た目の確認）は見本のデータで動く。

export type Part = { id: string; level: number; charging: boolean; at: number };
export type AirPods = { model: number; name: string; parts: Part[] };

export type State = {
  version: string;
  pcName: string;
  topic: string;
  topicGrouped: string;
  qr: string;
  pc: { level: number; charging: boolean; plugged: boolean } | null;
  airpods: AirPods[];
  mouse: { name: string; level: number; charging: boolean; millivolts: number; at: number } | null;
  mouseStatus: string;
  bluetooth: { status: string; lastSignalAt: number | null; lastRssi: number | null; signals: number };
  send: { lastSentAt: number | null; result: string; ok: boolean; sending: boolean };
  settings: { startup: boolean; readAirPods: boolean; swapSides: boolean; rssi: number };
  dataFolder: string;
  now: number;
};

export type Command =
  | { type: "ready" }
  | { type: "send" }
  | { type: "copy" }
  | { type: "join"; topic: string }
  | { type: "rename"; name: string }
  | { type: "setting"; key: "startup" | "readAirPods" | "swapSides" | "rssi"; value: boolean | number }
  | { type: "dumpHid" }
  | { type: "pollMouse" }
  | { type: "openFolder" };

export type Incoming =
  | { type: "state"; state: State }
  | { type: "toast"; text: string; tone?: "success" | "danger" | "neutral" };

type WebView = {
  postMessage: (m: unknown) => void;
  addEventListener: (t: "message", f: (e: { data: unknown }) => void) => void;
};

const webview: WebView | undefined = (window as unknown as { chrome?: { webview?: WebView } }).chrome?.webview;
export const isDemo = !webview;

let listener: ((m: Incoming) => void) | null = null;

export function listen(f: (m: Incoming) => void) {
  listener = f;
  if (webview) {
    webview.addEventListener("message", (e) => f(e.data as Incoming));
  } else {
    demo.start();
  }
}

export function send(c: Command) {
  if (webview) webview.postMessage(c);
  else demo.handle(c);
}

// ---- 見本のデータ（ブラウザで開いたとき） ----

const demo = (() => {
  const now = () => Math.floor(Date.now() / 1000);
  const QR =
    "data:image/svg+xml;utf8," +
    encodeURIComponent(
      `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 29 29' shape-rendering='crispEdges'><rect width='29' height='29' fill='white'/>${Array.from(
        { length: 29 * 29 },
        (_, i) => {
          const x = i % 29, y = Math.floor(i / 29);
          const finder = (cx: number, cy: number) => x >= cx && x < cx + 7 && y >= cy && y < cy + 7 && !(x > cx && x < cx + 6 && y > cy && y < cy + 6 && !(x > cx + 1 && x < cx + 5 && y > cy + 1 && y < cy + 5));
          const on = finder(1, 1) || finder(21, 1) || finder(1, 21) || (x > 1 && y > 1 && x < 28 && y < 28 && !(x < 9 && y < 9) && !(x > 19 && y < 9) && !(x < 9 && y > 19) && ((x * 7 + y * 13 + x * y) % 5 < 2));
          return on ? `<rect x='${x}' y='${y}' width='1' height='1'/>` : "";
        }
      ).join("")}</svg>`
    );
  let state: State = {
    version: "1.0.5",
    pcName: "HIKARU",
    topic: "bat-7k2m9qx4vd8pn3hr",
    topicGrouped: "bat-7k2m 9qx4 vd8p n3hr",
    qr: QR,
    pc: { level: 82, charging: true, plugged: true },
    airpods: [
      {
        model: 0x1420,
        name: "AirPods Pro（第2世代）",
        parts: [
          { id: "left", level: 80, charging: false, at: now() - 240 },
          { id: "right", level: 70, charging: false, at: now() - 240 },
          { id: "case", level: 40, charging: true, at: now() - 3600 },
        ],
      },
    ],
    mouse: { name: "VXE マウス", level: 55, charging: false, millivolts: 3912, at: now() - 90 },
    mouseStatus: "読み取りました",
    bluetooth: { status: "AirPods を受信中", lastSignalAt: now() - 4, lastRssi: -48, signals: 214 },
    send: { lastSentAt: now() - 420, result: "送信しました", ok: true, sending: false },
    settings: { startup: true, readAirPods: true, swapSides: false, rssi: -70 },
    dataFolder: "C:\\Users\\haruto\\AppData\\Roaming\\BatteriesPC",
    now: now(),
  };
  const push = () => listener?.({ type: "state", state: { ...state, now: now() } });
  return {
    start() {
      const params = new URLSearchParams(location.search);
      if (params.has("empty")) state = { ...state, airpods: [], pc: null, mouse: null, mouseStatus: "レシーバーが HID Remapper の先にあるため読めません（PC に直接挿すと読めます）" };
      push();
      setInterval(() => {
        if (state.pc && !params.has("still")) {
          state = { ...state, pc: { ...state.pc, level: Math.min(100, state.pc.level + 1) } };
        }
        push();
      }, 3000);
    },
    handle(c: Command) {
      switch (c.type) {
        case "send":
          state = { ...state, send: { ...state.send, sending: true } };
          push();
          setTimeout(() => {
            state = { ...state, send: { lastSentAt: now(), result: "送信しました", ok: true, sending: false } };
            push();
            listener?.({ type: "toast", text: "iPhone に送りました", tone: "success" });
          }, 900);
          break;
        case "copy":
          listener?.({ type: "toast", text: "合言葉をコピーしました", tone: "success" });
          break;
        case "rename":
          state = { ...state, pcName: c.name };
          push();
          listener?.({ type: "toast", text: "名前を変えました", tone: "success" });
          break;
        case "setting":
          state = { ...state, settings: { ...state.settings, [c.key]: c.value } };
          push();
          break;
        case "join":
          state = { ...state, topic: c.topic, topicGrouped: c.topic };
          push();
          listener?.({ type: "toast", text: "合言葉を変えました", tone: "success" });
          break;
        case "pollMouse":
          listener?.({ type: "toast", text: state.mouseStatus, tone: "success" });
          break;
        case "dumpHid":
          listener?.({ type: "toast", text: "デスクトップに batteries-hid.txt を作りました", tone: "neutral" });
          break;
      }
    },
  };
})();
