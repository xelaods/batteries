import { useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import {
  Battery,
  BatteryCharging,
  Bluetooth,
  Check,
  Copy,
  FileText,
  Laptop,
  Mouse,
  Plug,
  QrCode,
  Send,
  Settings2,
  Smartphone,
  Headphones,
  KeyRound,
  FolderOpen,
  TriangleAlert,
  Gauge,
} from "lucide-react";
import { AnimatedTabs } from "./components/ui/AnimatedTabs";
import { Badge } from "./components/ui/badge";
import { Button } from "./components/ui/Button";
import { SpotlightCard } from "./components/ui/SpotlightCard";
import { StretchSwitch } from "./components/ui/StretchSwitch";
import { BatteryRing } from "./components/BatteryRing";
import { listen, send, type AirPods, type State } from "./bridge";
import { motionTransitions } from "./lib/motion-tokens";
import { cn } from "./lib/utils";

type Toast = { id: number; text: string; tone: "success" | "danger" | "neutral" };

function ago(seconds: number) {
  if (seconds < 60) return "たった今";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}分前`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}時間前`;
  return `${Math.floor(seconds / 86400)}日前`;
}

function clock(unix: number) {
  const d = new Date(unix * 1000);
  return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export default function App() {
  const [state, setState] = useState<State | null>(null);
  const [tab, setTab] = useState("now");
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastId = useRef(0);

  useEffect(() => {
    listen((m) => {
      if (m.type === "state") setState(m.state);
      if (m.type === "toast") {
        const id = ++toastId.current;
        setToasts((t) => [...t.slice(-2), { id, text: m.text, tone: m.tone ?? "neutral" }]);
        setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 2600);
      }
    });
    send({ type: "ready" });
  }, []);

  if (!state) {
    return <div className="h-full grid place-items-center text-text-muted text-sm">読み込み中…</div>;
  }

  const tabs = [
    { id: "now", label: "いまの値", icon: <Battery className="size-3.5" /> },
    { id: "pair", label: "iPhone とつなぐ", icon: <QrCode className="size-3.5" /> },
    { id: "settings", label: "設定", icon: <Settings2 className="size-3.5" /> },
  ];

  return (
    <div className="h-full flex flex-col relative">
      <div className="pointer-events-none absolute inset-0 bg-dot-subtle opacity-40 [mask-image:radial-gradient(ellipse_at_top,black,transparent_70%)]" />
      <Header state={state} />
      <div className="relative px-6 pt-1">
        <AnimatedTabs tabs={tabs} activeTab={tab} onChange={setTab} variant="pill" renderContent={false} layoutId="main-tabs" />
      </div>
      <main className="relative flex-1 overflow-y-auto px-6 pt-5 pb-8">
        <AnimatePresence mode="wait">
          <motion.div
            key={tab}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={motionTransitions.springGentle}
          >
            {tab === "now" && <NowTab state={state} />}
            {tab === "pair" && <PairTab state={state} />}
            {tab === "settings" && <SettingsTab state={state} />}
          </motion.div>
        </AnimatePresence>
      </main>
      <Toasts toasts={toasts} />
    </div>
  );
}

// ---------------------------------------------------------------- ヘッダー

function Header({ state }: { state: State }) {
  const since = state.send.lastSentAt ? state.now - state.send.lastSentAt : null;
  const status = state.send.sending
    ? { tone: "neutral" as const, text: "送信中…", pulse: true }
    : !state.send.ok
      ? { tone: "danger" as const, text: "送信できていません", pulse: false }
      : since !== null && since < 75 * 60
        ? { tone: "success" as const, text: "iPhone に送信中", pulse: true }
        : { tone: "warning" as const, text: "まだ送っていません", pulse: false };

  return (
    <header className="relative flex items-center justify-between px-6 pt-5 pb-4">
      <div className="flex items-center gap-3">
        <div className="grid size-9 place-items-center rounded-[10px] border border-border bg-surface shadow-xs">
          <BatteryCharging className="size-[18px] text-emerald-400" />
        </div>
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-[15px] font-semibold tracking-tight">バッテリー送信</h1>
            <span className="rounded-md border border-border bg-surface-raised px-1.5 py-0.5 font-mono text-[10px] text-text-muted">
              v{state.version}
            </span>
          </div>
          <p className="text-xs text-text-muted">
            {state.pcName} の電池と、近くの AirPods を iPhone に届けます
          </p>
        </div>
      </div>
      <Badge tone={status.tone} dot pulse={status.pulse}>
        {status.text}
      </Badge>
    </header>
  );
}

