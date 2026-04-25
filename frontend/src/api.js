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
