import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { authApi } from "../services/api";
import { useAuthStore } from "../stores/authStore";

type Step = "credentials" | "otp";

export default function Login() {
  const navigate = useNavigate();
  const { setAuth } = useAuthStore();

  const [step, setStep] = useState<Step>("credentials");
  const [form, setForm] = useState({ email: "", password: "" });
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [clock, setClock] = useState("");

  // OTP state
  const [otpSession, setOtpSession] = useState("");
  const [emailHint, setEmailHint] = useState("");
  const [otpDigits, setOtpDigits] = useState(["", "", "", "", "", ""]);
  const [resendCooldown, setResendCooldown] = useState(0);
  const otpRefs = useRef<(HTMLInputElement | null)[]>([]);

  useEffect(() => {
    const tick = () =>
      setClock(
        new Date().toLocaleTimeString("en-GB", {
          hour12: false,
          hour: "2-digit",
          minute: "2-digit",
          second: "2-digit",
        })
      );
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (resendCooldown <= 0) return;
    const id = setInterval(() => setResendCooldown((c) => c - 1), 1000);
    return () => clearInterval(id);
  }, [resendCooldown]);

  // ── Step 1: Submit credentials ──
  const handleCredentials = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const { data } = await authApi.login(form.email, form.password);
      setOtpSession(data.otp_session);
      setEmailHint(data.email_hint);
      setStep("otp");
      setResendCooldown(60);
      setTimeout(() => otpRefs.current[0]?.focus(), 100);
    } catch (err: any) {
      setError(err.response?.data?.detail || "Invalid credentials. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  // ── Step 2: OTP digit input ──
  const handleOtpChange = (index: number, value: string) => {
    if (!/^\d*$/.test(value)) return;
    const next = [...otpDigits];
    next[index] = value.slice(-1);
    setOtpDigits(next);
    if (value && index < 5) otpRefs.current[index + 1]?.focus();
  };

  const handleOtpKeyDown = (index: number, e: React.KeyboardEvent) => {
    if (e.key === "Backspace" && !otpDigits[index] && index > 0) {
      otpRefs.current[index - 1]?.focus();
    }
    if (e.key === "ArrowLeft" && index > 0) otpRefs.current[index - 1]?.focus();
    if (e.key === "ArrowRight" && index < 5) otpRefs.current[index + 1]?.focus();
  };

  const handleOtpPaste = (e: React.ClipboardEvent) => {
    e.preventDefault();
    const text = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, 6);
    if (!text) return;
    const next = [...otpDigits];
    text.split("").forEach((ch, i) => { if (i < 6) next[i] = ch; });
    setOtpDigits(next);
    otpRefs.current[Math.min(text.length, 5)]?.focus();
  };

  const handleVerify = async (digits = otpDigits) => {
    const code = digits.join("");
    if (code.length !== 6) return;
    setError("");
    setLoading(true);
    try {
      const { data } = await authApi.verifyOtp(otpSession, code);
      setAuth(data.user, data.access_token, data.refresh_token);
      navigate("/");
    } catch (err: any) {
      setError(err.response?.data?.detail || "Invalid verification code.");
      setOtpDigits(["", "", "", "", "", ""]);
      setTimeout(() => otpRefs.current[0]?.focus(), 50);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (otpDigits.every((d) => d !== "") && step === "otp") {
      handleVerify(otpDigits);
    }
  }, [otpDigits]);

  const handleResend = async () => {
    if (resendCooldown > 0) return;
    try {
      await authApi.resendOtp(otpSession);
      setResendCooldown(60);
      setOtpDigits(["", "", "", "", "", ""]);
      setTimeout(() => otpRefs.current[0]?.focus(), 50);
    } catch (err: any) {
      setError(err.response?.data?.detail || "Failed to resend code.");
    }
  };

  return (
    <div className="login-root">
      {/* Subtle grid background */}
      <div className="login-grid" />
      <div className="login-glow" />

      {/* ── LEFT PANEL (desktop) ── */}
      <div className="login-left">
        <div className="login-brand">
          <img src="/logo1.png" alt="DRD" className="login-logo" />
          <div className="login-brand-text">
            <span className="login-brand-name">DRD OPERATIONS</span>
            <span className="login-brand-sub">FIELD COORDINATION SYSTEM</span>
          </div>
        </div>

        <div className="login-hero">
          <div className="login-hero-label">PLATFORM CAPABILITIES</div>
          <h2 className="login-hero-title">
            Unified {" "}
            <span className="login-hero-accent">Tactical</span>
           {" "} Operations 
          </h2>
          <div className="login-hero-bar" />
          <p className="login-hero-desc">
            Real-time field coordination, encrypted communications,
            live GPS tracking and mission planning — all in one secure platform.
          </p>
        </div>

        <div className="login-caps">
          {[
            { label: "Live Tracking", desc: "Real-time GPS field awareness" },
            { label: "Secure Comms", desc: "End-to-end encrypted messaging" },
            { label: "Mission Control", desc: "Full operational planning suite" },
            { label: "Mesh Network", desc: "Offline Reticulum connectivity" },
          ].map(({ label, desc }) => (
            <div key={label} className="login-cap-row">
              <div className="login-cap-dot" />
              <div>
                <div className="login-cap-label">{label}</div>
                <div className="login-cap-desc">{desc}</div>
              </div>
            </div>
          ))}
        </div>

        <div className="login-status-bar">
          <div className="login-status-item">
            <span className="login-dot-green" />
            <span>System Online</span>
          </div>
          <span className="login-clock-val">{clock}</span>
          <span className="login-node">NODE: OPS-01</span>
        </div>
      </div>

      {/* ── RIGHT PANEL ── */}
      <div className="login-right">
        <div className="login-form-wrap">

          {/* Mobile logo */}
          <div className="login-mobile-brand">
            <img src="/logo1.png" alt="DRD" className="login-mobile-logo" />
            <div>
              <div className="login-brand-name">DRD OPERATIONS</div>
              <div className="login-brand-sub">FIELD COORDINATION SYSTEM</div>
            </div>
          </div>

          {/* ── CREDENTIALS STEP ── */}
          {step === "credentials" && (
            <div className="login-card">
              <div className="login-card-header">
                <div className="login-card-header-line">
                  <div className="login-divider-line" />
                  <span className="login-divider-text">SECURE ACCESS</span>
                  <div className="login-divider-line" />
                </div>
                <h1 className="login-card-title">Sign In</h1>
                <p className="login-card-sub">Enter your credentials to access the platform</p>
              </div>

              {error && <ErrorBanner message={error} />}

              <form onSubmit={handleCredentials} className="login-form">
                <div className="login-field">
                  <label className="login-label">Email or Username</label>
                  <div className="login-input-wrap">
                    <span className="login-input-icon">
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-4 3.6-7 8-7s8 3 8 7"/></svg>
                    </span>
                    <input
                      type="text"
                      required
                      autoComplete="username"
                      value={form.email}
                      placeholder="username or email"
                      onChange={(e) => setForm({ ...form, email: e.target.value })}
                      className="login-input login-input-padded"
                    />
                  </div>
                </div>

                <div className="login-field">
                  <div className="login-label-row">
                    <label className="login-label">Password</label>
                  </div>
                  <div className="login-input-wrap">
                    <span className="login-input-icon">
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
                    </span>
                    <input
                      type={showPass ? "text" : "password"}
                      required
                      autoComplete="current-password"
                      value={form.password}
                      placeholder="••••••••••••"
                      onChange={(e) => setForm({ ...form, password: e.target.value })}
                      className="login-input login-input-padded login-input-with-right"
                    />
                    <button type="button" className="login-input-icon-right" onClick={() => setShowPass(!showPass)}>
                      {showPass
                        ? <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
                        : <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                      }
                    </button>
                  </div>
                </div>

                <button type="submit" disabled={loading} className="login-btn">
                  {loading ? <><Spinner /> Verifying...</> : "Continue"}
                </button>
              </form>
            </div>
          )}

          {/* ── OTP STEP ── */}
          {step === "otp" && (
            <div className="login-card">
              <div className="login-card-header">
                <div className="login-card-header-line">
                  <div className="login-divider-line" />
                  <span className="login-divider-text">VERIFICATION</span>
                  <div className="login-divider-line" />
                </div>
                <h1 className="login-card-title">Enter Code</h1>
                <p className="login-card-sub">
                  A 6-digit code was sent to <strong className="login-email-hint">{emailHint}</strong>
                </p>
              </div>

              {error && <ErrorBanner message={error} />}

              <div className="login-otp-group" onPaste={handleOtpPaste}>
                {otpDigits.map((digit, i) => (
                  <input
                    key={i}
                    ref={(el) => { otpRefs.current[i] = el; }}
                    type="text"
                    inputMode="numeric"
                    maxLength={1}
                    value={digit}
                    onChange={(e) => handleOtpChange(i, e.target.value)}
                    onKeyDown={(e) => handleOtpKeyDown(i, e)}
                    className={`login-otp-box${digit ? " login-otp-box-filled" : ""}`}
                    autoFocus={i === 0}
                  />
                ))}
              </div>

              <button
                className="login-btn"
                disabled={loading || otpDigits.some((d) => !d)}
                onClick={() => handleVerify()}
                style={{ marginTop: 8 }}
              >
                {loading ? <><Spinner /> Verifying...</> : "Verify & Sign In"}
              </button>

              <div className="login-otp-footer">
                <button
                  type="button"
                  className="login-back-btn"
                  onClick={() => { setStep("credentials"); setError(""); }}
                >
                  ← Back
                </button>
                <button
                  type="button"
                  className={`login-resend-btn${resendCooldown > 0 ? " disabled" : ""}`}
                  onClick={handleResend}
                  disabled={resendCooldown > 0}
                >
                  {resendCooldown > 0 ? `Resend in ${resendCooldown}s` : "Resend code"}
                </button>
              </div>
            </div>
          )}

          {/* Status bar */}
          <div className="login-stat-row">
            {[
              { k: "UPLINK", v: "ACTIVE", ok: true },
              { k: "ENCRYPT", v: "AES-256", ok: true },
              { k: "CHANNEL", v: "SECURE", ok: true },
            ].map(({ k, v, ok }) => (
              <div key={k} className="login-stat-cell">
                <div className="login-stat-key">{k}</div>
                <div className={`login-stat-val${ok ? " ok" : " warn"}`}>{v}</div>
              </div>
            ))}
          </div>

          <p className="login-footer-note">
            Authorized personnel only · DRD Operations
          </p>
        </div>
      </div>

      <style>{CSS}</style>
    </div>
  );
}

