#!/bin/bash
# ============================================================
# Browser Automation Studio — setup_m4.sh
# Applies M4 file changes: React frontend + updated main.py
#
# Run from INSIDE the project directory:
#   cd ~/Documents/studies/Development/BrowserAutomaionStudio/browser-automation-studio
#   bash setup_m4.sh
#
# What this does:
#   1. Writes frontend/src/App.jsx
#   2. Writes frontend/src/api.js
#   3. Writes frontend/src/index.jsx
#   4. Writes frontend/src/components/StatusBar.jsx
#   5. Writes frontend/src/components/ModeSelector.jsx
#   6. Writes frontend/src/components/NoVNCViewer.jsx
#   7. Writes frontend/src/components/ChatBox.jsx
#   8. Writes frontend/public/index.html  (updated)
#   9. Writes frontend/package.json       (updated with Google Fonts)
#   10. Writes guide_m4.md
#
#   Does NOT touch: .env, Dockerfile, supervisord.conf,
#                   backend/, data/, scripts/
#
# NOTE: Docker rebuild IS required after this script
#       because React must be compiled into static files.
# ============================================================

set -e

echo "======================================================"
echo "  Browser Automation Studio — M4 Setup"
echo "======================================================"

# Works from inside or outside the project directory
if [ -f "Dockerfile" ] && [ -d "backend" ]; then
    echo "Running from inside project directory: $(pwd)"
elif [ -d "browser-automation-studio" ]; then
    cd "browser-automation-studio"
    echo "Entered project directory: $(pwd)"
else
    echo "ERROR: Cannot find project."
    echo "Run from inside browser-automation-studio/ or its parent."
    exit 1
fi
echo ""

# Ensure component directory exists
mkdir -p frontend/src/components
mkdir -p frontend/public

# ==============================================================
# FILE: frontend/public/index.html
# ==============================================================
echo "Writing frontend/public/index.html..."
cat > frontend/public/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000408" />
    <meta name="description" content="Browser Automation Studio — AI-powered browser control" />
    <title>Browser Automation Studio</title>
    <style>
      body { margin: 0; background: #000408; }
      #root { height: 100vh; }
    </style>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
HTML_EOF

# ==============================================================
# FILE: frontend/package.json
# ==============================================================
echo "Writing frontend/package.json..."
cat > frontend/package.json << 'PKG_EOF'
{
  "name": "browser-automation-studio-frontend",
  "version": "4.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "react-scripts": "5.0.1",
    "axios": "^1.7.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "proxy": "http://localhost:7860",
  "eslintConfig": {
    "extends": ["react-app"],
    "rules": {
      "no-unused-vars": "warn"
    }
  },
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version"]
  }
}
PKG_EOF

# ==============================================================
# FILE: frontend/src/index.jsx
# ==============================================================
echo "Writing frontend/src/index.jsx..."
cat > frontend/src/index.jsx << 'IDX_EOF'
import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";

const container = document.getElementById("root");
const root = createRoot(container);
root.render(<React.StrictMode><App /></React.StrictMode>);
IDX_EOF

# ==============================================================
# FILE: frontend/src/api.js
# ==============================================================
echo "Writing frontend/src/api.js..."
cat > frontend/src/api.js << 'API_EOF'
// ============================================================
// Browser Automation Studio — frontend/src/api.js
// M4: All API calls to FastAPI backend
// ============================================================

const BASE = window.location.origin;

export const getToken = () => localStorage.getItem("bas_token");
export const setToken = (t) => localStorage.setItem("bas_token", t);
export const clearToken = () => localStorage.removeItem("bas_token");
export const isLoggedIn = () => !!getToken();

const authHeaders = () => ({
  "Content-Type": "application/json",
  Authorization: `Bearer ${getToken()}`,
});

async function apiFetch(path, options = {}) {
  const res = await fetch(`${BASE}${path}`, options);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data?.detail || `HTTP ${res.status}`);
  return data;
}

