import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import {
  FiShield, FiUser, FiLock, FiEye, FiEyeOff,
  FiAlertTriangle, FiWifi, FiZap, FiMapPin,
  FiRadio, FiNavigation, FiTarget,
} from "react-icons/fi";
import { MdRadar } from "react-icons/md";
import * as api from "../services/api";

function getErrorMessage(raw: string): string {
  const lower = raw.toLowerCase();
  if (lower.includes("401") || lower.includes("invalid") || lower.includes("incorrect") || lower.includes("wrong") || lower.includes("credential")) {
    return "Invalid credentials. Verify your operator ID and access code.";
  }
  if (lower.includes("network") || lower.includes("connect") || lower.includes("timeout") || lower.includes("fetch")) {
    return "Cannot reach command server. Check your network connection.";
  }
  if (lower.includes("locked") || lower.includes("disabled") || lower.includes("suspended")) {
    return "Account is locked or suspended. Contact your system administrator.";
  }
  if (lower.includes("403") || lower.includes("forbidden")) {
    return "Access denied. You are not authorized to access this system.";
  }
  return raw || "Authentication failed. Please try again.";
}

const STATUS_ITEMS = [
  { icon: <FiWifi size={12} />, label: "SECURE TLS", color: "#22c55e" },
  { icon: <FiRadio size={12} />, label: "COMMAND LINK", color: "#22c55e" },
  { icon: <FiNavigation size={12} />, label: "GPS ENABLED", color: "#f59e0b" },
];

const GRID_LINES = Array.from({ length: 12 });

