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
