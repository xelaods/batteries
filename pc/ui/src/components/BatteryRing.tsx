import { motion } from "framer-motion";
import { Zap } from "lucide-react";
import { AnimatedNumber } from "./ui/AnimatedNumber";
import { motionTransitions } from "../lib/motion-tokens";
import { cn } from "../lib/utils";

export function levelColor(level: number, charging: boolean) {
  if (charging) return "#34d399"; // emerald-400
  if (level <= 10) return "#fb7185"; // rose-400
  if (level <= 20) return "#fbbf24"; // amber-400
  return "#34d399";
}

/** 丸いメーター（標準のバッテリーウィジェット風）。中に数字か絵を入れる */
export function BatteryRing({
  level,
  charging,
  size = 120,
  stroke = 8,
  stale = false,
  showNumber = true,
  icon,
  className,
}: {
  level: number;
  charging: boolean;
  size?: number;
  stroke?: number;
  stale?: boolean;
  showNumber?: boolean;
  icon?: React.ReactNode;
  className?: string;
}) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const color = levelColor(level, charging);
  const fraction = Math.max(0.02, Math.min(1, level / 100));

  return (
    <div className={cn("relative shrink-0", className)} style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeOpacity={0.14} strokeWidth={stroke} />
        <motion.circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          strokeOpacity={stale ? 0.5 : 1}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          initial={{ strokeDashoffset: c }}
          animate={{ strokeDashoffset: c * (1 - fraction) }}
          transition={motionTransitions.springGentle}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        {showNumber ? (
          <div className={cn("flex items-baseline font-semibold text-text-primary", stale && "text-text-secondary")} style={{ fontSize: size * 0.27 }}>
            <AnimatedNumber value={level} useGrouping={false} className="font-sans tracking-tight" />
            <span className="ml-0.5 text-text-muted" style={{ fontSize: size * 0.12 }}>
              %
            </span>
          </div>
        ) : (
          <div className={cn("text-text-secondary", stale && "opacity-60")}>{icon}</div>
        )}
      </div>
      {charging && (
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={motionTransitions.springSnappy}
          className="absolute -top-0.5 -right-0.5 grid place-items-center rounded-full bg-emerald-400 text-[#0b2a1d] ring-4 ring-[var(--surface)]"
          style={{ width: size * 0.2, height: size * 0.2, minWidth: 18, minHeight: 18 }}
        >
          <Zap className="size-[60%]" fill="currentColor" strokeWidth={0} />
        </motion.div>
      )}
    </div>
  );
}
