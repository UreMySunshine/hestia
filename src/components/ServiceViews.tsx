import type { MouseEvent } from "react";
import type { ServiceVM } from "../lib/vm";
import type { Service } from "../types";
import { Icon } from "./primitives";

interface Props {
  svc: Service;
  vm: ServiceVM;
  onOpen: () => void;
  onToggle: () => void;
}

const monoBox = {
  fontFamily: "JetBrains Mono,monospace",
  color: "var(--mu)",
  background: "var(--sunk)",
  border: "1px solid var(--line2)",
  overflow: "hidden",
  textOverflow: "ellipsis",
  whiteSpace: "nowrap",
} as const;

const ellipsis = {
  overflow: "hidden",
  textOverflow: "ellipsis",
  whiteSpace: "nowrap",
} as const;

function StatePill({ vm, radius }: { vm: ServiceVM; radius: number }) {
  return (
    <span
      style={{
        flex: "none",
        display: "flex",
        alignItems: "center",
        gap: radius > 10 ? 6 : 5,
        padding: radius > 10 ? "4px 10px" : "2px 9px",
        borderRadius: radius,
        fontSize: 10.5,
        fontWeight: 500,
        background: vm.pillBg,
        border: `1px solid ${vm.pillBd}`,
        color: vm.pillTx,
      }}
    >
      <span
        style={{
          width: 5,
          height: 5,
          borderRadius: "50%",
          background: vm.dot,
          animation: vm.pulse,
        }}
      />
      {vm.stateLabel}
    </span>
  );
}

function ToggleButton({
  vm,
  onToggle,
  size,
}: {
  vm: ServiceVM;
  onToggle: () => void;
  size: [number, number];
}) {
  const stop = (e: MouseEvent) => {
    e.stopPropagation();
    onToggle();
  };
  return (
    <button
      onClick={stop}
      title={vm.btnLabel}
      aria-label={vm.btnLabel}
      style={{
        flex: "none",
        width: size[0],
        height: size[1],
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        borderRadius: 12,
        fontSize: 11,
        cursor: "pointer",
        fontFamily: "inherit",
        background: vm.btnBg,
        border: `1px solid ${vm.btnBd}`,
        color: vm.btnTx,
      }}
    >
      <Icon d={vm.btnPath} sw={1.9} />
    </button>
  );
}

/** 网格视图卡片 */
export function ServiceCard({ svc, vm, onOpen, onToggle }: Props) {
  return (
    <div
      onClick={onOpen}
      className="glass card-hover"
      style={{
        borderRadius: 22,
        padding: "17px 18px 15px",
        display: "flex",
        flexDirection: "column",
        gap: 14,
        cursor: "pointer",
        boxShadow: "var(--sh)",
      }}
    >
      <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
        <div
          style={{
            width: 42,
            height: 42,
            flex: "none",
            borderRadius: 14,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: vm.iconBg,
            border: `1px solid ${vm.iconBd}`,
            color: vm.iconTx,
          }}
        >
          <Icon d={vm.iconPath} size={21} sw={1.7} />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 15.5, fontWeight: 600, ...ellipsis }}>
            {svc.name}
          </div>
          <div style={{ fontSize: 11.5, color: "var(--dim)", marginTop: 4 }}>
            {svc.proj}
          </div>
        </div>
        <StatePill vm={vm} radius={11} />
      </div>

      <div
        style={{ ...monoBox, fontSize: 11.5, borderRadius: 13, padding: "10px 13px" }}
      >
        {svc.cmd}
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        {[
          ["目录", svc.cwd],
          ["停止", svc.stop],
        ].map(([k, v]) => (
          <div
            key={k}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 9,
              fontSize: 11.5,
              color: "var(--dim)",
            }}
          >
            <span style={{ width: 34, flex: "none" }}>{k}</span>
            <span
              style={{
                flex: 1,
                minWidth: 0,
                color: "var(--mu)",
                fontFamily: "JetBrains Mono,monospace",
                ...ellipsis,
              }}
            >
              {v}
            </span>
          </div>
        ))}
      </div>

      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 12,
          borderTop: "1px solid var(--line2)",
          paddingTop: 12,
          fontSize: 11.5,
          color: "var(--dim)",
        }}
      >
        <span>{vm.portLabel}</span>
        <span>{vm.uptimeLabel}</span>
        <span>重启 {svc.restarts} 次</span>
        <span style={{ flex: 1 }} />
        <ToggleButton vm={vm} onToggle={onToggle} size={[36, 32]} />
      </div>
    </div>
  );
}

/** 列表视图行 */
export function ServiceRow({ svc, vm, onOpen, onToggle }: Props) {
  return (
    <div
      onClick={onOpen}
      className="glass card-hover"
      style={{
        display: "flex",
        alignItems: "center",
        gap: 14,
        padding: "13px 16px",
        borderRadius: 18,
        cursor: "pointer",
        minWidth: 0,
        boxShadow: "var(--shSm)",
      }}
    >
      <div
        style={{
          width: 38,
          height: 38,
          flex: "none",
          borderRadius: 13,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: vm.iconBg,
          border: `1px solid ${vm.iconBd}`,
          color: vm.iconTx,
        }}
      >
        <Icon d={vm.iconPath} size={19} sw={1.7} />
      </div>

      <div style={{ flex: "2 1 180px", minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
          <span style={{ fontSize: 14.5, fontWeight: 600, ...ellipsis }}>
            {svc.name}
          </span>
          <StatePill vm={vm} radius={10} />
        </div>
        <div
          style={{
            fontSize: 11.5,
            color: "var(--dim)",
            marginTop: 5,
            ...ellipsis,
          }}
        >
          {svc.proj} · {vm.portLabel} · {vm.uptimeLabel}
        </div>
      </div>

      <div
        style={{
          ...monoBox,
          flex: "3 1 140px",
          minWidth: 0,
          fontSize: 11.5,
          borderRadius: 12,
          padding: "9px 13px",
        }}
      >
        {svc.cmd}
      </div>

      <div
        style={{
          width: 132,
          flex: "none",
          fontSize: 11.5,
          color: "var(--dim)",
          ...ellipsis,
        }}
      >
        {svc.cwd}
      </div>

      <ToggleButton vm={vm} onToggle={onToggle} size={[36, 32]} />
    </div>
  );
}
