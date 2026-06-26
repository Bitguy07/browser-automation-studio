// ============================================================
// Browser Automation Studio — NoVNCViewer.jsx
// Embeds noVNC iframe — live Chrome view, clickable & typeable
// ============================================================
import { useState, useRef } from "react";

export default function NoVNCViewer({ visible }) {
  const [connected, setConnected] = useState(false);
  const [loading, setLoading] = useState(true);
  const iframeRef = useRef(null);

  // Use the same host/port the React app was loaded from (e.g., localhost:7860 or HF Space URL).
  // We point to the FastAPI mounted /vnc/vnc.html and tell noVNC to use the /websockify websocket proxy path.
  const protocol = window.location.protocol;
  const host = window.location.host;
  const vncUrl = `${protocol}//${host}/vnc/vnc.html?path=websockify&autoconnect=true&resize=scale&reconnect=true&reconnect_delay=2000&show_dot=false&bell=false&toolbar=false`;

  const handleLoad = () => {
    setLoading(false);
    setConnected(true);

    // Inject CSS into the noVNC iframe to hide:
    //   1. The top toolbar (shows "Connected unencrypted" message)
    //   2. The status bar at bottom
    // This works because we are on the same origin (localhost:6080)
    // Note: if browser blocks cross-origin iframe access, this silently fails
    // which is fine — the toolbar=false URL param handles it as backup.
    try {
      const iframe = iframeRef.current;
      if (!iframe || !iframe.contentDocument) return;
      const style = iframe.contentDocument.createElement("style");
      style.textContent = `
        #noVNC_control_bar_anchor,
        #noVNC_control_bar,
        #noVNC_status,
        #noVNC_notification,
        #noVNC_hint_anchor,
        .noVNC_connected #noVNC_control_bar_anchor {
          display: none !important;
          visibility: hidden !important;
          opacity: 0 !important;
          height: 0 !important;
          overflow: hidden !important;
        }
        #noVNC_container {
          top: 0 !important;
        }
      `;
      iframe.contentDocument.head.appendChild(style);
    } catch (_) {
      // Cross-origin block — silently ignore, toolbar=false param handles it
    }
  };

  const handleReconnect = () => {
    setLoading(true);
    setConnected(false);
    if (iframeRef.current) { iframeRef.current.src = vncUrl; }
  };

  if (!visible) return null;

  return (
    <div style={styles.container}>
      {/* Header */}
      <div style={styles.header}>
        <div style={styles.headerLeft}>
          <span style={styles.headerIcon}>⬡</span>
          <span style={styles.headerTitle}>CHROME LIVE VIEW</span>
        </div>
        <div style={styles.headerRight}>
          <div style={styles.connStatus}>
            <span style={{
              ...styles.connDot,
              background: connected ? "#00ff88" : "#ff4466",
              boxShadow: connected ? "0 0 6px #00ff88" : "0 0 6px #ff4466",
              animation: loading ? "pulse 1s infinite" : "none",
            }} />
            <span style={{ ...styles.connLabel, color: connected ? "#00ff88" : "#ff4466" }}>
              {loading ? "CONNECTING..." : connected ? "LIVE" : "DISCONNECTED"}
            </span>
          </div>
          <button style={styles.reconnectBtn} onClick={handleReconnect}
            title="Reconnect noVNC">⟳ RECONNECT</button>
        </div>
      </div>

      {/* Scanline overlay for aesthetics */}
      <div style={styles.scanlines} />

      {/* Loading state */}
      {loading && (
        <div style={styles.loadingOverlay}>
          <div style={styles.loadingContent}>
            <div style={styles.spinner}>
              {[...Array(8)].map((_, i) => (
                <div key={i} style={{
                  ...styles.spinnerDot,
                  transform: `rotate(${i * 45}deg) translateY(-16px)`,
                  animationDelay: `${i * 0.1}s`,
                }} />
              ))}
            </div>
            <div style={styles.loadingText}>INITIALIZING CHROME STREAM</div>
            <div style={styles.loadingSubtext}>Connecting to noVNC on :6080</div>
          </div>
        </div>
      )}

      {/* The actual noVNC iframe */}
      <iframe
        ref={iframeRef}
        src={vncUrl}
        style={{
          ...styles.iframe,
          opacity: loading ? 0 : 1,
          transition: "opacity 0.5s ease",
        }}
        onLoad={handleLoad}
        title="Chrome Live View"
        allow="fullscreen"
      />

      {/* Corner decorations */}
      <div style={{ ...styles.corner, top: 40, left: 0 }} />
      <div style={{ ...styles.corner, top: 40, right: 0, transform: "scaleX(-1)" }} />
      <div style={{ ...styles.corner, bottom: 0, left: 0, transform: "scaleY(-1)" }} />
      <div style={{ ...styles.corner, bottom: 0, right: 0, transform: "scale(-1)" }} />
    </div>
  );
}

