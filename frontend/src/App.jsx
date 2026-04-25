import { useState, useEffect, useRef, useCallback } from "react";
import { isLoggedIn, login, getMode, createMonitorWS } from "./api";
import StatusBar from "./components/StatusBar";
import ModeSelector from "./components/ModeSelector";
import ChatBox from "./components/ChatBox";
import NoVNCViewer from "./components/NoVNCViewer";

const GLOBAL_CSS = `
  @import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&display=swap');
  *, *::before, *::after { box-sizing:border-box; margin:0; padding:0; }
  html, body, #root { height:100%; width:100%; background:#000408; color:#aabbcc;
    font-family:'Share Tech Mono','Courier New',monospace; overflow:hidden; }
  ::-webkit-scrollbar { width:4px; }
  ::-webkit-scrollbar-track { background:transparent; }
  ::-webkit-scrollbar-thumb { background:#1a2a3a; border-radius:2px; }
  @keyframes fadeInUp { from{opacity:0;transform:translateY(20px)} to{opacity:1;transform:none} }
  @keyframes fadeIn { from{opacity:0} to{opacity:1} }
  @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.3} }
  @keyframes scanDown { 0%{transform:translateY(-100%)} 100%{transform:translateY(100vh)} }
  @keyframes glitch { 0%,90%,100%{transform:none;opacity:1} 91%{transform:translateX(-2px);opacity:.8}
    93%{transform:translateX(2px);opacity:.9} 95%{transform:translateX(-1px);opacity:.7} }
  @keyframes typingBounce { 0%,60%,100%{transform:translateY(0)} 30%{transform:translateY(-4px)} }
  @keyframes borderGlow { 0%,100%{box-shadow:0 0 8px rgba(0,212,255,0.15)}
    50%{box-shadow:0 0 20px rgba(0,212,255,0.4)} }
  @keyframes loginAppear { 0%{opacity:0;transform:translateY(30px) scale(0.97)}
    100%{opacity:1;transform:none} }
  @keyframes spin { to{transform:rotate(360deg)} }
  @keyframes dashExpand { from{width:0} to{width:60px} }
  textarea::placeholder { color:#1a2030; }
  button:active { transform:scale(0.97); }
`;

