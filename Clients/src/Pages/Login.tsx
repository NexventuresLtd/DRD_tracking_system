import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  FiShield, FiMail, FiLock, FiEye, FiEyeOff,
  FiAlertCircle, FiActivity,
} from "react-icons/fi";
import * as api from "../services/api";

export default function Login() {
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
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
      const msg =
        (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
        "Authentication failed. Check your credentials.";
      setError(String(msg));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="w-screen h-screen bg-slate-950 flex flex-col items-center justify-center p-4"
      style={{ fontFamily: "'Poppins', sans-serif" }}
    >
      {/* Top status bar */}
      <div className="fixed top-0 left-0 right-0 h-1 bg-gradient-to-r from-primary/0 via-primary/60 to-primary/0" />

      <div className="w-full max-w-[380px]">
        {/* Branding */}
        <div className="flex flex-col items-center mb-8">
          <div className="relative mb-4">
            <div className="w-16 h-16 rounded-2xl bg-primary/15 border border-primary/40 flex items-center justify-center">
              <FiShield size={30} color="#3b82f6" />
            </div>
            <span className="absolute -top-1 -right-1 w-3.5 h-3.5 bg-green-500 rounded-full border-2 border-slate-950 animate-pulse" />
          </div>
          <div className="text-white font-bold text-xl tracking-[0.2em]">DRD</div>
          <div className="text-slate-500 text-[10px] tracking-[0.25em] mt-0.5 text-center">
            FIELD COORDINATION SYSTEM
          </div>
        </div>

        {/* Card */}
        <div className="bg-slate-900 border border-white/8 rounded-2xl p-6 shadow-2xl">
          {/* Header */}
          <div className="flex items-center gap-2 mb-5">
            <FiActivity size={13} color="#3b82f6" />
            <span className="text-slate-300 text-xs font-bold tracking-widest">AUTHENTICATE</span>
          </div>

          {/* Error */}
          {error && (
            <div className="mb-4 flex items-start gap-2 px-3 py-2.5 bg-red-500/8 border border-red-500/20 rounded-lg">
              <FiAlertCircle size={13} color="#ef4444" className="mt-0.5 flex-shrink-0" />
              <span className="text-red-400 text-xs leading-relaxed">{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Username or Email */}
            <div>
              <label className="text-slate-500 text-[9px] font-bold tracking-[0.2em] mb-1.5 block">
                USERNAME / EMAIL
              </label>
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-600 pointer-events-none">
                  <FiMail size={13} />
                </span>
                <input
                  type="text"
                  value={identifier}
                  onChange={e => setIdentifier(e.target.value)}
                  required
                  autoComplete="username"
                  className="w-full bg-slate-800/80 border border-white/8 rounded-lg pl-9 pr-3 py-2.5 text-white text-xs focus:outline-none focus:border-primary/50 focus:bg-slate-800 transition-all placeholder:text-slate-600"
                  placeholder="commander or operator@drd.mil"
                />
              </div>
            </div>

            {/* Password */}
            <div>
              <label className="text-slate-500 text-[9px] font-bold tracking-[0.2em] mb-1.5 block">
                ACCESS CODE
              </label>
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-600 pointer-events-none">
                  <FiLock size={13} />
                </span>
                <input
                  type={showPass ? "text" : "password"}
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                  className="w-full bg-slate-800/80 border border-white/8 rounded-lg pl-9 pr-10 py-2.5 text-white text-xs focus:outline-none focus:border-primary/50 focus:bg-slate-800 transition-all placeholder:text-slate-600"
                  placeholder="••••••••••"
                />
                <button
                  type="button"
                  onClick={() => setShowPass(v => !v)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-600 hover:text-slate-400 transition-colors"
                >
                  {showPass ? <FiEyeOff size={13} /> : <FiEye size={13} />}
                </button>
              </div>
            </div>

            {/* Submit */}
            <button
              type="submit"
              disabled={loading || !identifier || !password}
              className="w-full py-2.5 bg-primary rounded-lg text-white text-xs font-semibold tracking-widest hover:opacity-90 active:scale-[0.99] disabled:opacity-40 disabled:cursor-not-allowed transition-all flex items-center justify-center gap-2"
            >
              {loading ? (
                <>
                  <span className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin flex-shrink-0" />
                  AUTHENTICATING...
                </>
              ) : (
                <>
                  <FiShield size={12} />
                  AUTHENTICATE
                </>
              )}
            </button>
          </form>

          {/* Footer hint */}
          <div className="mt-5 pt-4 border-t border-white/5 flex items-center justify-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-green-500/70 animate-pulse flex-shrink-0" />
            <span className="text-slate-600 text-[9px] tracking-[0.15em]">SECURE ENCRYPTED CONNECTION</span>
          </div>
        </div>

        <div className="text-center mt-5 text-slate-700 text-[9px] tracking-[0.25em]">
          AUTHORIZED PERSONNEL ONLY — DRDOPS
        </div>
      </div>
    </div>
  );
}
