import appIcon from "../assets/app-icon.png";
import { TOUR } from "../data/seed";
import type { Store } from "../store";

export function Tour({ store }: { store: Store }) {
  const { state, patch } = store;
  const step = state.tourStep ?? 0;
  const t = TOUR[step];

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(4,8,20,.62)",
        backdropFilter: "blur(8px)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        zIndex: 60,
        padding: 32,
      }}
    >
      <div
        style={{
          width: "min(600px,100%)",
          background: "var(--panelSolid)",
          backdropFilter: "var(--blur)",
          WebkitBackdropFilter: "var(--blur)",
          border: "1px solid var(--line)",
          borderRadius: 26,
          boxShadow:
            "0 34px 90px rgba(0,0,0,.5), inset 0 1px 0 rgba(255,255,255,.28)",
          padding: "32px 32px 24px",
          display: "flex",
          flexDirection: "column",
          gap: 20,
        }}
      >
        {t.path ? (
          <div
            style={{
              width: 54,
              height: 54,
              borderRadius: 18,
              background: "var(--brandBg)",
              border: "1px solid var(--brandBd)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="var(--onAc)"
              strokeWidth={1.8}
              strokeLinecap="round"
              strokeLinejoin="round"
              style={{ width: 27, height: 27 }}
            >
              <path d={t.path} />
            </svg>
          </div>
        ) : (
          <img
            src={appIcon}
            alt=""
            style={{
              width: 54,
              height: 54,
              borderRadius: 18,
              objectFit: "cover",
              border: "1px solid var(--brandBd)",
            }}
          />
        )}

        <div>
          <div
            style={{
              fontSize: 11.5,
              color: "var(--dim)",
              letterSpacing: ".12em",
            }}
          >
            第 {step + 1} / 3 步
          </div>
          <div
            style={{
              fontSize: 26,
              fontWeight: 600,
              letterSpacing: "-.025em",
              marginTop: 10,
            }}
          >
            {t.title}
          </div>
          <div
            style={{
              fontSize: 14,
              color: "var(--mu)",
              lineHeight: 1.7,
              marginTop: 11,
              textWrap: "pretty",
            }}
          >
            {t.body}
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {t.points.map((p) => (
            <div
              key={p.t}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 11,
                background: "var(--sunk)",
                border: "1px solid var(--line2)",
                borderRadius: 14,
                padding: "11px 14px",
              }}
            >
              <span
                style={{
                  width: 7,
                  height: 7,
                  borderRadius: "50%",
                  flex: "none",
                  background: "var(--ac)",
                }}
              />
              <span style={{ fontSize: 12.5, color: "var(--mu)" }}>{p.t}</span>
            </div>
          ))}
        </div>

        <div
          style={{ display: "flex", alignItems: "center", gap: 12, paddingTop: 2 }}
        >
          <div style={{ display: "flex", gap: 6 }}>
            {TOUR.map((_, i) => (
              <span
                key={i}
                style={{
                  width: 7,
                  height: 7,
                  borderRadius: "50%",
                  background: i === step ? "var(--ac)" : "var(--line2)",
                }}
              />
            ))}
          </div>
          <span style={{ flex: 1 }} />
          <button
            className="link-dim to-tx"
            onClick={() => patch({ tourStep: null })}
            style={{ fontSize: 12.5, cursor: "pointer", fontFamily: "inherit" }}
          >
            跳过
          </button>
          <button
            onClick={() =>
              patch((s) => ({
                tourStep: (s.tourStep ?? 0) >= 2 ? null : (s.tourStep ?? 0) + 1,
              }))
            }
            style={{
              border: "1px solid rgba(255,138,91,.55)",
              borderRadius: 14,
              background:
                "linear-gradient(150deg,rgba(255,138,91,.5),rgba(255,138,91,.16))",
              color: "var(--onAc)",
              padding: "10px 22px",
              fontSize: 13,
              fontWeight: 500,
              cursor: "pointer",
              fontFamily: "inherit",
              boxShadow: "var(--shSm)",
            }}
          >
            {t.cta}
          </button>
        </div>
      </div>
    </div>
  );
}