function LoginPage({ onLogin }) {
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [showPass, setShowPass] = useState(false);

  const handleLogin = async (e) => {
    e?.preventDefault();
    if (!password || loading) return;
    setLoading(true); setError("");
    try { await login(password); onLogin(); }
    catch (_) { setError("ACCESS DENIED — Invalid credentials"); setPassword(""); }
    finally { setLoading(false); }
  };

  return (
    <div style={{ height:"100vh", display:"flex", alignItems:"center", justifyContent:"center",
      background:"#000408", position:"relative", overflow:"hidden" }}>
      {/* Grid bg */}
      <div style={{ position:"absolute", inset:0, animation:"fadeIn 2s",
        backgroundImage:"linear-gradient(rgba(0,212,255,0.025) 1px,transparent 1px),linear-gradient(90deg,rgba(0,212,255,0.025) 1px,transparent 1px)",
        backgroundSize:"40px 40px" }} />
      {/* Scan line */}
      <div style={{ position:"absolute", left:0, right:0, height:2,
        background:"linear-gradient(transparent,rgba(0,212,255,0.06),transparent)",
        animation:"scanDown 4s linear infinite" }} />
      {/* Card */}
      <div style={{ position:"relative", zIndex:10, width:"min(420px,92vw)",
        padding:"40px 36px", background:"rgba(0,8,20,0.93)",
        border:"1px solid rgba(0,212,255,0.22)", borderRadius:4,
        animation:"loginAppear 0.6s ease",
        boxShadow:"0 0 60px rgba(0,212,255,0.06),inset 0 0 60px rgba(0,0,0,0.5)" }}>
        {/* Logo */}
        <div style={{ textAlign:"center", marginBottom:32 }}>
          <div style={{ display:"flex", justifyContent:"center", gap:4, marginBottom:16 }}>
            {[...Array(6)].map((_,i) => (
              <span key={i} style={{ fontSize:16, color:"#00d4ff",
                filter:"drop-shadow(0 0 4px #00d4ff)", animation:`pulse 2s ${i*0.15}s infinite` }}>⬡</span>
            ))}
          </div>
          <h1 style={{ fontFamily:"'Share Tech Mono',monospace", fontSize:13, fontWeight:700,
            color:"#fff", letterSpacing:3, marginBottom:10, animation:"glitch 8s infinite" }}>
            BROWSER AUTOMATION STUDIO
          </h1>
          <div style={{ display:"flex", alignItems:"center", justifyContent:"center", gap:10 }}>
            <div style={{ height:1, background:"rgba(0,212,255,0.25)",
              animation:"dashExpand 0.8s ease 0.3s both" }} />
            <span style={{ fontSize:8, color:"#00d4ff", letterSpacing:3, whiteSpace:"nowrap" }}>
              SECURE ACCESS TERMINAL
            </span>
            <div style={{ height:1, background:"rgba(0,212,255,0.25)",
              animation:"dashExpand 0.8s ease 0.3s both" }} />
          </div>
        </div>
        {/* Form */}
        <form onSubmit={handleLogin} style={{ display:"flex", flexDirection:"column", gap:20 }}>
          <div style={{ display:"flex", flexDirection:"column", gap:6 }}>
            <label style={{ fontFamily:"monospace", fontSize:9, color:"#446", letterSpacing:2 }}>
              ACCESS CODE
            </label>
            <div style={{ display:"flex", alignItems:"center",
              background:"rgba(0,20,40,0.6)",
              border:`1px solid ${error ? "#ff4466" : loading ? "#00d4ff" : "rgba(0,212,255,0.25)"}`,
              borderRadius:2, padding:"10px 12px", gap:8,
              animation: !error && !loading ? "borderGlow 3s infinite" : "none",
              transition:"border-color 0.3s" }}>
              <span style={{ fontSize:14 }}>🔐</span>
              <input type={showPass ? "text" : "password"} value={password}
                onChange={e => setPassword(e.target.value)}
                onKeyDown={e => e.key==="Enter" && handleLogin()}
                placeholder="Enter access code..." autoFocus disabled={loading}
                style={{ flex:1, background:"none", border:"none", outline:"none",
                  color:"#aaccdd", fontFamily:"monospace", fontSize:13, letterSpacing:1 }} />
              <button type="button" onClick={() => setShowPass(s=>!s)}
                style={{ background:"none", border:"none", color:"#446",
                  cursor:"pointer", fontSize:14, padding:0 }}>
                {showPass ? "◉" : "○"}
              </button>
            </div>
          </div>
          {error && (
            <div style={{ display:"flex", alignItems:"center", gap:8,
              fontFamily:"monospace", fontSize:10, color:"#ff4466", letterSpacing:1,
              padding:"8px 10px", background:"rgba(255,68,102,0.07)",
              border:"1px solid rgba(255,68,102,0.18)", borderRadius:2,
              animation:"fadeIn 0.3s" }}>
              <span>⚠</span>{error}
            </div>
          )}
          <button type="submit" disabled={loading || !password}
            style={{ padding:"12px 20px",
              background:"linear-gradient(135deg,rgba(0,212,255,0.12),rgba(0,255,136,0.04))",
              border:"1px solid rgba(0,212,255,0.35)", color:"#00d4ff",
              fontFamily:"monospace", fontSize:11, letterSpacing:2, fontWeight:700,
              borderRadius:2, transition:"all 0.2s",
              opacity: !password ? 0.5 : 1, cursor: !password ? "not-allowed" : "pointer" }}>
            {loading ? "AUTHENTICATING..." : "INITIALIZE SESSION →"}
          </button>
        </form>
        <div style={{ marginTop:28, display:"flex", justifyContent:"center",
          gap:6, fontFamily:"monospace", fontSize:9, color:"#223", letterSpacing:1 }}>
          <span>M1✓</span><span style={{color:"#112"}}>·</span>
          <span>M2✓</span><span style={{color:"#112"}}>·</span>
          <span>M3✓</span><span style={{color:"#112"}}>·</span>
          <span style={{color:"#00d4ff"}}>M4 ACTIVE</span>
        </div>
      </div>
    </div>
  );
}

