import { useState, useEffect } from "react";
import { getHealth, logout } from "../api";

const MODE_COLORS = {
  IDLE: "#00ff88",
  MANUAL: "#ffaa00",
  AUTONOMOUS: "#00d4ff",
};

export default function StatusBar({ mode, lastEvent, onLogout, wsConnected }) {
  const [health, setHealth] = useState(null);
  const [time, setTime] = useState(new Date());

  useEffect(() => {
    const fetch_ = async () => {
      try { setHealth(await getHealth()); } catch (_) {}
    };
    fetch_();
    const hi = setInterval(fetch_, 15000);
    const ti = setInterval(() => setTime(new Date()), 1000);
    return () => { clearInterval(hi); clearInterval(ti); };
  }, []);

  const handleLogout = async () => {
    try { await logout(); } finally { onLogout(); }
  };

  const modeColor = MODE_COLORS[mode] || "#00ff88";
  const allOk = health && Object.values(health.components || {}).every(v => v === "ok");

  return (
    <div style={S.bar}>
      <div style={S.logo}>
        <span style={S.logoIcon}>⬡</span>
        <span style={S.logoText}>BAS</span>
        <span style={S.logoSub}>v3.0</span>
      </div>
      <div style={S.center}>
        <div style={{ ...S.badge, borderColor: modeColor, color: modeColor }}>
          <span style={{ ...S.dot, background: modeColor, boxShadow: `0 0 6px ${modeColor}` }} />
          {mode}
        </div>
        <div style={S.indicator}>
          <span style={{ ...S.dot, background: allOk ? "#00ff88" : "#ff4466",
            boxShadow: `0 0 6px ${allOk ? "#00ff88" : "#ff4466"}` }} />
          <span style={S.indLabel}>{allOk ? "SYS OK" : "SYS ERR"}</span>
        </div>
        <div style={S.indicator}>
          <span style={{ ...S.dot, background: wsConnected ? "#00d4ff" : "#444",
            boxShadow: wsConnected ? "0 0 6px #00d4ff" : "none" }} />
          <span style={S.indLabel}>{wsConnected ? "WS LIVE" : "WS OFF"}</span>
        </div>
        {lastEvent && (
          <div style={S.lastEvent}>
            <span style={S.eventDash}>›</span>
            <span style={S.eventText}>{lastEvent}</span>
          </div>
        )}
      </div>
      <div style={S.right}>
        <span style={S.clock}>
          {time.toLocaleTimeString("en-US", { hour12: false })}
        </span>
        <button style={S.logoutBtn} onClick={handleLogout}
          onMouseEnter={e => { e.target.style.color="#ff4466"; e.target.style.borderColor="#ff446666"; }}
          onMouseLeave={e => { e.target.style.color="#666"; e.target.style.borderColor="#333"; }}>
          ⏻ EXIT
        </button>
      </div>
    </div>
  );
}

const S = {
  bar: { height:48, background:"rgba(0,8,20,0.95)", borderBottom:"1px solid rgba(0,212,255,0.2)",
    display:"flex", alignItems:"center", padding:"0 16px", gap:16, flexShrink:0,
    backdropFilter:"blur(10px)", zIndex:100 },
  logo: { display:"flex", alignItems:"center", gap:6, marginRight:8 },
  logoIcon: { fontSize:18, color:"#00d4ff", filter:"drop-shadow(0 0 4px #00d4ff)" },
  logoText: { fontFamily:"'Courier New',monospace", fontWeight:700, fontSize:13,
    color:"#fff", letterSpacing:2 },
  logoSub: { fontSize:9, color:"#334", fontFamily:"monospace", marginTop:2 },
  center: { flex:1, display:"flex", alignItems:"center", gap:16, overflow:"hidden" },
  badge: { display:"flex", alignItems:"center", gap:5, padding:"3px 10px",
    border:"1px solid", borderRadius:2, fontFamily:"monospace", fontSize:11,
    fontWeight:700, letterSpacing:1, whiteSpace:"nowrap" },
  indicator: { display:"flex", alignItems:"center", gap:5 },
  indLabel: { fontFamily:"monospace", fontSize:10, color:"#556", letterSpacing:1, whiteSpace:"nowrap" },
  dot: { width:6, height:6, borderRadius:"50%", flexShrink:0 },
  lastEvent: { display:"flex", alignItems:"center", gap:4, overflow:"hidden", maxWidth:280 },
  eventDash: { color:"#00d4ff", fontFamily:"monospace", fontSize:12, flexShrink:0 },
  eventText: { fontFamily:"monospace", fontSize:10, color:"#446",
    overflow:"hidden", textOverflow:"ellipsis", whiteSpace:"nowrap" },
  right: { display:"flex", alignItems:"center", gap:12 },
  clock: { fontFamily:"monospace", fontSize:11, color:"#334", letterSpacing:1, whiteSpace:"nowrap" },
  logoutBtn: { background:"none", border:"1px solid #333", color:"#666",
    fontFamily:"monospace", fontSize:10, letterSpacing:1,
    padding:"4px 10px", cursor:"pointer", borderRadius:2, transition:"all 0.2s" },
};