export async function login(password) {
  const data = await apiFetch("/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  setToken(data.access_token);
  return data;
}

export async function logout() {
  try {
    await apiFetch("/api/auth/logout", { method: "POST", headers: authHeaders() });
  } finally {
    clearToken();
  }
}

export async function getHealth() {
  return apiFetch("/health");
}

export async function getMode() {
  return apiFetch("/api/mode", { headers: authHeaders() });
}

export async function switchMode(mode) {
  return apiFetch("/api/mode/switch", {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ mode }),
  });
}

export async function submitTask(objective, mode = "auto") {
  return apiFetch("/api/task/submit", {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ objective, mode }),
  });
}

export async function getTaskStatus(taskId) {
  return apiFetch(`/api/task/${taskId}/status`, { headers: authHeaders() });
}

export async function listTasks() {
  return apiFetch("/api/task/list", { headers: authHeaders() });
}

export async function cancelTask(taskId) {
  return apiFetch(`/api/task/${taskId}`, { method: "DELETE", headers: authHeaders() });
}

export async function getScreenshot() {
  return apiFetch("/api/browser/screenshot", { headers: authHeaders() });
}

export async function saveSession(name) {
  return apiFetch("/api/session/save", {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ name }),
  });
}

export async function listSessions() {
  return apiFetch("/api/session/list", { headers: authHeaders() });
}

export async function loadSession(name) {
  return apiFetch(`/api/session/load/${name}`, { method: "POST", headers: authHeaders() });
}

export async function getVncStatus() {
  return apiFetch("/api/vnc/status", { headers: authHeaders() });
}

export function createMonitorWS(onMessage, onClose) {
  const token = getToken();
  const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
  const host = window.location.host;
  const ws = new WebSocket(`${proto}//${host}/api/ws/monitor?token=${token}`);
  ws.onmessage = (e) => {
    try { onMessage(JSON.parse(e.data)); } catch (_) {}
  };
  ws.onclose = onClose || (() => {});
  ws.onerror = () => ws.close();
  return ws;
}
API_EOF

# ==============================================================
# FILE: frontend/src/components/StatusBar.jsx
# ==============================================================
echo "Writing frontend/src/components/StatusBar.jsx..."
cat > frontend/src/components/StatusBar.jsx << 'SB_EOF'
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
SB_EOF

# ==============================================================
# FILE: frontend/src/components/ModeSelector.jsx
# ==============================================================
echo "Writing frontend/src/components/ModeSelector.jsx..."
cat > frontend/src/components/ModeSelector.jsx << 'MS_EOF'
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
MS_EOF

# ==============================================================
# FILE: frontend/src/components/NoVNCViewer.jsx
# ==============================================================
echo "Writing frontend/src/components/NoVNCViewer.jsx..."
cat > frontend/src/components/NoVNCViewer.jsx << 'VNC_EOF'
import { useState, useRef } from "react";

