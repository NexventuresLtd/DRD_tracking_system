import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import {
  FiUser, FiLock, FiEye, FiEyeOff,
  FiAlertTriangle,  FiRadio, FiWifi, FiNavigation, FiArrowRight
} from "react-icons/fi";
import * as api from "../services/api";

const GPS_IMAGE = "https://images.unsplash.com/photo-1614064641938-3bbee52942c7?w=1200&q=80";

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
    <div className="min-h-screen flex bg-slate-950">
      {/* ── LEFT PANEL — GPS tracking image ───────────────────────── */}
      <motion.div
        className="hidden lg:flex lg:w-[52%] relative overflow-hidden"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.7, ease: "easeOut" }}
      >
        {/* Background image */}
        <div className="absolute inset-0">
          <img
            src={GPS_IMAGE}
            alt="GPS tracking"
            className="w-full h-full object-cover scale-105"
            style={{ filter: "brightness(0.5) saturate(1.2)" }}
          />
        </div>

        {/* Overlay gradient */}
        <div className="absolute inset-0 bg-gradient-to-br from-slate-950/80 via-slate-900/50 to-slate-950/85" />

        {/* Subtle grid pattern overlay */}
        <div
          className="absolute inset-0 opacity-[0.03]"
          style={{
            backgroundImage: `linear-gradient(rgba(59, 130, 246, 0.3) 1px, transparent 1px), linear-gradient(90deg, rgba(59, 130, 246, 0.3) 1px, transparent 1px)`,
            backgroundSize: '60px 60px'
          }}
        />

        {/* Animated scan line */}
        <motion.div
          className="absolute left-0 right-0 h-[2px] bg-gradient-to-r from-transparent via-blue-500/50 to-transparent"
          animate={{ top: ["0%", "100%"] }}
          transition={{
            duration: 8,
            repeat: Infinity,
            ease: "linear",
            repeatDelay: 2
          }}
        />

        {/* Content overlay */}
        <div className="relative z-10 flex flex-col h-full p-12 xl:p-16">
          {/* Top branding */}
          <motion.div
            className="flex items-center gap-4"
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3, duration: 0.5 }}
          >
            <div className="w-12 h-12 rounded-2xl overflow-hidden flex items-center justify-center">
              <img src="/logo1.png" alt="DRD Logo" className="w-full h-full object-contain" />
            </div>
            <div>
              <div className="text-white font-bold text-lg tracking-[0.2em]">DRD TRACKING</div>
              <div className="text-[10px] tracking-[0.3em] text-white/30 mt-1">FIELD COORDINATION</div>
            </div>
          </motion.div>

          {/* Center tagline */}
          <motion.div
            className="flex-1 flex flex-col justify-center"
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.5, duration: 0.7 }}
          >
            <h2 className="text-5xl xl:text-6xl font-bold text-white leading-[1.1] mb-6">
              Real-Time Tracking
              <br />
              <span className="text-blue-400 text-4xl xl:text-5xl">Military Field Ops</span>
              <br />
              <span className="text-3xl xl:text-4xl">
                Command
              </span>
            </h2>
            <p className="text-base xl:text-lg leading-relaxed text-white/40 max-w-md">
              Live GPS tracking, tactical route planning, and secure team communications for deployed units.
            </p>

            {/* Feature badges */}
            <div className="flex flex-wrap gap-3 mt-8">
              {['Live Tracking', 'Secure Comms', 'Route Planning'].map((feature, i) => (
                <motion.span
                  key={i}
                  className="px-4 py-2 rounded-full text-xs font-medium bg-white/5 border border-white/10 text-white/60 backdrop-blur-sm"
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: 0.7 + i * 0.1 }}
                >
                  {feature}
                </motion.span>
              ))}
            </div>
          </motion.div>

          {/* Bottom status row */}
          <motion.div
            className="flex gap-8"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.8 }}
          >
            {[
              { icon: <FiWifi size={14} />, label: "SECURE TLS", ok: true },
              { icon: <FiRadio size={14} />, label: "COMMAND LINK", ok: true },
              { icon: <FiNavigation size={14} />, label: "GPS ACTIVE", ok: true },
            ].map((s, i) => (
              <motion.div
                key={i}
                className="flex items-center gap-3"
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.9 + i * 0.1 }}
              >
                <span className="text-emerald-400">{s.icon}</span>
                <span className="text-[10px] font-semibold tracking-[0.2em] text-white/25">{s.label}</span>
                <motion.span
                  className="w-2 h-2 rounded-full bg-emerald-400"
                  animate={{ opacity: [1, 0.2, 1] }}
                  transition={{
                    duration: 2,
                    delay: i * 0.5,
                    repeat: Infinity,
                    ease: "easeInOut"
                  }}
                />
              </motion.div>
            ))}
          </motion.div>
        </div>
      </motion.div>

      {/* ── RIGHT PANEL — Form ────────────────────────────────────── */}
      <motion.div
        className="flex-1 flex items-center justify-center p-6 sm:p-8 lg:p-12 xl:p-16"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.5 }}
      >
        {/* Top accent line */}
        <div className="absolute top-0 left-0 right-0 h-[1px] bg-gradient-to-r from-transparent via-blue-500/20 to-transparent lg:hidden" />

        <motion.div
          className="w-full max-w-[540px]"
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.6, ease: "easeOut" }}
        >
          {/* Mobile logo */}
          <div className="flex flex-col items-center mb-10 lg:hidden">
            <motion.div
              className="w-20 h-20 rounded-2xl overflow-hidden flex items-center justify-center mb-5"
              whileHover={{ scale: 1.05 }}
            >
              <img src="/logo1.png" alt="DRD Logo" className="w-full h-full object-contain" />
            </motion.div>
            <div className="text-white font-bold text-2xl tracking-[0.2em]">DRD TRACKING</div>
            <div className="text-[10px] tracking-[0.3em] text-white/25 mt-2">FIELD COORDINATION SYSTEM</div>
          </div>

          {/* Heading */}
          <div className="mb-8">
            <h1 className="text-white text-[32px] sm:text-4xl font-bold mb-3 leading-tight">Welcome Back</h1>
            <p className="text-sm sm:text-base text-white/35">Sign in to your tactical account</p>
          </div>

          {/* Card */}
          <div className="rounded-3xl p-[1px] bg-gradient-to-b from-white/10 to-transparent">
            <div className="rounded-3xl bg-slate-900/95 backdrop-blur-xl p-8 sm:p-10">
              {/* Error banner */}
              <AnimatePresence>
                {error && (
                  <motion.div
                    className="mb-6 flex items-start gap-3 rounded-2xl px-5 py-4 bg-red-500/5 border border-red-500/20"
                    initial={{ opacity: 0, y: -10, height: 0 }}
                    animate={{ opacity: 1, y: 0, height: "auto" }}
                    exit={{ opacity: 0, y: -10, height: 0 }}
                    transition={{ duration: 0.3 }}
                  >
                    <FiAlertTriangle size={16} className="text-red-400 mt-0.5 shrink-0" />
                    <span className="text-sm leading-relaxed text-red-300/90">{error}</span>
                  </motion.div>
                )}
              </AnimatePresence>

              <form onSubmit={handleSubmit} className="space-y-7">
                {/* Identifier */}
                <div>
                  <label className="block mb-3 text-[12px] font-medium tracking-[0.1em] text-white/75">
                    USERNAME
                  </label>
                  <div className={`relative rounded-2xl overflow-hidden transition-all duration-300 ${idFocused ? 'ring-2 ring-blue-500/50' : 'ring-1 ring-white/[0.08]'
                    }`}>
                    <span className="absolute left-4 top-1/2 -translate-y-1/2">
                      <FiUser size={18} className={idFocused ? 'text-blue-400 font-bold' : 'text-blue-900 font-bold'} />
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
                      className="w-full pl-12 pr-5 py-5 bg-slate-800/50 text-white text-sm placeholder:text-white/20 outline-none transition-colors duration-300"
                    />
                  </div>
                </div>

                {/* Password */}
                <div>
                  <label className="block mb-3 text-[12px] font-medium tracking-[0.1em] text-white/75">
                    ACCESS CODE
                  </label>
                  <div className={`relative rounded-2xl overflow-hidden transition-all duration-300 ${pwFocused ? 'ring-2 ring-blue-500/50' : 'ring-1 ring-white/[0.08]'
                    }`}>
                    <span className="absolute left-4 top-1/2 -translate-y-1/2">
                      <FiLock size={18} className={pwFocused ? 'text-blue-400 font-bold' : 'text-blue-900 font-bold'} />
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
                      className="w-full pl-12 pr-12 py-5 bg-slate-800/50 text-white text-sm placeholder:text-white/20 outline-none transition-colors duration-300"
                    />
                    <button
                      type="button"
                      onClick={() => setShowPass(v => !v)}
                      tabIndex={-1}
                      className="absolute right-4 top-1/2 -translate-y-1/2 text-white/30 hover:text-white/60 transition-colors"
                    >
                      {showPass ? <FiEyeOff size={18} className="text-blue-900 font-bold" /> : <FiEye size={18} className="text-blue-700 font-bold" />}
                    </button>
                  </div>
                </div>

                {/* Submit button */}
                <motion.button
                  type="submit"
                  disabled={loading || !identifier || !password}
                  className="w-full flex items-center justify-center gap-3 rounded-2xl text-white font-bold tracking-[0.15em] text-sm py-4 relative overflow-hidden transition-all duration-300"
                  style={{
                    background: loading || !identifier || !password
                      ? 'linear-gradient(135deg, rgba(59,130,246,0.3), rgba(37,99,235,0.3))'
                      : 'linear-gradient(135deg, #3b82f6, #2563eb)',
                    cursor: loading || !identifier || !password ? "not-allowed" : "pointer",
                  }}
                  whileHover={{
                    scale: loading || !identifier || !password ? 1 : 1.02,
                    boxShadow: loading || !identifier || !password
                      ? 'none'
                      : '0 10px 40px -10px rgba(59,130,246,0.4)'
                  }}
                  whileTap={{ scale: 0.98 }}
                >
                  {loading ? (
                    <>
                      <motion.span
                        className="w-5 h-5 rounded-full border-2 border-white/30 border-t-white"
                        animate={{ rotate: 360 }}
                        transition={{ duration: 0.8, repeat: Infinity, ease: "linear" }}
                      />
                      <span>AUTHENTICATING...</span>
                    </>
                  ) : (
                    <>
                      <span>AUTHENTICATE</span>
                      <FiArrowRight size={18} />
                    </>
                  )}
                </motion.button>
              </form>

              {/* Footer */}
              <div className="mt-8 pt-6 flex items-center justify-center gap-3 border-t border-white/[0.06]">
                <motion.span
                  className="w-2 h-2 rounded-full bg-emerald-400"
                  animate={{ opacity: [1, 0.2, 1] }}
                  transition={{ duration: 2, repeat: Infinity }}
                />
                <span className="text-[10px] tracking-[0.2em] text-white/75">ENCRYPTED · AUTHORIZED PERSONNEL ONLY</span>
              </div>
            </div>
          </div>

          {/* Additional info */}
          <p className="mt-6 text-center text-xs text-white/70 tracking-wide">
            Need help? Contact your system administrator
          </p>
        </motion.div>
      </motion.div>
    </div>
  );
}