// ---------------------------------------------------------------- いまの値

function SectionLabel({ icon, children, right }: { icon: React.ReactNode; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="mb-3 flex items-center justify-between">
      <div className="flex items-center gap-2 text-xs font-medium text-text-secondary">
        <span className="text-text-muted">{icon}</span>
        {children}
      </div>
      {right}
    </div>
  );
}

function NowTab({ state }: { state: State }) {
  return (
    <div className="grid grid-cols-5 gap-4">
      <PcCard state={state} />
      <div className="col-span-3 flex flex-col gap-4">
        {state.airpods.length === 0 ? (
          <SpotlightCard className="flex-1 border-dashed border-border bg-surface/60 p-5">
            <SectionLabel icon={<Headphones className="size-3.5" />}>AirPods</SectionLabel>
            <p className="text-sm text-text-secondary">まだ見つかっていません</p>
            <p className="mt-1 text-xs leading-relaxed text-text-muted">
              ケースを開けて PC の近くに置くと、数秒で表示されます。
              {!state.settings.readAirPods && "（設定で「AirPods を読み取る」がオフになっています）"}
            </p>
          </SpotlightCard>
        ) : (
          state.airpods.map((a) => <AirPodsCard key={a.model} airpods={a} now={state.now} />)
        )}
        <MouseCard />
      </div>
      <SendCard state={state} />
    </div>
  );
}

function PcCard({ state }: { state: State }) {
  const pc = state.pc;
  return (
    <SpotlightCard className="col-span-2 border-border bg-surface p-5" spotlightColor="rgba(52, 211, 153, 0.06)">
      <SectionLabel icon={<Laptop className="size-3.5" />}>この PC</SectionLabel>
      {pc ? (
        <div className="flex flex-col items-center pt-2 pb-1">
          <BatteryRing level={pc.level} charging={pc.charging} size={148} stroke={10} />
          <div className="mt-4 text-sm font-medium">{state.pcName}</div>
          <div className="mt-2 flex gap-1.5">
            {pc.charging ? (
              <Badge tone="success">充電中</Badge>
            ) : pc.plugged ? (
              <Badge>
                <Plug className="size-3" />
                電源につながっています
              </Badge>
            ) : (
              <Badge>電池で動作中</Badge>
            )}
          </div>
        </div>
      ) : (
        <div className="flex h-[220px] flex-col items-center justify-center text-center">
          <Laptop className="mb-3 size-8 text-text-subtle" />
          <p className="text-sm text-text-secondary">この PC には電池がありません</p>
          <p className="mt-1 text-xs text-text-muted">デスクトップ PC では AirPods だけを送ります</p>
        </div>
      )}
    </SpotlightCard>
  );
}

function AirPodsCard({ airpods, now }: { airpods: AirPods; now: number }) {
  const order = ["left", "right", "case"];
  const labels: Record<string, string> = { left: "左", right: "右", case: "ケース" };
  const parts = [...airpods.parts].sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
  const latest = Math.max(...parts.map((p) => p.at));
  const fresh = now - latest < 120;
  return (
    <SpotlightCard className="border-border bg-surface p-5" spotlightColor="rgba(96, 165, 250, 0.06)">
      <SectionLabel
        icon={<Headphones className="size-3.5" />}
        right={
          <Badge tone={fresh ? "success" : "neutral"} dot pulse={fresh}>
            {fresh ? "受信中" : `最後の値・${ago(now - latest)}`}
          </Badge>
        }
      >
        {airpods.name}
      </SectionLabel>
      <div className="flex items-center gap-7 pt-1">
        {parts.map((p) => (
          <div key={p.id} className="flex flex-col items-center gap-2">
            <BatteryRing level={p.level} charging={p.charging} size={84} stroke={7} stale={now - p.at > 15 * 60} />
            <span className="text-xs text-text-muted">{labels[p.id] ?? p.id}</span>
          </div>
        ))}
      </div>
    </SpotlightCard>
  );
}