export default function NoVNCViewer({ visible }) {
  const [connected, setConnected] = useState(false);
  const [loading, setLoading] = useState(true);
  const iframeRef = useRef(null);

  const vncUrl = "/vnc/vnc.html?autoconnect=true&resize=scale&reconnect=true&reconnect_delay=2000";

  const handleLoad = () => { setLoading(false); setConnected(true); };

  const handleReconnect = () => {
    setLoading(true); setConnected(false);
    if (iframeRef.current) iframeRef.current.src = vncUrl;
  };

  if (!visible) return null;

  return (
    <div style={S.container}>
      <div style={S.header}>
        <div style={S.headerLeft}>
          <span style={S.headerIcon}>⬡</span>
          <span style={S.headerTitle}>CHROME LIVE VIEW</span>
        </div>
        <div style={S.headerRight}>
          <div style={S.connStatus}>
            <span style={{ ...S.connDot,
              background: connected ? "#00ff88" : "#ff4466",
              boxShadow: connected ? "0 0 6px #00ff88" : "0 0 6px #ff4466" }} />
            <span style={{ ...S.connLabel, color: connected ? "#00ff88" : "#ff4466" }}>
              {loading ? "CONNECTING..." : connected ? "LIVE" : "DISCONNECTED"}
            </span>
          </div>
          <button style={S.reconnectBtn} onClick={handleReconnect}>⟳ RECONNECT</button>
        </div>
      </div>
      <div style={S.scanlines} />
      {loading && (
        <div style={S.loadingOverlay}>
          <div style={{ textAlign:"center" }}>
            <div style={S.spinRing} />
            <div style={S.loadingText}>INITIALIZING CHROME STREAM</div>
            <div style={S.loadingSub}>Connecting to noVNC</div>
          </div>
        </div>
      )}
      <iframe ref={iframeRef} src={vncUrl}
        style={{ ...S.iframe, opacity: loading ? 0 : 1, transition:"opacity 0.5s" }}
        onLoad={handleLoad} title="Chrome Live View" allow="fullscreen" />
      <div style={{ ...S.corner, top:40, left:0 }} />
      <div style={{ ...S.corner, top:40, right:0, transform:"scaleX(-1)" }} />
      <div style={{ ...S.corner, bottom:0, left:0, transform:"scaleY(-1)" }} />
      <div style={{ ...S.corner, bottom:0, right:0, transform:"scale(-1)" }} />
    </div>
  );
}

const S = {
  container: { flex:1, display:"flex", flexDirection:"column",
    background:"#000", position:"relative", overflow:"hidden" },
  header: { display:"flex", alignItems:"center", justifyContent:"space-between",
    padding:"8px 12px", background:"rgba(0,8,20,0.9)",
    borderBottom:"1px solid rgba(0,212,255,0.12)", flexShrink:0, zIndex:10 },
  headerLeft: { display:"flex", alignItems:"center", gap:6 },
  headerIcon: { color:"#00d4ff", fontSize:12 },
  headerTitle: { fontFamily:"monospace", fontSize:10, color:"#00d4ff",
    letterSpacing:2, fontWeight:700 },
  headerRight: { display:"flex", alignItems:"center", gap:10 },
  connStatus: { display:"flex", alignItems:"center", gap:5 },
  connDot: { width:7, height:7, borderRadius:"50%" },
  connLabel: { fontFamily:"monospace", fontSize:9, letterSpacing:1 },
  reconnectBtn: { background:"none", border:"1px solid #222", color:"#445",
    fontFamily:"monospace", fontSize:9, letterSpacing:1,
    padding:"3px 8px", cursor:"pointer", borderRadius:2 },
  scanlines: { position:"absolute", inset:0, zIndex:5, pointerEvents:"none",
    background:"repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(0,0,0,0.03) 2px,rgba(0,0,0,0.03) 4px)" },
  loadingOverlay: { position:"absolute", inset:0, zIndex:20,
    display:"flex", alignItems:"center", justifyContent:"center",
    background:"rgba(0,4,12,0.95)" },
  spinRing: { width:40, height:40, border:"2px solid #112",
    borderTop:"2px solid #00d4ff", borderRadius:"50%",
    animation:"spin 0.8s linear infinite", margin:"0 auto 16px" },
  loadingText: { fontFamily:"monospace", fontSize:10, color:"#00d4ff",
    letterSpacing:3, marginBottom:6 },
  loadingSub: { fontFamily:"monospace", fontSize:8, color:"#334", letterSpacing:1 },
  iframe: { flex:1, border:"none", width:"100%", height:"100%", display:"block" },
  corner: { position:"absolute", width:12, height:12, zIndex:15,
    borderTop:"2px solid rgba(0,212,255,0.35)", borderLeft:"2px solid rgba(0,212,255,0.35)",
    pointerEvents:"none" },
};
VNC_EOF

