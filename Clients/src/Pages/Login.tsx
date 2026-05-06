import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import {
  FiShield, FiUser, FiLock, FiEye, FiEyeOff,
  FiAlertTriangle, FiZap, FiRadio, FiWifi, FiNavigation,
} from "react-icons/fi";
import * as api from "../services/api";

const GPS_IMAGE = "https://livetracking.pk/wp-content/uploads/2026/03/real-time-gps-location-tracking-pakistan.jpeg";

function getErrorMessage(raw: string): string {
  const lower = raw.toLowerCase();
  if (lower.includes("401") || lower.includes("invalid") || lower.includes("incorrect") || lower.includes("credential")) {
    return "Invalid credentials. Verify your operator ID and access code.";
  }
  if (lower.includes("network") || lower.includes("connect") || lower.includes("timeout") || lower.includes("fetch")) {
    return "Cannot reach command server. Check your network connection.";
  }
  if (lower.includes("locked") || lower.includes("disabled") || lower.includes("suspended")) {
    return "Account locked. Contact your system administrator.";
  }
  if (lower.includes("403") || lower.includes("forbidden")) {
    return "Access denied. You are not authorized for this system.";
  }
  return raw || "Authentication failed. Please try again.";
}

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

      {/* ── LEFT PANEL — GPS tracking image ───────────────────────── */}
      <motion.div
        className="hidden lg:flex flex-col relative overflow-hidden"
        style={{ width: "52%" }}
        initial={{ opacity: 0, x: -20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.7, ease: "easeOut" }}
      >
        {/* Background image */}
        <img
          src={GPS_IMAGE}
          alt="GPS tracking"
          className="absolute inset-0 w-full h-full object-cover"
          style={{ filter: "brightness(0.55) saturate(1.1)" }}
        />

        {/* Overlay gradient */}
        <div className="absolute inset-0" style={{ background: "linear-gradient(135deg, rgba(5,12,26,0.75) 0%, rgba(10,22,40,0.5) 50%, rgba(5,12,26,0.8) 100%)" }} />

        {/* Scan line effect */}
        <motion.div
          className="absolute left-0 right-0 h-px"
          style={{ background: "linear-gradient(90deg, transparent, rgba(59,130,246,0.6), transparent)" }}
          animate={{ top: ["0%", "100%"] }}
          transition={{ duration: 6, repeat: Infinity, ease: "linear" }}
        />

        {/* Content overlay */}
        <div className="relative z-10 flex flex-col h-full p-10">
          {/* Top branding */}
          <motion.div
            className="flex items-center gap-3"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
          >
            <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ background: "rgba(59,130,246,0.2)", border: "1px solid rgba(59,130,246,0.4)" }}>
              <FiShield size={20} color="#3b82f6" />
            </div>
            <div>
              <div className="text-white font-bold text-base tracking-widest">DRD TRACKING</div>
              <div className="text-[9px] tracking-widest" style={{ color: "rgba(255,255,255,0.4)" }}>FIELD COORDINATION</div>
            </div>
          </motion.div>

          {/* Center tagline */}
          <motion.div
            className="flex-1 flex flex-col justify-center"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.5, duration: 0.7 }}
          >
            <div className="text-4xl font-bold text-white leading-tight mb-4">
              Real-Time<br />
              <span style={{ color: "#3b82f6" }}>Field Ops</span><br />
              Command
            </div>
            <p className="text-sm leading-relaxed" style={{ color: "rgba(255,255,255,0.5)", maxWidth: 300 }}>
              Live GPS tracking, tactical route planning, and secure team communications for deployed units.
            </p>
          </motion.div>

          {/* Bottom status row */}
          <motion.div
            className="flex gap-5"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.8 }}
          >
            {[
              { icon: <FiWifi size={12} />, label: "SECURE TLS", ok: true },
              { icon: <FiRadio size={12} />, label: "COMMAND LINK", ok: true },
              { icon: <FiNavigation size={12} />, label: "GPS ACTIVE", ok: true },
            ].map((s, i) => (
              <motion.div key={i} className="flex items-center gap-2" initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.9 + i * 0.1 }}>
                <span style={{ color: "#22c55e" }}>{s.icon}</span>
                <span className="text-[9px] font-semibold tracking-widest" style={{ color: "rgba(255,255,255,0.35)" }}>{s.label}</span>
                <motion.span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: "#22c55e" }} animate={{ opacity: [1, 0.2, 1] }} transition={{ duration: 2, delay: i * 0.5, repeat: Infinity }} />
              </motion.div>
            ))}
          </motion.div>
        </div>
      </motion.div>

      {/* ── RIGHT PANEL — Form ────────────────────────────────────── */}
      <motion.div
        className="flex-1 flex flex-col items-center justify-center relative overflow-y-auto"
        style={{ background: "#060E1C" }}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.5 }}
      >
        {/* Top accent */}
        <div className="absolute top-0 left-0 right-0 h-px" style={{ background: "linear-gradient(90deg, transparent, rgba(59,130,246,0.4), transparent)" }} />

        <motion.div
          className="w-full px-8 py-10"
          style={{ maxWidth: 480 }}
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.6, ease: "easeOut" }}
        >
          {/* Mobile logo */}
          <div className="flex flex-col items-center mb-8 lg:hidden">
            <div className="w-16 h-16 rounded-2xl flex items-center justify-center mb-4" style={{ background: "rgba(59,130,246,0.12)", border: "1px solid rgba(59,130,246,0.3)" }}>
              <FiShield size={30} color="#3b82f6" />
            </div>
            <div className="text-white font-bold text-xl tracking-widest">DRD TRACKING</div>
            <div className="text-[9px] tracking-widest mt-1" style={{ color: "rgba(255,255,255,0.3)" }}>FIELD COORDINATION SYSTEM</div>
          </div>

          {/* Heading */}
          <div className="mb-8">
            <h1 className="text-white text-3xl font-bold mb-1">Welcome Back</h1>
            <p className="text-sm" style={{ color: "rgba(255,255,255,0.35)" }}>Sign in to your tactical account</p>
          </div>

          {/* Card */}
          <div className="rounded-2xl p-8" style={{ background: "rgba(15,28,46,0.95)", border: "1px solid rgba(255,255,255,0.06)", boxShadow: "0 30px 70px rgba(0,0,0,0.5)" }}>

            {/* Error banner */}
            <AnimatePresence>
              {error && (
                <motion.div
                  className="mb-6 flex items-start gap-3 rounded-xl px-4 py-3.5"
                  style={{ background: "rgba(239,68,68,0.07)", border: "1px solid rgba(239,68,68,0.2)" }}
                  initial={{ opacity: 0, y: -8, height: 0 }}
                  animate={{ opacity: 1, y: 0, height: "auto" }}
                  exit={{ opacity: 0, y: -8, height: 0 }}
                  transition={{ duration: 0.25 }}
                >
                  <FiAlertTriangle size={15} color="#ef4444" className="mt-0.5 shrink-0" />
                  <span className="text-sm leading-relaxed" style={{ color: "#f87171" }}>{error}</span>
                </motion.div>
              )}
            </AnimatePresence>

            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Identifier */}
              <div>
                <label className="block mb-2.5 text-[10px] font-bold tracking-widest" style={{ color: idFocused ? "#3b82f6" : "rgba(255,255,255,0.35)" }}>
                  OPERATOR ID / USERNAME
                </label>
                <motion.div
                  className="relative rounded-xl overflow-hidden"
                  animate={{ boxShadow: idFocused ? "0 0 0 2px rgba(59,130,246,0.45)" : "0 0 0 1px rgba(255,255,255,0.08)" }}
                  transition={{ duration: 0.2 }}
                >
                  <span className="absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none">
                    <FiUser size={16} color={idFocused ? "#3b82f6" : "rgba(255,255,255,0.2)"} />
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
                    style={{
                      width: "100%", paddingLeft: 44, paddingRight: 16, paddingTop: 14, paddingBottom: 14,
                      background: idFocused ? "rgba(59,130,246,0.06)" : "rgba(10,22,40,0.9)",
                      color: "white", fontSize: 13, outline: "none", border: "none",
                    }}
                  />
                </motion.div>
              </div>

              {/* Password */}
              <div>
                <label className="block mb-2.5 text-[10px] font-bold tracking-widest" style={{ color: pwFocused ? "#3b82f6" : "rgba(255,255,255,0.35)" }}>
                  ACCESS CODE
                </label>
                <motion.div
                  className="relative rounded-xl overflow-hidden"
                  animate={{ boxShadow: pwFocused ? "0 0 0 2px rgba(59,130,246,0.45)" : "0 0 0 1px rgba(255,255,255,0.08)" }}
                  transition={{ duration: 0.2 }}
                >
                  <span className="absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none">
                    <FiLock size={16} color={pwFocused ? "#3b82f6" : "rgba(255,255,255,0.2)"} />
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
                    style={{
                      width: "100%", paddingLeft: 44, paddingRight: 48, paddingTop: 14, paddingBottom: 14,
                      background: pwFocused ? "rgba(59,130,246,0.06)" : "rgba(10,22,40,0.9)",
                      color: "white", fontSize: 13, outline: "none", border: "none",
                    }}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPass(v => !v)}
                    tabIndex={-1}
                    style={{ position: "absolute", right: 14, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", cursor: "pointer", color: "rgba(255,255,255,0.3)" }}
                  >
                    {showPass ? <FiEyeOff size={15} /> : <FiEye size={15} />}
                  </button>
                </motion.div>
              </div>

              {/* Submit */}
              <motion.button
                type="submit"
                disabled={loading || !identifier || !password}
                className="w-full flex items-center justify-center gap-2.5 rounded-xl text-white font-bold tracking-widest relative overflow-hidden"
                style={{
                  padding: "15px 24px",
                  fontSize: 13,
                  background: loading || !identifier || !password ? "rgba(59,130,246,0.4)" : "#2563eb",
                  border: "none",
                  cursor: loading || !identifier || !password ? "not-allowed" : "pointer",
                }}
                whileTap={{ scale: loading ? 1 : 0.985 }}
                transition={{ duration: 0.1 }}
              >
                {loading ? (
                  <>
                    <motion.span
                      className="w-4 h-4 rounded-full border-2 shrink-0"
                      style={{ borderColor: "rgba(255,255,255,0.3)", borderTopColor: "white" }}
                      animate={{ rotate: 360 }}
                      transition={{ duration: 0.8, repeat: Infinity, ease: "linear" }}
                    />
                    AUTHENTICATING...
                  </>
                ) : (
                  <>
                    <FiZap size={14} />
                    AUTHENTICATE
                  </>
                )}
              </motion.button>
            </form>

            {/* Footer */}
            <div className="mt-7 pt-6 flex items-center justify-center gap-2" style={{ borderTop: "1px solid rgba(255,255,255,0.05)" }}>
              <motion.span className="w-1.5 h-1.5 rounded-full" style={{ background: "#22c55e" }} animate={{ opacity: [1, 0.3, 1] }} transition={{ duration: 2, repeat: Infinity }} />
              <span className="text-[9px] tracking-widest" style={{ color: "rgba(255,255,255,0.2)" }}>ENCRYPTED · AUTHORIZED PERSONNEL ONLY</span>
            </div>
          </div>
        </motion.div>
      </motion.div>
    </div>
  );
}