function MouseCard() {
  return (
    <SpotlightCard className="border-border bg-surface p-5">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="grid size-10 place-items-center rounded-lg border border-border bg-surface-raised">
            <Mouse className="size-[18px] text-text-muted" />
          </div>
          <div>
            <div className="text-sm font-medium">マウス（VXE）</div>
            <div className="text-xs text-text-muted">電池の読み方を調べている段階です</div>
          </div>
        </div>
        <Button variant="outline" size="sm" leftIcon={<FileText className="size-3.5" />} onClick={() => send({ type: "dumpHid" })}>
          情報を書き出す
        </Button>
      </div>
    </SpotlightCard>
  );
}

function SendCard({ state }: { state: State }) {
  const bt = state.bluetooth;
  return (
    <SpotlightCard className="col-span-5 border-border bg-surface p-5">
      <div className="flex items-center justify-between gap-6">
        <div className="grid flex-1 grid-cols-2 gap-6">
          <div className="flex items-start gap-3">
            <div className={cn("grid size-10 shrink-0 place-items-center rounded-lg border", state.send.ok ? "border-border bg-surface-raised" : "border-rose-500/30 bg-rose-500/10")}>
              {state.send.ok ? <Smartphone className="size-[18px] text-text-secondary" /> : <TriangleAlert className="size-[18px] text-rose-400" />}
            </div>
            <div>
              <div className="text-sm font-medium">
                {state.send.lastSentAt ? `${clock(state.send.lastSentAt)} に送信` : "まだ送っていません"}
              </div>
              <div className={cn("text-xs", state.send.ok ? "text-text-muted" : "text-rose-400")}>{state.send.result}</div>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <div className="grid size-10 shrink-0 place-items-center rounded-lg border border-border bg-surface-raised">
              <Bluetooth className="size-[18px] text-text-secondary" />
            </div>
            <div>
              <div className="text-sm font-medium">{bt.status}</div>
              <div className="text-xs text-text-muted">
                {bt.lastSignalAt ? `最後の AirPods 信号 ${ago(state.now - bt.lastSignalAt)}・${bt.lastRssi} dBm` : "AirPods の信号はまだ届いていません"}
              </div>
            </div>
          </div>
        </div>
        <Button variant="primary" size="md" isLoading={state.send.sending} loadingText="送信中…" leftIcon={<Send className="size-4" />} onClick={() => send({ type: "send" })}>
          今すぐ送る
        </Button>
      </div>
      <p className="mt-4 border-t border-border pt-3 text-[11px] leading-relaxed text-text-muted">
        値が変わったときは10分ごと、変わらなくても1時間ごとに送ります。ウィンドウを閉じてもタスクトレイで動き続けます。
      </p>
    </SpotlightCard>
  );
}

// ---------------------------------------------------------------- iPhone とつなぐ