# ==============================================================
# FILE: frontend/src/components/ChatBox.jsx
# ==============================================================
echo "Writing frontend/src/components/ChatBox.jsx..."
cat > frontend/src/components/ChatBox.jsx << 'CB_EOF'
import { useState, useRef, useEffect } from "react";
import { submitTask } from "../api";

const STATUS_COLORS = { PENDING:"#ffaa00", RUNNING:"#00d4ff",
  COMPLETED:"#00ff88", FAILED:"#ff4466", CANCELLED:"#446" };
const STATUS_ICONS = { PENDING:"⏳", RUNNING:"⚡", COMPLETED:"✓", FAILED:"✗", CANCELLED:"○" };

function SystemMsg({ content }) {
  return (
    <div style={{ display:"flex", justifyContent:"center", padding:"4px 0" }}>
      <span style={{ fontFamily:"monospace", fontSize:9, color:"#223", letterSpacing:2,
        borderTop:"1px solid #0d1825", borderBottom:"1px solid #0d1825", padding:"3px 12px" }}>
        {content}
      </span>
    </div>
  );
}

function BotMsg({ content, task }) {
  return (
    <div style={{ display:"flex", alignItems:"flex-start", gap:8 }}>
      <span style={{ fontSize:14, color:"#00d4ff", filter:"drop-shadow(0 0 4px #00d4ff)",
        marginTop:2, flexShrink:0 }}>⬡</span>
      <div style={{ maxWidth:"75%", padding:"8px 12px", borderRadius:"0 4px 4px 4px",
        background:"rgba(0,20,40,0.8)", border:"1px solid rgba(0,212,255,0.12)",
        fontFamily:"monospace", fontSize:11, color:"#99aacc", lineHeight:1.6 }}>
        <div style={{ whiteSpace:"pre-wrap" }}>{content}</div>
        {task && (
          <div style={{ marginTop:8, padding:"6px 8px", background:"rgba(0,0,0,0.3)",
            borderRadius:2, fontSize:10, display:"flex", flexDirection:"column", gap:4 }}>
            <span style={{ color: STATUS_COLORS[task.status] }}>
              {STATUS_ICONS[task.status]} {task.status}
            </span>
            {task.status === "RUNNING" && task.progress > 0 && (
              <div style={{ height:2, background:"#0a1520", borderRadius:1 }}>
                <div style={{ height:"100%", width:`${task.progress}%`,
                  background:"#00d4ff", boxShadow:"0 0 4px #00d4ff",
                  transition:"width 0.3s ease", borderRadius:1 }} />
              </div>
            )}
            {task.result && <div style={{ color:"#556", fontSize:9, lineHeight:1.5,
              wordBreak:"break-word" }}>{task.result}</div>}
            {task.error && <div style={{ color:"#ff4466", fontSize:9 }}>{task.error}</div>}
          </div>
        )}
        <div style={{ fontSize:8, color:"#223", marginTop:4, textAlign:"right",
          letterSpacing:1 }}>{task?.time}</div>
      </div>
    </div>
  );
}

function UserMsg({ content, time }) {
  return (
    <div style={{ display:"flex", alignItems:"flex-start", gap:8, justifyContent:"flex-end" }}>
      <div style={{ maxWidth:"75%", padding:"8px 12px", borderRadius:"4px 0 4px 4px",
        background:"rgba(0,40,20,0.8)", border:"1px solid rgba(0,255,136,0.12)",
        fontFamily:"monospace", fontSize:11, color:"#99ccaa", lineHeight:1.6,
        whiteSpace:"pre-wrap" }}>
        {content}
        <div style={{ fontSize:8, color:"#223", marginTop:4, textAlign:"right", letterSpacing:1 }}>{time}</div>
      </div>
      <span style={{ fontSize:14, color:"#00ff88", filter:"drop-shadow(0 0 4px #00ff88)",
        marginTop:2, flexShrink:0 }}>⬡</span>
    </div>
  );
}