export default function Login() {
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [idFocused, setIdFocused] = useState(false);
  const [pwFocused, setPwFocused] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const { data } = await api.login(identifier, password);
      localStorage.setItem("access_token", data.access_token);
      if (data.refresh_token) localStorage.setItem("refresh_token", data.refresh_token);
      navigate("/");
    } catch (err: unknown) {
      const raw =
        (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
        "Authentication failed.";
      setError(getErrorMessage(String(raw)));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="w-screen h-screen flex overflow-hidden" style={{ fontFamily: "'Poppins', sans-serif", background: "#050C1A" }}>

      {/* ── LEFT PANEL ───────────────────────────────────────────── */}
      <motion.div
        className="hidden lg:flex flex-col relative overflow-hidden"
        style={{ width: "55%", background: "linear-gradient(135deg, #060E1C 0%, #0A1628 50%, #0D1F38 100%)" }}
        initial={{ opacity: 0, x: -30 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.7, ease: "easeOut" }}
      >
        {/* Tactical grid */}
        <svg className="absolute inset-0 w-full h-full" style={{ opacity: 0.07 }}>
          {GRID_LINES.map((_, i) => (
            <React.Fragment key={i}>
              <line x1={`${(i / 12) * 100}%`} y1="0" x2={`${(i / 12) * 100}%`} y2="100%" stroke="#3b82f6" strokeWidth="0.5" />
              <line x1="0" y1={`${(i / 12) * 100}%`} x2="100%" y2={`${(i / 12) * 100}%`} stroke="#3b82f6" strokeWidth="0.5" />
            </React.Fragment>
          ))}
        </svg>

        {/* Glow orbs */}
        <div className="absolute" style={{ width: 500, height: 500, borderRadius: "50%", background: "radial-gradient(circle, rgba(59,130,246,0.12) 0%, transparent 70%)", top: "10%", left: "20%", pointerEvents: "none" }} />
        <div className="absolute" style={{ width: 300, height: 300, borderRadius: "50%", background: "radial-gradient(circle, rgba(6,182,212,0.08) 0%, transparent 70%)", bottom: "15%", right: "10%", pointerEvents: "none" }} />

        {/* Animated radar ring */}
        <div className="absolute" style={{ top: "50%", left: "50%", transform: "translate(-50%, -50%)", pointerEvents: "none" }}>
          {[1, 1.6, 2.2].map((scale, i) => (
            <motion.div
              key={i}
              className="absolute rounded-full border"
              style={{
                width: 160,
                height: 160,
                top: "50%",
                left: "50%",
                transform: `translate(-50%, -50%) scale(${scale})`,
                borderColor: `rgba(59,130,246,${0.15 - i * 0.04})`,
              }}
              animate={{ opacity: [0.4, 0.1, 0.4] }}
              transition={{ duration: 3, delay: i * 0.8, repeat: Infinity, ease: "easeInOut" }}
            />
          ))}
          <motion.div
            className="flex items-center justify-center rounded-full"
            style={{ width: 160, height: 160, background: "rgba(59,130,246,0.06)", border: "1px solid rgba(59,130,246,0.2)" }}
            animate={{ rotate: 360 }}
            transition={{ duration: 12, repeat: Infinity, ease: "linear" }}
          >
            <motion.div
              style={{
                width: 2, height: 80, background: "linear-gradient(to top, rgba(59,130,246,0.8), transparent)",
                transformOrigin: "bottom center", position: "absolute", bottom: "50%", left: "50%", marginLeft: -1,
              }}
            />
          </motion.div>
          <div className="absolute" style={{ top: "50%", left: "50%", transform: "translate(-50%, -50%)" }}>
            <MdRadar size={36} color="rgba(59,130,246,0.6)" />
          </div>
        </div>

        {/* Top branding */}
        <div className="relative z-10 p-10 flex-1 flex flex-col">
          <motion.div
            className="flex items-center gap-3 mb-auto"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3, duration: 0.5 }}
          >
            <div className="w-9 h-9 rounded-xl flex items-center justify-center" style={{ background: "rgba(59,130,246,0.15)", border: "1px solid rgba(59,130,246,0.3)" }}>
              <FiShield size={18} color="#3b82f6" />
            </div>
            <div>
              <div className="text-white font-bold text-sm tracking-widest">DRD TRACKING</div>
              <div className="text-[9px] tracking-widest" style={{ color: "rgba(255,255,255,0.3)" }}>FIELD COORDINATION</div>
            </div>
          </motion.div>

          {/* Center text */}
          <motion.div
            className="flex flex-col gap-4 mb-auto"
            style={{ marginTop: "auto", paddingBottom: "10%" }}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.5, duration: 0.6 }}
          >
            <div className="text-3xl font-bold text-white leading-tight">
              Tactical Field<br />
              <span style={{ color: "#3b82f6" }}>Coordination</span><br />
              System
            </div>
            <div className="text-sm leading-relaxed" style={{ color: "rgba(255,255,255,0.4)", maxWidth: 280 }}>
              Real-time unit tracking, route planning, and secure team communications for field operations.
            </div>
          </motion.div>

          {/* Status indicators */}
          <motion.div
            className="flex flex-col gap-2"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.8, duration: 0.5 }}
          >
            {STATUS_ITEMS.map((s, i) => (
              <motion.div
                key={i}
                className="flex items-center gap-2"
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.9 + i * 0.1 }}
              >
                <span style={{ color: s.color }}>{s.icon}</span>
                <span className="text-[10px] font-semibold tracking-widest" style={{ color: "rgba(255,255,255,0.3)" }}>{s.label}</span>
                <motion.span
                  className="w-1.5 h-1.5 rounded-full ml-1"
                  style={{ backgroundColor: s.color }}
                  animate={{ opacity: [1, 0.3, 1] }}
                  transition={{ duration: 2, delay: i * 0.5, repeat: Infinity }}
                />
              </motion.div>
            ))}
          </motion.div>

          {/* Map pins decoration */}
          {[
            { x: "15%", y: "35%", delay: 1.0 },
            { x: "72%", y: "28%", delay: 1.2 },
            { x: "45%", y: "65%", delay: 1.4 },
          ].map((pin, i) => (
            <motion.div
              key={i}
              className="absolute"
              style={{ left: pin.x, top: pin.y }}
              initial={{ opacity: 0, scale: 0 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: pin.delay, type: "spring", stiffness: 200 }}
            >
              <FiMapPin size={14} color="rgba(59,130,246,0.5)" />
              <motion.div
                className="absolute rounded-full"
                style={{ width: 20, height: 20, top: -3, left: -3, border: "1px solid rgba(59,130,246,0.3)" }}
                animate={{ scale: [1, 1.8], opacity: [0.6, 0] }}
                transition={{ duration: 2, delay: pin.delay, repeat: Infinity }}
              />
            </motion.div>
          ))}
        </div>
      </motion.div>

      {/* ── RIGHT PANEL ───────────────────────────────────────────── */}
      <motion.div
        className="flex-1 flex flex-col items-center justify-center p-6 relative"
        style={{ background: "#060E1C" }}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.5 }}
      >
        {/* Top accent line */}
        <div className="absolute top-0 left-0 right-0 h-px" style={{ background: "linear-gradient(to right, transparent, rgba(59,130,246,0.4), transparent)" }} />

        <motion.div
          className="w-full"
          style={{ maxWidth: 380 }}
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.6, ease: "easeOut" }}
        >
          {/* Mobile logo */}
          <div className="flex flex-col items-center mb-8 lg:hidden">
            <div className="w-14 h-14 rounded-2xl flex items-center justify-center mb-3" style={{ background: "rgba(59,130,246,0.12)", border: "1px solid rgba(59,130,246,0.3)" }}>
              <FiShield size={26} color="#3b82f6" />
            </div>
            <div className="text-white font-bold text-lg tracking-widest">DRD TRACKING</div>
            <div className="text-[9px] tracking-widest mt-0.5" style={{ color: "rgba(255,255,255,0.3)" }}>FIELD COORDINATION SYSTEM</div>
          </div>

          {/* Card */}
          <div className="rounded-2xl p-7" style={{ background: "rgba(15,28,46,0.95)", border: "1px solid rgba(255,255,255,0.06)", boxShadow: "0 25px 60px rgba(0,0,0,0.5)" }}>
            {/* Card header */}
            <div className="flex items-center gap-2 mb-6">
              <FiTarget size={13} color="#3b82f6" />
              <span className="text-xs font-bold tracking-widest" style={{ color: "rgba(255,255,255,0.4)" }}>AUTHENTICATE</span>
            </div>

            {/* Error banner */}
            <AnimatePresence>
              {error && (
                <motion.div
                  className="mb-5 flex items-start gap-2.5 rounded-xl px-3.5 py-3"
                  style={{ background: "rgba(239,68,68,0.07)", border: "1px solid rgba(239,68,68,0.2)" }}
                  initial={{ opacity: 0, y: -8, height: 0 }}
                  animate={{ opacity: 1, y: 0, height: "auto" }}
                  exit={{ opacity: 0, y: -8, height: 0 }}
                  transition={{ duration: 0.25 }}
                >
                  <FiAlertTriangle size={14} color="#ef4444" className="mt-0.5 shrink-0" />
                  <span className="text-xs leading-relaxed" style={{ color: "#f87171" }}>{error}</span>
                </motion.div>
              )}
            </AnimatePresence>

            <form onSubmit={handleSubmit} className="space-y-5">
              {/* Identifier field */}
              <div>
                <label className="block mb-2 text-[9px] font-bold tracking-widest" style={{ color: idFocused ? "#3b82f6" : "rgba(255,255,255,0.3)" }}>
                  OPERATOR ID / USERNAME
                </label>
                <motion.div
                  className="relative rounded-xl overflow-hidden"
                  animate={{ boxShadow: idFocused ? "0 0 0 1.5px rgba(59,130,246,0.5)" : "0 0 0 1px rgba(255,255,255,0.07)" }}
                  transition={{ duration: 0.2 }}
                >
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none">
                    <FiUser size={14} color={idFocused ? "#3b82f6" : "rgba(255,255,255,0.2)"} />
                  </span>
                  <input
                    type="text"
                    value={identifier}
                    onChange={e => setIdentifier(e.target.value)}
                    onFocus={() => setIdFocused(true)}
                    onBlur={() => setIdFocused(false)}
                    required
                    autoComplete="username"
                    placeholder="commander.alpha or user@drd.mil"
                    className="w-full pl-10 pr-4 py-3 text-xs text-white focus:outline-none transition-colors"
                    style={{ background: idFocused ? "rgba(59,130,246,0.05)" : "rgba(10,22,40,0.9)", color: "white", fontSize: 12 }}
                  />
                </motion.div>
              </div>

              {/* Password field */}
              <div>
                <label className="block mb-2 text-[9px] font-bold tracking-widest" style={{ color: pwFocused ? "#3b82f6" : "rgba(255,255,255,0.3)" }}>
                  ACCESS CODE
                </label>
                <motion.div
                  className="relative rounded-xl overflow-hidden"
                  animate={{ boxShadow: pwFocused ? "0 0 0 1.5px rgba(59,130,246,0.5)" : "0 0 0 1px rgba(255,255,255,0.07)" }}
                  transition={{ duration: 0.2 }}
                >
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none">
                    <FiLock size={14} color={pwFocused ? "#3b82f6" : "rgba(255,255,255,0.2)"} />
                  </span>
                  <input
                    type={showPass ? "text" : "password"}
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    onFocus={() => setPwFocused(true)}
                    onBlur={() => setPwFocused(false)}
                    required
                    autoComplete="current-password"
                    placeholder="••••••••••"
                    className="w-full pl-10 pr-11 py-3 text-xs text-white focus:outline-none"
                    style={{ background: pwFocused ? "rgba(59,130,246,0.05)" : "rgba(10,22,40,0.9)", color: "white", fontSize: 12 }}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPass(v => !v)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 transition-colors"
                    style={{ color: "rgba(255,255,255,0.3)", background: "none", border: "none", cursor: "pointer" }}
                    tabIndex={-1}
                  >
                    {showPass ? <FiEyeOff size={14} /> : <FiEye size={14} />}
                  </button>
                </motion.div>
              </div>

              {/* Submit */}
              <motion.button
                type="submit"
                disabled={loading || !identifier || !password}
                className="w-full py-3 rounded-xl text-white text-xs font-bold tracking-widest flex items-center justify-center gap-2 relative overflow-hidden"
                style={{ background: loading || !identifier || !password ? "rgba(59,130,246,0.4)" : "#2563eb", border: "none", cursor: loading || !identifier || !password ? "not-allowed" : "pointer" }}
                whileTap={{ scale: loading ? 1 : 0.98 }}
                transition={{ duration: 0.1 }}
              >
                {/* Shimmer on hover */}
                <motion.div
                  className="absolute inset-0 pointer-events-none"
                  style={{ background: "linear-gradient(90deg, transparent, rgba(255,255,255,0.08), transparent)", x: "-100%" }}
                  whileHover={{ x: "100%" }}
                  transition={{ duration: 0.5 }}
                />
                {loading ? (
                  <>
                    <motion.span
                      className="w-3.5 h-3.5 rounded-full border-2 shrink-0"
                      style={{ borderColor: "rgba(255,255,255,0.3)", borderTopColor: "white" }}
                      animate={{ rotate: 360 }}
                      transition={{ duration: 0.8, repeat: Infinity, ease: "linear" }}
                    />
                    AUTHENTICATING...
                  </>
                ) : (
                  <>
                    <FiZap size={13} />
                    AUTHENTICATE
                  </>
                )}
              </motion.button>
            </form>

            {/* Footer */}
            <div className="mt-6 pt-5 flex items-center justify-center gap-2" style={{ borderTop: "1px solid rgba(255,255,255,0.05)" }}>
              <motion.span
                className="w-1.5 h-1.5 rounded-full"
                style={{ background: "#22c55e" }}
                animate={{ opacity: [1, 0.3, 1] }}
                transition={{ duration: 2, repeat: Infinity }}
              />
              <span className="text-[9px] tracking-widest" style={{ color: "rgba(255,255,255,0.2)" }}>ENCRYPTED · AUTHORIZED PERSONNEL ONLY</span>
            </div>
          </div>
        </motion.div>
      </motion.div>
    </div>
  );
}
