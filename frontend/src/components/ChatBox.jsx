// ============================================================
// Browser Automation Studio — frontend/src/components/ChatBox.jsx
// M5 UI: per ui_updates.md
//   - User message stays as separate bubble (right side)
//   - Queued bubble updates in-place with ✓ DONE / ✗ FAILED suffix
//   - Live step bubble updates in-place; disappears on completion
//   - Markdown rendering in results (bold, lists, code, etc.)
//   - Groq rate-limit bar (30 req/min free tier)
//   - Rate-limit freeze: disables input + countdown timer (persisted)
//   - /reset command
//   - /help includes /reset
//   - /status shows Groq usage
// ============================================================

import { useState, useRef, useEffect, useCallback } from "react";
import { submitTask } from "../api";

const STATUS_COLORS = {
  PENDING: "#ffaa00", RUNNING: "#00d4ff",
  COMPLETED: "#00ff88", FAILED: "#ff4466", CANCELLED: "#446",
};
const STATUS_ICONS = {
  PENDING: "⏳", RUNNING: "⚡", COMPLETED: "✓", FAILED: "✗", CANCELLED: "○",
};

// ── Groq rate-limit state (persisted to sessionStorage) ───────
const RL_KEY     = "bas_rl_reqs";
const RL_FREEZE  = "bas_rl_freeze_until";
const RL_MAX     = 30;
const RL_WINDOW  = 60_000;   // 1 minute

function getRLReqs() {
  try { return JSON.parse(sessionStorage.getItem(RL_KEY) || "[]"); } catch { return []; }
}
function saveRLReqs(arr) {
  sessionStorage.setItem(RL_KEY, JSON.stringify(arr));
}
function getFreezeUntil() {
  const v = sessionStorage.getItem(RL_FREEZE);
  return v ? parseInt(v, 10) : 0;
}
function setFreezeUntil(ts) {
  sessionStorage.setItem(RL_FREEZE, String(ts));
}

function trackRequest() {
  const now = Date.now();
  const arr  = getRLReqs().filter(t => now - t < RL_WINDOW);
  arr.push(now);
  saveRLReqs(arr);
  const count = arr.length;
  if (count >= RL_MAX) {
    const oldest = arr[0];
    const resetAt = oldest + RL_WINDOW;
    setFreezeUntil(resetAt);
  }
  return count;
}

function getRLCount() {
  const now = Date.now();
  return getRLReqs().filter(t => now - t < RL_WINDOW).length;
}