function ErrorBanner({ message }: { message: string }) {
  return (
    <div className="login-error">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
      </svg>
      <span>{message}</span>
    </div>
  );
}

function Spinner() {
  return <span className="login-spinner" />;
}

const CSS = `
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600;700&display=swap');

  *, *::before, *::after { box-sizing: border-box; }

  .login-root {
    min-height: 100vh;
    display: flex;
    background: #080f08;
    font-family: 'Inter', sans-serif;
    position: relative;
    overflow: hidden;
  }

  .login-grid {
    position: fixed; inset: 0; pointer-events: none;
    background-image:
      linear-gradient(rgba(22,163,74,0.035) 1px, transparent 1px),
      linear-gradient(90deg, rgba(22,163,74,0.035) 1px, transparent 1px);
    background-size: 64px 64px;
  }

  .login-glow {
    position: fixed; top: -300px; right: -200px;
    width: 700px; height: 700px; border-radius: 50%;
    background: radial-gradient(circle, rgba(22,163,74,0.06) 0%, transparent 65%);
    pointer-events: none;
  }

  /* ── LEFT PANEL ── */
  .login-left {
    display: none;
    width: 50%;
    flex-direction: column;
    justify-content: space-between;
    padding: 48px 52px;
    border-right: 1px solid rgba(22,163,74,0.1);
    position: relative; z-index: 1;
  }

  .login-brand {
    display: flex; align-items: center; gap: 14px;
  }

  .login-logo {
    height: 48px; width: auto; object-fit: contain;
    filter: brightness(0.95);
  }

  .login-brand-text { display: flex; flex-direction: column; gap: 2px; }

  .login-brand-name {
    color: #22c55e;
    font-family: 'JetBrains Mono', monospace;
    font-size: 13px; font-weight: 700; letter-spacing: 3px;
  }

  .login-brand-sub {
    color: #1f4d1f;
    font-family: 'JetBrains Mono', monospace;
    font-size: 8px; letter-spacing: 2.5px; text-transform: uppercase;
  }

  .login-hero { margin: 40px 0; }

  .login-hero-label {
    color: #1f4d1f;
    font-family: 'JetBrains Mono', monospace;
    font-size: 9px; letter-spacing: 4px; margin-bottom: 16px;
  }

  .login-hero-title {
    color: #d1fae5; font-size: 36px; font-weight: 700;
    line-height: 1.15; margin: 0 0 20px; letter-spacing: -0.5px;
  }

  .login-hero-accent { color: #16a34a; }

  .login-hero-bar { width: 40px; height: 3px; background: #16a34a; margin-bottom: 20px; }

  .login-hero-desc {
    color: #374151; font-size: 15px; line-height: 1.7; margin: 0;
    max-width: 440px;
  }

  .login-caps { display: flex; flex-direction: column; gap: 6px; }

  .login-cap-row {
    display: flex; align-items: flex-start; gap: 14px;
    padding: 12px 14px;
    border-left: 2px solid transparent;
    transition: border-color 0.15s, background 0.15s;
    cursor: default;
  }

  .login-cap-row:hover {
    border-left-color: #16a34a;
    background: rgba(22,163,74,0.04);
  }

  .login-cap-dot {
    width: 6px; height: 6px; border-radius: 50%;
    background: #16a34a; flex-shrink: 0; margin-top: 5px;
  }

  .login-cap-label {
    color: #d1fae5; font-size: 13px; font-weight: 600; margin-bottom: 2px;
  }

  .login-cap-desc { color: #374151; font-size: 12px; }

  .login-status-bar {
    display: flex; justify-content: space-between; align-items: center;
    padding-top: 20px; border-top: 1px solid rgba(22,163,74,0.1);
  }

  .login-status-item {
    display: flex; align-items: center; gap: 7px;
    color: #1f4d1f; font-size: 10px; letter-spacing: 1.5px;
    font-family: 'JetBrains Mono', monospace; text-transform: uppercase;
  }

  .login-dot-green {
    width: 6px; height: 6px; border-radius: 50%;
    background: #22c55e;
    box-shadow: 0 0 6px rgba(34,197,94,0.8);
    animation: pulse-green 2s ease-in-out infinite;
  }

  .login-clock-val {
    color: #1f4d1f; font-family: 'JetBrains Mono', monospace;
    font-size: 11px; letter-spacing: 1px;
  }

  .login-node {
    color: #162616; font-family: 'JetBrains Mono', monospace;
    font-size: 9px; letter-spacing: 1px;
  }

  /* ── RIGHT PANEL ── */
  .login-right {
    flex: 1;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    padding: 32px 20px;
    position: relative; z-index: 1;
  }

  .login-form-wrap { width: 100%; max-width: 420px; }

  /* Mobile brand */
  .login-mobile-brand {
    display: flex; align-items: center; gap: 12px;
    margin-bottom: 32px; justify-content: center;
  }

  .login-mobile-logo {
    height: 40px; width: auto; object-fit: contain;
  }

  /* Card */
  .login-card {
    background: rgba(10,18,10,0.95);
    border: 1px solid rgba(22,163,74,0.15);
    border-top: 2px solid #16a34a;
    padding: 32px 28px;
    box-shadow: 0 0 60px rgba(22,163,74,0.07), 0 8px 32px rgba(0,0,0,0.6);
    border-radius: 4px;
  }

  .login-card-header { margin-bottom: 24px; }

  .login-card-header-line {
    display: flex; align-items: center; gap: 10px; margin-bottom: 16px;
  }

  .login-divider-line { flex: 1; height: 1px; background: rgba(22,163,74,0.12); }

  .login-divider-text {
    color: #1f4d1f; font-size: 9px; letter-spacing: 3px;
    font-family: 'JetBrains Mono', monospace; white-space: nowrap;
  }

  .login-card-title {
    color: #ecfdf5; font-size: 22px; font-weight: 700; margin: 0 0 6px;
    letter-spacing: -0.3px;
  }

  .login-card-sub { color: #4b5563; font-size: 13px; margin: 0; line-height: 1.5; }

  .login-email-hint { color: #22c55e; }

  /* Error */
  .login-error {
    display: flex; align-items: flex-start; gap: 9px;
    background: rgba(127,29,29,0.18);
    border: 1px solid rgba(220,38,38,0.25);
    border-left: 3px solid #dc2626;
    padding: 11px 14px; margin-bottom: 18px;
    color: #fca5a5; font-size: 13px; line-height: 1.5;
  }

  .login-error svg { flex-shrink: 0; color: #ef4444; margin-top: 1px; }

  /* Form */
  .login-form { display: flex; flex-direction: column; gap: 18px; }

  .login-field { display: flex; flex-direction: column; gap: 7px; }

  .login-label-row { display: flex; justify-content: space-between; align-items: center; }

  .login-label { color: #6b7280; font-size: 12px; font-weight: 500; }

  .login-input-wrap {
    position: relative; display: flex; align-items: center;
  }

  .login-input-icon {
    position: absolute; left: 13px;
    color: rgba(22,163,74,0.45);
    display: flex; align-items: center;
    pointer-events: none; z-index: 1;
  }

  .login-input-icon-right {
    position: absolute; right: 0; top: 0; bottom: 0;
    padding: 0 13px;
    display: flex; align-items: center;
    cursor: pointer; color: rgba(22,163,74,0.35);
    background: none; border: none; z-index: 1;
    transition: color 0.15s;
  }
  .login-input-icon-right:hover { color: #22c55e; }

  .login-input {
    width: 100%; padding: 12px 14px;
    background: #050d05;
    border: 1px solid rgba(22,163,74,0.15);
    color: #d1fae5; font-size: 14px;
    outline: none; font-family: 'Inter', sans-serif;
    transition: border-color 0.15s, box-shadow 0.15s;
    -webkit-appearance: none;
    border-radius: 3px;
  }

  .login-input-padded { padding-left: 40px; }
  .login-input-with-right { padding-right: 42px; }

  .login-input::placeholder { color: #2a3f2a; }

  .login-input:focus {
    border-color: #16a34a;
    box-shadow: 0 0 0 3px rgba(22,163,74,0.1);
  }

  /* Submit button */
  .login-btn {
    width: 100%; padding: 13px 20px;
    background: #16a34a;
    border: none; cursor: pointer;
    color: #000; font-size: 14px; font-weight: 700;
    letter-spacing: 0.3px;
    display: flex; align-items: center; justify-content: center; gap: 9px;
    transition: background 0.15s, opacity 0.15s;
    font-family: 'Inter', sans-serif;
  }

  .login-btn:hover:not(:disabled) { background: #22c55e; }
  .login-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  /* Spinner */
  .login-spinner {
    display: inline-block; width: 14px; height: 14px;
    border: 2px solid rgba(0,0,0,0.4);
    border-top-color: #000;
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
  }

  /* ── OTP boxes ── */
  .login-otp-group {
    display: flex; gap: 10px; justify-content: center;
    margin: 8px 0 20px;
  }

  .login-otp-box {
    width: 48px; height: 56px;
    text-align: center;
    background: #050d05;
    border: 1px solid rgba(22,163,74,0.15);
    color: #d1fae5;
    font-size: 22px; font-weight: 700;
    font-family: 'JetBrains Mono', monospace;
    outline: none;
    transition: border-color 0.15s, box-shadow 0.15s;
    caret-color: #22c55e;
    -webkit-appearance: none;
  }

  .login-otp-box:focus {
    border-color: #16a34a;
    box-shadow: 0 0 0 3px rgba(22,163,74,0.1);
  }

  .login-otp-box-filled {
    border-color: rgba(22,163,74,0.4);
    color: #22c55e;
  }

  .login-otp-footer {
    display: flex; justify-content: space-between; align-items: center;
    margin-top: 16px;
  }

  .login-back-btn {
    background: none; border: none; cursor: pointer;
    color: #4b5563; font-size: 13px; padding: 0;
    font-family: 'Inter', sans-serif;
    transition: color 0.1s;
  }

  .login-back-btn:hover { color: #d1fae5; }

  .login-resend-btn {
    background: none; border: none; cursor: pointer;
    color: #16a34a; font-size: 13px; padding: 0;
    font-family: 'Inter', sans-serif;
    transition: color 0.1s;
  }

  .login-resend-btn:hover:not(.disabled) { color: #22c55e; }
  .login-resend-btn.disabled { color: #374151; cursor: default; }

  /* Stat row */
  .login-stat-row {
    display: grid; grid-template-columns: 1fr 1fr 1fr;
    gap: 1px; margin-top: 1px;
  }

  .login-stat-cell {
    background: rgba(10,18,10,0.9);
    border: 1px solid rgba(22,163,74,0.08);
    padding: 8px 10px; text-align: center;
  }

  .login-stat-key {
    color: #1f4d1f; font-size: 7px; letter-spacing: 2px;
    font-family: 'JetBrains Mono', monospace; margin-bottom: 3px;
    text-transform: uppercase;
  }

  .login-stat-val {
    font-size: 10px; font-weight: 700; letter-spacing: 1px;
    font-family: 'JetBrains Mono', monospace;
  }

  .login-stat-val.ok { color: #16a34a; }
  .login-stat-val.warn { color: #f59e0b; }

  .login-footer-note {
    text-align: center; margin-top: 20px;
    color: #162616; font-size: 10px; letter-spacing: 1.5px;
    text-transform: uppercase; font-family: 'JetBrains Mono', monospace;
  }

  /* Responsive */
  @media (min-width: 1024px) {
    .login-left { display: flex; }
    .login-mobile-brand { display: none; }
  }

  @media (max-width: 480px) {
    .login-card { padding: 24px 18px; }
    .login-otp-box { width: 40px; height: 48px; font-size: 18px; }
    .login-otp-group { gap: 7px; }
    .login-hero-title { font-size: 28px; }
    .login-form-wrap { max-width: 100%; }
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  @keyframes pulse-green {
    0%, 100% { box-shadow: 0 0 6px rgba(34,197,94,0.8); }
    50% { box-shadow: 0 0 12px rgba(34,197,94,0.4); }
  }
`;