export default function ChatBox({ mode, wsEvents }) {
  const now = () => new Date().toLocaleTimeString("en-US", { hour12:false });
  const [messages, setMessages] = useState([
    { id:"s1", type:"system", content:"BROWSER AUTOMATION STUDIO v3.0 — ONLINE" },
    { id:"s2", type:"bot", content:"System ready. Type a task or /help for commands.", task:null },
  ]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior:"smooth" });
  }, [messages]);

  useEffect(() => {
    if (!wsEvents || wsEvents.type !== "task_update" || !wsEvents.task_id) return;
    setMessages(prev => prev.map(m =>
      m.taskId === wsEvents.task_id
        ? { ...m, task: { ...m.task, status: wsEvents.status,
            progress: wsEvents.data?.progress || m.task?.progress || 0,
            result: wsEvents.data?.result || m.task?.result,
            error: wsEvents.data?.error || m.task?.error }}
        : m
    ));
  }, [wsEvents]);

  const addMsg = (type, content, extra={}) => {
    const id = Date.now().toString();
    setMessages(prev => [...prev, { id, type, content, time:now(), ...extra }]);
    return id;
  };

  const handleSpecial = (cmd) => {
    const c = cmd.toLowerCase().trim();
    if (c === "/help") {
      addMsg("bot", "Commands:\n  /help   — this message\n  /clear  — clear chat\n  /status — system info\n\nOr type any task:\n  Go to google.com and search for...\n  Open YouTube and find...");
      return true;
    }
    if (c === "/clear") {
      setMessages([{ id:"c1", type:"system", content:"CHAT CLEARED" }]);
      return true;
    }
    if (c === "/status") {
      addMsg("bot", `Mode: ${mode} | Ready for tasks`);
      return true;
    }
    return false;
  };

  const handleSend = async () => {
    const text = input.trim();
    if (!text || loading) return;
    setInput("");
    addMsg("user", text);
    if (handleSpecial(text)) return;
    setLoading(true);
    const botId = addMsg("bot", `Submitting → "${text.slice(0,40)}${text.length>40?"...":""}"`,
      { task: { status:"PENDING", progress:0, result:null, error:null } });
    try {
      const task = await submitTask(text, mode === "AUTONOMOUS" ? "auto" : "manual");
      setMessages(prev => prev.map(m =>
        m.id === botId
          ? { ...m, content:`Task queued → ${task.id.slice(0,8)}...`,
              taskId: task.id, task:{ status:"PENDING", progress:0, result:null, error:null }}
          : m
      ));
    } catch (e) {
      setMessages(prev => prev.map(m =>
        m.id === botId ? { ...m, content:`Error: ${e.message}`, task:null } : m
      ));
    } finally {
      setLoading(false);
      inputRef.current?.focus();
    }
  };

  return (
    <div style={{ display:"flex", flexDirection:"column", height:"100%", overflow:"hidden" }}>
      <div style={{ flex:1, overflowY:"auto", padding:"12px 16px",
        display:"flex", flexDirection:"column", gap:8,
        scrollbarWidth:"thin", scrollbarColor:"#1a2030 transparent" }}>
        {messages.map(m => {
          if (m.type === "system") return <SystemMsg key={m.id} content={m.content} />;
          if (m.type === "user") return <UserMsg key={m.id} content={m.content} time={m.time} />;
          return <BotMsg key={m.id} content={m.content} task={m.task} />;
        })}
        {loading && (
          <div style={{ display:"flex", alignItems:"flex-start", gap:8 }}>
            <span style={{ fontSize:14, color:"#00d4ff", marginTop:2 }}>⬡</span>
            <div style={{ padding:"10px 14px", background:"rgba(0,20,40,0.8)",
              border:"1px solid rgba(0,212,255,0.1)", borderRadius:"0 4px 4px 4px",
              display:"flex", gap:4, alignItems:"center" }}>
              {[0,0.2,0.4].map((d,i) => (
                <span key={i} style={{ width:5, height:5, borderRadius:"50%",
                  background:"#00d4ff", display:"inline-block",
                  animation:`typingBounce 1.2s ${d}s infinite` }} />
              ))}
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>
      <div style={{ borderTop:"1px solid rgba(0,212,255,0.08)",
        padding:"10px 16px 8px", background:"rgba(0,4,12,0.6)", flexShrink:0 }}>
        <div style={{ display:"flex", alignItems:"center", gap:8,
          background:"rgba(0,20,40,0.8)", border:"1px solid rgba(0,212,255,0.18)",
          borderRadius:2, padding:"6px 10px" }}>
          <span style={{ color:"#00d4ff", fontFamily:"monospace", fontSize:14 }}>›</span>
          <textarea value={input} ref={inputRef}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => { if (e.key==="Enter" && !e.shiftKey) { e.preventDefault(); handleSend(); }}}
            placeholder="Enter task objective or /help..." disabled={loading}
            rows={1} style={{ flex:1, background:"none", border:"none", outline:"none",
              color:"#aabbcc", fontFamily:"monospace", fontSize:11, resize:"none",
              lineHeight:1.5, padding:0 }} />
          <button onClick={handleSend} disabled={loading || !input.trim()}
            style={{ background:"rgba(0,212,255,0.08)", border:"1px solid rgba(0,212,255,0.25)",
              color:"#00d4ff", fontFamily:"monospace", fontSize:9, letterSpacing:1,
              padding:"4px 10px", borderRadius:2, flexShrink:0,
              opacity: !input.trim() ? 0.4 : 1,
              cursor: !input.trim() ? "not-allowed" : "pointer" }}>
            {loading ? "..." : "SEND ⏎"}
          </button>
        </div>
        <div style={{ fontFamily:"monospace", fontSize:8, color:"#1a2030",
          letterSpacing:1, marginTop:5, paddingLeft:4 }}>
          ENTER to send · SHIFT+ENTER for newline · /help for commands
        </div>
      </div>
    </div>
  );
}
CB_EOF