// ── Simple markdown → HTML renderer ──────────────────────────
function renderMarkdown(text) {
  if (!text) return "";
  let html = text
    // Code blocks (```...```)
    .replace(/```([^`]*?)```/gs, (_, code) =>
      `<pre style="background:rgba(0,0,0,0.4);padding:8px;border-radius:2px;overflow-x:auto;font-size:10px;margin:4px 0;border:1px solid rgba(0,212,255,0.1)">${escHtml(code.trim())}</pre>`)
    // Inline code
    .replace(/`([^`]+)`/g, (_, c) =>
      `<code style="background:rgba(0,0,0,0.4);padding:1px 4px;border-radius:2px;font-size:10px;color:#00d4ff">${escHtml(c)}</code>`)
    // Bold
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    // Italic
    .replace(/\*(.+?)\*/g, "<em>$1</em>")
    // H3, H2, H1
    .replace(/^### (.+)$/gm, '<span style="color:#fff;font-weight:700;font-size:11px">$1</span>')
    .replace(/^## (.+)$/gm,  '<span style="color:#fff;font-weight:700;font-size:12px">$1</span>')
    .replace(/^# (.+)$/gm,   '<span style="color:#fff;font-weight:700;font-size:13px">$1</span>')
    // Numbered list
    .replace(/^\d+\. (.+)$/gm,
      '<div style="display:flex;gap:6px;margin:2px 0"><span style="color:#00d4ff;flex-shrink:0">›</span><span>$1</span></div>')
    // Bullet list
    .replace(/^[-*] (.+)$/gm,
      '<div style="display:flex;gap:6px;margin:2px 0"><span style="color:#00d4ff;flex-shrink:0">•</span><span>$1</span></div>')
    // Links
    .replace(/\[(.+?)\]\((.+?)\)/g,
      '<a href="$2" target="_blank" style="color:#00d4ff;text-decoration:underline">$1</a>')
    // Double newline → paragraph break
    .replace(/\n\n/g, '<br/><br/>')
    // Single newline
    .replace(/\n/g, '<br/>');
  return html;
}

function escHtml(t) {
  return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function MarkdownContent({ text }) {
  return (
    <div
      dangerouslySetInnerHTML={{ __html: renderMarkdown(text) }}
      style={{ whiteSpace: "normal", wordBreak: "break-word" }}
    />
  );
}


// ── Message components ────────────────────────────────────────
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

function BotMsg({ content, task, isStep }) {
  const isMarkdown = task?.status === "COMPLETED" && task?.result;
  return (
    <div style={{ display:"flex", alignItems:"flex-start", gap:8 }}>
      <span style={{ fontSize:14, color: isStep ? "#ffaa00" : "#00d4ff",
        filter:`drop-shadow(0 0 4px ${isStep ? "#ffaa00" : "#00d4ff"})`,
        marginTop:2, flexShrink:0 }}>⬡</span>
      <div style={{ maxWidth:"75%", padding:"8px 12px", borderRadius:"0 4px 4px 4px",
        background:"rgba(0,20,40,0.8)",
        border:`1px solid ${isStep ? "rgba(255,170,0,0.18)" : "rgba(0,212,255,0.12)"}`,
        fontFamily:"monospace", fontSize:11, color:"#99aacc", lineHeight:1.6 }}>
        {isMarkdown
          ? <MarkdownContent text={task.result} />
          : <div style={{ whiteSpace:"pre-wrap" }}>{content}</div>
        }
        {task && !isStep && (
          <div style={{ marginTop:8, padding:"6px 8px", background:"rgba(0,0,0,0.3)",
            borderRadius:2, fontSize:10, display:"flex", flexDirection:"column", gap:4 }}>
            <span style={{ color: STATUS_COLORS[task.status] }}>
              {STATUS_ICONS[task.status]} {task.status}
              {task.status === "COMPLETED" && " ✓ DONE"}
              {task.status === "FAILED" && " ✗ FAILED"}
            </span>
            {task.status === "RUNNING" && task.progress > 0 && (
              <div style={{ height:2, background:"#0a1520", borderRadius:1 }}>
                <div style={{ height:"100%", width:`${task.progress}%`,
                  background:"#00d4ff", boxShadow:"0 0 4px #00d4ff",
                  transition:"width 0.3s ease", borderRadius:1 }} />
              </div>
            )}
            {task.error && (
              <div style={{ color:"#ff4466", fontSize:9 }}>{task.error}</div>
            )}
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
        <div style={{ fontSize:8, color:"#223", marginTop:4, textAlign:"right",
          letterSpacing:1 }}>{time}</div>
      </div>
      <span style={{ fontSize:14, color:"#00ff88",
        filter:"drop-shadow(0 0 4px #00ff88)",
        marginTop:2, flexShrink:0 }}>⬡</span>
    </div>
  );
}


// ── Rate limit bar ────────────────────────────────────────────
function RateLimitBar({ count, frozen, secondsLeft }) {
  const pct   = Math.min((count / RL_MAX) * 100, 100);
  const color = pct >= 85 ? "#ff4466" : pct >= 50 ? "#ffaa00" : "#00d4ff";
  return (
    <div style={{ padding:"4px 16px 2px", borderTop:"1px solid rgba(0,212,255,0.05)" }}>
      <div style={{ display:"flex", alignItems:"center", gap:8, marginBottom:3 }}>
        <span style={{ fontFamily:"monospace", fontSize:8, color:"#334", letterSpacing:1,
          whiteSpace:"nowrap" }}>GROQ API</span>
        <div style={{ flex:1, height:2, background:"#0a1520", borderRadius:1 }}>
          <div style={{ height:"100%", width:`${pct}%`, background:color,
            boxShadow:`0 0 4px ${color}`, transition:"width 0.5s ease",
            borderRadius:1 }} />
        </div>
        <span style={{ fontFamily:"monospace", fontSize:8, color,
          whiteSpace:"nowrap", minWidth:50, textAlign:"right" }}>
          {frozen
            ? `FROZEN ${secondsLeft}s`
            : `${count}/${RL_MAX} req/min`}
        </span>
      </div>
    </div>
  );
}


// ── Main ChatBox ──────────────────────────────────────────────
export default function ChatBox({ mode, wsEvents }) {
  const now = () => new Date().toLocaleTimeString("en-US", { hour12:false });

  const [messages, setMessages] = useState([
    { id:"s1", type:"system", content:"BROWSER AUTOMATION STUDIO v5.0 — M5 ONLINE" },
    { id:"s2", type:"bot", content:"System ready. Type a task or /help for commands.", task:null },
  ]);
  const [input, setInput]   = useState("");
  const [loading, setLoading] = useState(false);

  // Rate-limit state
  const [rlCount, setRlCount]         = useState(getRLCount);
  const [frozen, setFrozen]           = useState(() => Date.now() < getFreezeUntil());
  const [secondsLeft, setSecondsLeft] = useState(0);

  const bottomRef = useRef(null);
  const inputRef  = useRef(null);

  // Scroll to bottom on new messages
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior:"smooth" });
  }, [messages]);

  // Tick every second — update RL count + freeze countdown
  useEffect(() => {
    const tick = () => {
      const fu = getFreezeUntil();
      const now = Date.now();
      if (fu > now) {
        setFrozen(true);
        setSecondsLeft(Math.ceil((fu - now) / 1000));
      } else {
        setFrozen(false);
        setSecondsLeft(0);
        setFreezeUntil(0);
      }
      setRlCount(getRLCount());
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  // WebSocket events — update existing bubbles in-place
  useEffect(() => {
    if (!wsEvents || !wsEvents.task_id) return;

    if (wsEvents.type === "task_update") {
      const isStep   = wsEvents.data?.step_bubble === true;
      const status   = wsEvents.status;
      const message  = wsEvents.message || "";
      const result   = wsEvents.data?.result;
      const error    = wsEvents.data?.error;
      const progress = wsEvents.data?.progress ?? 0;

      setMessages(prev => {
        // Find the queued bubble
        const queuedIdx = prev.findIndex(m => m.taskId === wsEvents.task_id && !m.isStep);
        // Find the step bubble (if any)
        const stepIdx   = prev.findIndex(m => m.taskId === wsEvents.task_id && m.isStep);

        let next = [...prev];

        if (isStep) {
          // Update step bubble in-place, or create one
          const stepMsg = {
            id:     `step-${wsEvents.task_id}`,
            type:   "bot",
            isStep: true,
            taskId: wsEvents.task_id,
            content: message,
            task:    { status: "RUNNING", progress, time: now() },
          };
          if (stepIdx !== -1) {
            next[stepIdx] = stepMsg;
          } else {
            // Insert right after queued bubble
            if (queuedIdx !== -1) {
              next.splice(queuedIdx + 1, 0, stepMsg);
            } else {
              next.push(stepMsg);
            }
          }
          return next;
        }

        // Not a step bubble — update queued bubble
        if (queuedIdx !== -1) {
          next[queuedIdx] = {
            ...next[queuedIdx],
            task: {
              ...next[queuedIdx].task,
              status:   status,
              progress: progress,
              result:   result || next[queuedIdx].task?.result,
              error:    error  || next[queuedIdx].task?.error,
              time:     now(),
            },
          };
        }

        // Remove step bubble once task is done
        if (status === "COMPLETED" || status === "FAILED" || status === "CANCELLED") {
          next = next.filter(m => !(m.isStep && m.taskId === wsEvents.task_id));
        }

        return next;
      });
    }

    if (wsEvents.type === "browser_reset") {
      addMsg("bot", wsEvents.message || "Browser reset complete.");
    }
  }, [wsEvents]);

  const addMsg = (type, content, extra={}) => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    setMessages(prev => [...prev, { id, type, content, time:now(), ...extra }]);
    return id;
  };

  const handleSpecial = async (cmd) => {
    const c = cmd.toLowerCase().trim();

    if (c === "/help") {
      addMsg("bot",
        "Commands:\n" +
        "  /help    — this message\n" +
        "  /clear   — clear chat\n" +
        "  /status  — system info + API usage\n" +
        "  /reset   — reset Chrome (close stale tabs)\n\n" +
        "Or type any task:\n" +
        "  Go to google.com and search for...\n" +
        "  Open YouTube and find..."
      );
      return true;
    }
    if (c === "/clear") {
      setMessages([{ id:"c1", type:"system", content:"CHAT CLEARED" }]);
      return true;
    }
    if (c === "/status") {
      addMsg("bot",
        `Mode: ${mode} | Ready for tasks\nGroq API: ${rlCount}/${RL_MAX} req/min used`
      );
      return true;
    }
    if (c === "/reset") {
      addMsg("bot", "Resetting browser — closing stale tabs…");
      try {
        const token = localStorage.getItem("bas_token");
        const res   = await fetch("/api/browser/reset", {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
        });
        const data  = await res.json();
        addMsg("bot", data.message || "Browser reset complete.");
      } catch (e) {
        addMsg("bot", `Reset error: ${e.message}`);
      }
      return true;
    }
    return false;
  };

  const handleSend = async () => {
    const text = input.trim();
    if (!text || loading || frozen) return;
    setInput("");

    // Add user bubble (stays permanently on right side)
    addMsg("user", text);

    if (await handleSpecial(text)) return;

    setLoading(true);

    // Add queued bot bubble
    const botId = addMsg("bot",
      `Task queued → "${text.slice(0,40)}${text.length > 40 ? "…" : ""}"`,
      { task: { status:"PENDING", progress:0, result:null, error:null, time:now() } }
    );

    // Track against rate limit
    const newCount = trackRequest();
    setRlCount(newCount);

    try {
      const task = await submitTask(text, mode === "AUTONOMOUS" ? "auto" : "manual");
      setMessages(prev => prev.map(m =>
        m.id === botId
          ? { ...m,
              content: `Task queued → ${task.id.slice(0,8)}…`,
              taskId:  task.id,
              task: { status:"PENDING", progress:0, result:null, error:null, time:now() } }
          : m
      ));
    } catch (e) {
      setMessages(prev => prev.map(m =>
        m.id === botId
          ? { ...m, content:`Error: ${e.message}`, task:null }
          : m
      ));
    } finally {
      setLoading(false);
      inputRef.current?.focus();
    }
  };

  const inputDisabled = loading || frozen;

  return (
    <div style={{ display:"flex", flexDirection:"column", height:"100%", overflow:"hidden" }}>
      {/* Message list */}
      <div style={{ flex:1, overflowY:"auto", padding:"12px 16px",
        display:"flex", flexDirection:"column", gap:8,
        scrollbarWidth:"thin", scrollbarColor:"#1a2030 transparent" }}>
        {messages.map(m => {
          if (m.type === "system") return <SystemMsg key={m.id} content={m.content} />;
          if (m.type === "user")   return <UserMsg   key={m.id} content={m.content} time={m.time} />;
          return <BotMsg key={m.id} content={m.content} task={m.task} isStep={m.isStep} />;
        })}
        {loading && (
          <div style={{ display:"flex", alignItems:"flex-start", gap:8 }}>
            <span style={{ fontSize:14, color:"#00d4ff", marginTop:2 }}>⬡</span>
            <div style={{ padding:"10px 14px", background:"rgba(0,20,40,0.8)",
              border:"1px solid rgba(0,212,255,0.1)", borderRadius:"0 4px 4px 4px",
              display:"flex", gap:4, alignItems:"center" }}>
              {[0, 0.2, 0.4].map((d, i) => (
                <span key={i} style={{ width:5, height:5, borderRadius:"50%",
                  background:"#00d4ff", display:"inline-block",
                  animation:`typingBounce 1.2s ${d}s infinite` }} />
              ))}
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      {/* Rate-limit bar */}
      <RateLimitBar count={rlCount} frozen={frozen} secondsLeft={secondsLeft} />

      {/* Freeze overlay message */}
      {frozen && (
        <div style={{ margin:"0 16px 6px", padding:"8px 12px",
          background:"rgba(255,68,102,0.08)", border:"1px solid rgba(255,68,102,0.2)",
          borderRadius:2, fontFamily:"monospace", fontSize:10, color:"#ff4466",
          letterSpacing:1, textAlign:"center" }}>
          ⚠ GROQ RATE LIMIT — input blocked for {secondsLeft}s
        </div>
      )}

      {/* Input area */}
      <div style={{ borderTop:"1px solid rgba(0,212,255,0.08)",
        padding:"10px 16px 8px", background:"rgba(0,4,12,0.6)", flexShrink:0 }}>
        <div style={{ display:"flex", alignItems:"center", gap:8,
          background:"rgba(0,20,40,0.8)",
          border:`1px solid ${inputDisabled ? "rgba(255,68,102,0.18)" : "rgba(0,212,255,0.18)"}`,
          borderRadius:2, padding:"6px 10px",
          opacity: inputDisabled ? 0.6 : 1 }}>
          <span style={{ color: inputDisabled ? "#ff4466" : "#00d4ff",
            fontFamily:"monospace", fontSize:14 }}>›</span>
          <textarea
            value={input}
            ref={inputRef}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => {
              if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); handleSend(); }
            }}
            placeholder={frozen ? "Rate limit active — please wait…" : "Enter task objective or /help…"}
            disabled={inputDisabled}
            rows={1}
            style={{ flex:1, background:"none", border:"none", outline:"none",
              color:"#aabbcc", fontFamily:"monospace", fontSize:11, resize:"none",
              lineHeight:1.5, padding:0 }}
          />
          <button
            onClick={handleSend}
            disabled={inputDisabled || !input.trim()}
            style={{ background:"rgba(0,212,255,0.08)",
              border:"1px solid rgba(0,212,255,0.25)",
              color:"#00d4ff", fontFamily:"monospace", fontSize:9,
              letterSpacing:1, padding:"4px 10px", borderRadius:2, flexShrink:0,
              opacity: (inputDisabled || !input.trim()) ? 0.4 : 1,
              cursor: (inputDisabled || !input.trim()) ? "not-allowed" : "pointer" }}>
            {loading ? "…" : "SEND ⏎"}
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
