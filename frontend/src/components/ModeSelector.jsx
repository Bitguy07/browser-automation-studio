import { useState } from "react";
import { switchMode } from "../api";

const MODES = [
  { id:"IDLE",       label:"IDLE",   icon:"⏸", color:"#00ff88", desc:"Standby" },
  { id:"MANUAL",     label:"MANUAL", icon:"🖱", color:"#ffaa00", desc:"You control" },
  { id:"AUTONOMOUS", label:"AUTO",   icon:"⚡", color:"#00d4ff", desc:"AI drives" },
];

export default function ModeSelector({ currentMode, onModeChange }) {
  const [loading, setLoading] = useState(false);

  const handleSwitch = async (modeId) => {
    if (modeId === currentMode || loading) return;
    setLoading(true);
    try {
      await switchMode(modeId);
      onModeChange(modeId);
    } catch (e) {
      console.error("Mode switch failed:", e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={S.container}>
      <div style={S.label}>MODE</div>
      <div style={S.buttons}>
        {MODES.map((m) => {
          const active = currentMode === m.id;
          return (
            <button key={m.id} onClick={() => handleSwitch(m.id)}
              disabled={loading} title={m.desc}
              style={{ ...S.btn,
                borderColor: active ? m.color : "#1a2030",
                color: active ? m.color : "#334",
                background: active ? `${m.color}12` : "transparent",
                boxShadow: active ? `0 0 10px ${m.color}28` : "none",
                cursor: loading ? "not-allowed" : "pointer",
              }}
              onMouseEnter={e => { if (!active) {
                e.currentTarget.style.borderColor = m.color+"55";
                e.currentTarget.style.color = m.color+"88";
              }}}
              onMouseLeave={e => { if (!active) {
                e.currentTarget.style.borderColor = "#1a2030";
                e.currentTarget.style.color = "#334";
              }}}>
              <span>{m.icon}</span>
              <span style={S.btnLabel}>{m.label}</span>
              {active && <span style={{ ...S.activeDot, background:m.color,
                boxShadow:`0 0 4px ${m.color}` }} />}
            </button>
          );
        })}
      </div>
    </div>
  );
}

const S = {
  container: { display:"flex", alignItems:"center", gap:10,
    padding:"8px 16px", borderBottom:"1px solid rgba(0,212,255,0.06)", flexShrink:0 },
  label: { fontFamily:"monospace", fontSize:9, color:"#223", letterSpacing:2, marginRight:4 },
  buttons: { display:"flex", gap:6 },
  btn: { display:"flex", alignItems:"center", gap:5, padding:"5px 14px",
    border:"1px solid", borderRadius:2, fontFamily:"monospace",
    fontSize:10, letterSpacing:1, fontWeight:700,
    transition:"all 0.15s ease", position:"relative", minWidth:80 },
  btnLabel: { flex:1, textAlign:"center" },
  activeDot: { width:5, height:5, borderRadius:"50%",
    position:"absolute", top:3, right:3 },
};