# ==============================================================
# FILE: frontend/src/App.jsx
# ==============================================================
echo "Writing frontend/src/App.jsx..."
cat > frontend/src/App.jsx << 'APP_EOF'
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
APP_EOF

# ==============================================================
# FILE: guide_m4.md
# ==============================================================
echo "Writing guide_m4.md..."
cat > guide_m4.md << 'GUIDE_EOF'
# Browser Automation Studio — M4 Guide
**React Frontend — Cyberpunk Terminal UI**

## What M4 Adds

| File | What's New |
|---|---|
| `frontend/src/App.jsx` | Login page + dashboard with routing, WebSocket client |
| `frontend/src/api.js` | All fetch calls to FastAPI (auth, tasks, mode, sessions) |
| `frontend/src/components/StatusBar.jsx` | Top bar: mode badge, health, WS status, clock, logout |
| `frontend/src/components/ModeSelector.jsx` | IDLE / MANUAL / AUTONOMOUS toggle buttons |
| `frontend/src/components/ChatBox.jsx` | Chat UI: submit tasks, see results in real time |
| `frontend/src/components/NoVNCViewer.jsx` | noVNC iframe: live Chrome, clickable and typeable |

## Design Aesthetic

Cyberpunk terminal — dark background (#000408), phosphor teal (#00d4ff),
phosphor green (#00ff88), Share Tech Mono font, scanline overlays, hex glyphs,
animated glitch title, border glow pulses, smooth transitions.

## Step 1 — Apply M4

```bash
bash setup_m4.sh
```

## Step 2 — Rebuild (REQUIRED for React)

```bash
docker compose down
docker compose build
docker compose up
```

React must compile into static files that FastAPI serves. This takes 3–5 min.

## Step 3 — Open the App

Visit: **http://localhost:7860**

You should see the cyberpunk login card.

## Step 4 — Verify All DoD Items

### DoD 1: Login page at root URL
```
http://localhost:7860
→ Cyberpunk login card with hexagon logo
```

### DoD 2: Login works
Enter your APP_PASSWORD → click "INITIALIZE SESSION →"
→ Dashboard loads with status bar and mode selector

### DoD 3 & 4: noVNC shows Chrome and is clickable
Right panel (60%) shows Chrome live. Click inside to control Chrome.

### DoD 5: WebSocket live
Status bar shows "WS LIVE" in blue within a few seconds of login.

### DoD 6: Mode switch
Click MANUAL → badge turns orange, API called.
Click AUTO → badge turns blue. Click IDLE → green.

### DoD 7: Chat submits tasks
Type anything → Enter → bot shows task status updating in real time
(PENDING → RUNNING → COMPLETED via WebSocket).

### DoD 8: React served by FastAPI
```bash
curl -s http://localhost:7860/ | grep "Browser Automation"
# Expected: Browser Automation Studio
```

## Chat Commands

- `/help` — show available commands
- `/clear` — clear chat history
- `/status` — show current mode
- Any other text → submitted as automation task

## Troubleshooting

### White screen after login
Open browser DevTools → Console → look for errors.
Most likely React build is missing:
```bash
docker compose exec automation-studio ls /app/frontend/build/
```

### noVNC shows "CONNECTING..." forever
The iframe connects WebSocket back to port 6080.
Make sure docker-compose.yml has: `"6080:6080"` in ports.

### Mode button shows no response
Token expired — logout and login again.

## M4 DoD Checklist

- [ ] http://localhost:7860 shows login page
- [ ] Login works → dashboard loads
- [ ] noVNC right panel shows Chrome
- [ ] Clicking noVNC controls Chrome
- [ ] WS LIVE shows in status bar
- [ ] Mode buttons work
- [ ] Chat submits tasks with real-time status
- [ ] React served by FastAPI at root

## Git Commit

```bash
git add .
git commit -m "[M4] react-frontend: COMPLETE — all DoD items ticked"
```

## What M5 Adds

M5 wires real browser automation: Selenium + Browser Use + Groq AI.
Tasks will actually navigate websites instead of showing "[M3 STUB]".
GUIDE_EOF

# ==============================================================
# Verification
# ==============================================================
echo ""
echo "======================================================"
echo "  Verifying M4 files..."
echo "======================================================"

EXPECTED=(
    "./frontend/src/App.jsx"
    "./frontend/src/api.js"
    "./frontend/src/index.jsx"
    "./frontend/src/components/StatusBar.jsx"
    "./frontend/src/components/ModeSelector.jsx"
    "./frontend/src/components/NoVNCViewer.jsx"
    "./frontend/src/components/ChatBox.jsx"
    "./frontend/public/index.html"
    "./frontend/package.json"
    "./guide_m4.md"
)

ALL_OK=true
for f in "${EXPECTED[@]}"; do
    if [ -f "$f" ]; then echo "  ✓ $f"
    else echo "  ✗ MISSING: $f"; ALL_OK=false; fi
done

echo ""
echo "  Previous modules intact:"
PREV=("./.env" "./Dockerfile" "./docker-compose.yml" "./supervisord.conf"
      "./backend/main.py" "./backend/auth.py" "./backend/models.py" "./backend/tasks.py")
for f in "${PREV[@]}"; do
    if [ -f "$f" ]; then echo "  ✓ $f"
    else echo "  ✗ MISSING: $f"; ALL_OK=false; fi
done

echo ""
if [ "$ALL_OK" = true ]; then
    echo "✅ M4 setup complete."
    echo ""
    echo "⚠  REBUILD REQUIRED (React needs to compile):"
    echo "   docker compose down"
    echo "   docker compose build"
    echo "   docker compose up"
    echo ""
    echo "   Then open: http://localhost:7860"
else
    echo "❌ Some files missing — check above."
fi
echo "======================================================"