function PairTab({ state }: { state: State }) {
  const [copied, setCopied] = useState(false);
  const [join, setJoin] = useState("");
  const [confirming, setConfirming] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const normalized = useMemo(() => {
    let t = join.trim();
    const i = t.toLowerCase().indexOf("code=");
    if (i >= 0) t = t.slice(i + 5);
    t = t.replace(/[\s　]/g, "").toLowerCase();
    return /^[a-z0-9_-]{8,64}$/.test(t) ? t : null;
  }, [join]);

  const copy = () => {
    send({ type: "copy" });
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  };

  return (
    <div className="grid grid-cols-5 gap-4">
      <SpotlightCard className="col-span-2 flex flex-col items-center border-border bg-surface p-6">
        <div className="rounded-2xl bg-white p-3 shadow-[0_10px_30px_-10px_rgba(0,0,0,0.6)]">
          <img src={state.qr} alt="iPhone とつなぐ QR コード" className="block size-[200px] [image-rendering:pixelated]" />
        </div>
        <p className="mt-4 text-center text-xs leading-relaxed text-text-muted">
          iPhone の<span className="text-text-secondary">カメラ</span>で読み取ると、
          <br />
          バッテリーアプリが開いて登録されます
        </p>
      </SpotlightCard>

      <div className="col-span-3 flex flex-col gap-4">
        <SpotlightCard className="border-border bg-surface p-5">
          <SectionLabel icon={<KeyRound className="size-3.5" />}>合言葉</SectionLabel>
          <div className="flex items-center justify-between gap-3 rounded-lg border border-border bg-surface-raised px-4 py-3">
            <span className="font-mono text-[19px] tracking-wide text-text-primary">{state.topicGrouped}</span>
            <Button
              variant="secondary"
              size="sm"
              onClick={copy}
              leftIcon={
                <AnimatePresence mode="wait" initial={false}>
                  <motion.span
                    key={copied ? "ok" : "copy"}
                    initial={{ scale: 0.6, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    exit={{ scale: 0.6, opacity: 0 }}
                    transition={motionTransitions.springSnappy}
                    className="block"
                  >
                    {copied ? <Check className="size-3.5 text-emerald-400" /> : <Copy className="size-3.5" />}
                  </motion.span>
                </AnimatePresence>
              }
            >
              {copied ? "コピーしました" : "コピー"}
            </Button>
          </div>
          <ol className="mt-4 space-y-2 text-xs text-text-secondary">
            {[
              "iPhone のカメラで左の QR コードを読み取る",
              "読み取れないときは、アプリの「PC 連携」に合言葉を入力",
              "ほかの PC にも同じ合言葉を入れると、同じ iPhone に届きます",
            ].map((t, i) => (
              <li key={i} className="flex items-start gap-2.5">
                <span className="grid size-[18px] shrink-0 place-items-center rounded-full border border-border bg-surface-raised font-mono text-[10px] text-text-muted">
                  {i + 1}
                </span>
                <span className="pt-px">{t}</span>
              </li>
            ))}
          </ol>
        </SpotlightCard>

        <SpotlightCard className="border-border bg-surface p-5">
          <SectionLabel icon={<Laptop className="size-3.5" />}>ほかの PC の合言葉を使う</SectionLabel>
          <p className="mb-3 text-xs text-text-muted">2台目以降の PC は、1台目の合言葉を入れると同じ iPhone に届きます。</p>
          <div className="flex gap-2">
            <input
              value={join}
              onChange={(e) => {
                setJoin(e.target.value);
                setError(null);
              }}
              placeholder="bat-xxxx xxxx xxxx xxxx"
              spellCheck={false}
              className="h-10 flex-1 rounded-lg border border-border bg-surface-raised px-3 font-mono text-sm text-text-primary outline-none transition-colors placeholder:text-text-subtle hover:border-border-hover focus:border-[var(--accent-ring)]"
            />
            <Button
              variant="secondary"
              onClick={() => {
                if (!normalized) return setError("英小文字・数字・ハイフンの8文字以上で入力してください");
                if (normalized === state.topic) return setError("今の合言葉と同じです");
                setConfirming(normalized);
              }}
            >
              この合言葉にする
            </Button>
          </div>
          <AnimatePresence>
            {error && (
              <motion.p initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} exit={{ opacity: 0, height: 0 }} className="mt-2 text-xs text-rose-400">
                {error}
              </motion.p>
            )}
            {confirming && (
              <motion.div
                initial={{ opacity: 0, y: -4, height: 0 }}
                animate={{ opacity: 1, y: 0, height: "auto" }}
                exit={{ opacity: 0, y: -4, height: 0 }}
                transition={motionTransitions.springGentle}
                className="overflow-hidden"
              >
                <div className="mt-3 flex items-center justify-between gap-3 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3.5 py-3">
                  <div className="text-xs leading-relaxed text-amber-200/90">
                    <span className="font-mono text-amber-100">{confirming}</span> に変えると、今の合言葉で連携している iPhone には届かなくなります。
                  </div>
                  <div className="flex shrink-0 gap-2">
                    <Button variant="ghost" size="sm" onClick={() => setConfirming(null)}>
                      やめる
                    </Button>
                    <Button
                      variant="primary"
                      size="sm"
                      onClick={() => {
                        send({ type: "join", topic: confirming });
                        setConfirming(null);
                        setJoin("");
                      }}
                    >
                      変える
                    </Button>
                  </div>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </SpotlightCard>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- 設定

function Row({ children, className }: { children: React.ReactNode; className?: string }) {
  return <div className={cn("flex items-center justify-between gap-6 px-5 py-4", className)}>{children}</div>;
}

function SettingsTab({ state }: { state: State }) {
  const [name, setName] = useState(state.pcName);
  useEffect(() => setName(state.pcName), [state.pcName]);
  const [rssi, setRssi] = useState(state.settings.rssi);
  useEffect(() => setRssi(state.settings.rssi), [state.settings.rssi]);
  const fill = `${((rssi + 100) / 70) * 100}%`;

  return (
    <div className="flex flex-col gap-4">
      <SpotlightCard className="border-border bg-surface p-0">
        <Row>
          <div>
            <div className="text-xs font-medium">iPhone に表示する名前</div>
            <div className="mt-0.5 text-[11px] text-text-muted">変えても同じ PC として扱われます</div>
          </div>
          <div className="flex gap-2">
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && name.trim() && send({ type: "rename", name: name.trim() })}
              className="h-8 w-48 rounded-md border border-border bg-surface-raised px-2.5 text-sm outline-none transition-colors hover:border-border-hover focus:border-[var(--accent-ring)]"
            />
            <Button variant="secondary" size="sm" disabled={!name.trim() || name.trim() === state.pcName} onClick={() => send({ type: "rename", name: name.trim() })}>
              変更
            </Button>
          </div>
        </Row>
      </SpotlightCard>

      <SpotlightCard className="border-border bg-surface p-0">
        <div className="divide-y divide-border">
        <Row>
          <StretchSwitch
            className="w-full"
            label="Windows の起動時に自動で起動"
            description="PC を立ち上げると、タスクトレイで動き始めます"
            checked={state.settings.startup}
            onChange={(v) => send({ type: "setting", key: "startup", value: v })}
          />
        </Row>
        <Row>
          <StretchSwitch
            className="w-full"
            label="AirPods を読み取る"
            description="近くの AirPods・Beats の電池を iPhone に送ります"
            checked={state.settings.readAirPods}
            onChange={(v) => send({ type: "setting", key: "readAirPods", value: v })}
          />
        </Row>
        <Row>
          <StretchSwitch
            className="w-full"
            label="AirPods の左右を入れ替える"
            description="左右が逆に表示されるときにオンにします"
            checked={state.settings.swapSides}
            onChange={(v) => send({ type: "setting", key: "swapSides", value: v })}
          />
        </Row>
        <div className="px-5 py-4">
          <div className="flex items-center justify-between">
            <div>
              <div className="flex items-center gap-1.5 text-xs font-medium">
                <Gauge className="size-3.5 text-text-muted" />
                AirPods の電波の強さの基準
              </div>
              <div className="mt-0.5 text-[11px] text-text-muted">これより弱い電波は、周りの人の AirPods として無視します</div>
            </div>
            <span className="rounded-md border border-border bg-surface-raised px-2 py-0.5 font-mono text-xs text-text-secondary">{rssi} dBm</span>
          </div>
          <input
            type="range"
            min={-100}
            max={-30}
            value={rssi}
            onChange={(e) => setRssi(Number(e.target.value))}
            onPointerUp={() => send({ type: "setting", key: "rssi", value: rssi })}
            onKeyUp={() => send({ type: "setting", key: "rssi", value: rssi })}
            className="range mt-4 w-full"
            style={{ ["--fill" as string]: fill }}
          />
          <div className="mt-1.5 flex justify-between text-[10px] text-text-subtle">
            <span>遠くまで拾う</span>
            <span>近くだけ</span>
          </div>
        </div>
        </div>
      </SpotlightCard>

      <div className="flex items-center justify-between px-1 text-[11px] text-text-muted">
        <span>
          バッテリー送信 v{state.version}・中継 ntfy.sh
        </span>
        <button onClick={() => send({ type: "openFolder" })} className="inline-flex items-center gap-1 text-text-muted transition-colors hover:text-text-secondary">
          <FolderOpen className="size-3" />
          設定の保存場所を開く
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- 通知

function Toasts({ toasts }: { toasts: Toast[] }) {
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-5 flex flex-col items-center gap-2">
      <AnimatePresence>
        {toasts.map((t) => (
          <motion.div
            key={t.id}
            layout
            initial={{ opacity: 0, y: 16, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.96 }}
            transition={motionTransitions.springResponsive}
            className="flex items-center gap-2 rounded-full border border-border bg-surface/95 px-4 py-2 text-xs text-text-primary shadow-[0_10px_25px_-8px_rgba(0,0,0,0.6)] backdrop-blur"
          >
            <span className={cn("size-1.5 rounded-full", t.tone === "success" ? "bg-emerald-400" : t.tone === "danger" ? "bg-rose-400" : "bg-neutral-400")} />
            {t.text}
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
}