const styles = {
  container: {
    flex: 1,
    display: "flex",
    flexDirection: "column",
    background: "#000",
    position: "relative",
    overflow: "hidden",
  },
  header: {
    display: "flex", alignItems: "center", justifyContent: "space-between",
    padding: "8px 12px",
    background: "rgba(0,8,20,0.9)",
    borderBottom: "1px solid rgba(0,212,255,0.15)",
    flexShrink: 0,
    zIndex: 10,
  },
  headerLeft: { display: "flex", alignItems: "center", gap: 6 },
  headerIcon: { color: "#00d4ff", fontSize: 12 },
  headerTitle: { fontFamily: "monospace", fontSize: 10, color: "#00d4ff",
    letterSpacing: 2, fontWeight: 700 },
  headerRight: { display: "flex", alignItems: "center", gap: 12 },
  connStatus: { display: "flex", alignItems: "center", gap: 5 },
  connDot: { width: 7, height: 7, borderRadius: "50%" },
  connLabel: { fontFamily: "monospace", fontSize: 9, letterSpacing: 1 },
  reconnectBtn: {
    background: "none", border: "1px solid #333",
    color: "#666", fontFamily: "monospace", fontSize: 9,
    letterSpacing: 1, padding: "3px 8px", cursor: "pointer",
    borderRadius: 2, transition: "all 0.2s",
  },
  scanlines: {
    position: "absolute", inset: 0, zIndex: 5,
    pointerEvents: "none",
    background: "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0,0,0,0.03) 2px, rgba(0,0,0,0.03) 4px)",
  },
  loadingOverlay: {
    position: "absolute", inset: 0, zIndex: 20,
    display: "flex", alignItems: "center", justifyContent: "center",
    background: "rgba(0,4,12,0.95)",
  },
  loadingContent: { textAlign: "center" },
  spinner: { width: 48, height: 48, position: "relative", margin: "0 auto 20px" },
  spinnerDot: {
    position: "absolute", top: "50%", left: "50%",
    width: 4, height: 4, borderRadius: "50%",
    background: "#00d4ff",
    animation: "fadeInOut 0.8s infinite",
    marginLeft: -2, marginTop: -2,
    transformOrigin: "2px 18px",
  },
  loadingText: { fontFamily: "monospace", fontSize: 11, color: "#00d4ff",
    letterSpacing: 3, marginBottom: 8 },
  loadingSubtext: { fontFamily: "monospace", fontSize: 9, color: "#333", letterSpacing: 1 },
  iframe: {
    flex: 1,
    border: "none",
    width: "100%",
    height: "100%",
    display: "block",
  },
  corner: {
    position: "absolute", width: 12, height: 12, zIndex: 15,
    borderTop: "2px solid rgba(0,212,255,0.4)",
    borderLeft: "2px solid rgba(0,212,255,0.4)",
    pointerEvents: "none",
  },
};