function Dashboard({ onLogout }) {
  const [mode, setMode] = useState("IDLE");
  const [showVnc, setShowVnc] = useState(true);
  const [wsConnected, setWsConnected] = useState(false);
  const [lastEvent, setLastEvent] = useState("");
  const [wsEvent, setWsEvent] = useState(null);
  const wsRef = useRef(null);

  useEffect(() => { getMode().then(d => setMode(d.mode)).catch(()=>{}); }, []);

  const connectWS = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;
    try {
      const ws = createMonitorWS(
        (data) => {
          setWsEvent(data);
          setWsConnected(true);
          if (data.type === "task_update")
            setLastEvent(`Task ${data.task_id?.slice(0,6)} → ${data.status}`);
          else if (data.type === "mode_change")
            setLastEvent(`Mode → ${data.data?.mode}`);
        },
        () => { setWsConnected(false); setTimeout(connectWS, 3000); }
      );
      ws.onopen = () => setWsConnected(true);
      wsRef.current = ws;
    } catch(_) {}
  }, []);

  useEffect(() => { connectWS(); return () => wsRef.current?.close(); }, [connectWS]);

  const isMobile = window.innerWidth < 768;

  return (
    <div style={{ height:"100vh", display:"flex", flexDirection:"column",
      background:"#000408", overflow:"hidden", animation:"fadeIn 0.4s" }}>
      <StatusBar mode={mode} lastEvent={lastEvent}
        wsConnected={wsConnected} onLogout={onLogout} />
      <ModeSelector currentMode={mode} onModeChange={setMode} />
      <div style={{ flex:1, display:"flex", overflow:"hidden" }}>
        {/* Chat panel */}
        <div style={{ display:"flex", flexDirection:"column",
          width: showVnc && !isMobile ? "40%" : "100%",
          background:"rgba(0,4,12,0.8)",
          borderRight: showVnc && !isMobile ? "1px solid rgba(0,212,255,0.07)" : "none",
          overflow:"hidden", transition:"width 0.3s ease" }}>
          <div style={{ display:"flex", alignItems:"center", gap:6, padding:"8px 16px",
            borderBottom:"1px solid rgba(0,212,255,0.06)",
            background:"rgba(0,8,20,0.5)", flexShrink:0 }}>
            <span style={{ fontSize:11, color:"#00d4ff" }}>⬡</span>
            <span style={{ fontFamily:"monospace", fontSize:9, color:"#334",
              letterSpacing:2, flex:1 }}>COMMAND TERMINAL</span>
            <button onClick={() => setShowVnc(v=>!v)}
              style={{ background:"none", border:"1px solid #111", color:"#334",
                fontFamily:"monospace", fontSize:8, letterSpacing:1,
                padding:"3px 8px", cursor:"pointer", borderRadius:2 }}>
              {showVnc ? "⇄ EXPAND" : "⇄ CHROME VIEW"}
            </button>
          </div>
          <ChatBox mode={mode} wsEvents={wsEvent} />
        </div>
        {/* Divider */}
        {showVnc && !isMobile && (
          <div style={{ width:1,
            background:"linear-gradient(to bottom,transparent,rgba(0,212,255,0.12),transparent)",
            flexShrink:0 }} />
        )}
        {/* noVNC panel */}
        {showVnc && !isMobile && (
          <div style={{ flex:1, display:"flex", flexDirection:"column",
            overflow:"hidden", background:"#000" }}>
            <NoVNCViewer visible={true} />
          </div>
        )}
      </div>
    </div>
  );
}

export default function App() {
  const [loggedIn, setLoggedIn] = useState(isLoggedIn());

  useEffect(() => {
    const style = document.createElement("style");
    style.textContent = GLOBAL_CSS;
    document.head.appendChild(style);
    return () => document.head.removeChild(style);
  }, []);

  return loggedIn
    ? <Dashboard onLogout={() => setLoggedIn(false)} />
    : <LoginPage onLogin={() => setLoggedIn(true)} />;
}
