import asyncio
import smtplib
import random
import string
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

_SMTP_SERVER  = "mail.nexventures.net"
_SMTP_PORT    = 587
_SENDER_EMAIL = "security@nexventures.net"
_SENDER_PASS  = "Ca4*#Syc8Hmzz.P"
_LOGIN        = "security@nexventures.net"


def _send_smtp_sync(to_email: str, message_string: str) -> None:
    """Blocking SMTP send — always call via run_in_executor."""
    with smtplib.SMTP(_SMTP_SERVER, _SMTP_PORT, timeout=15) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()          # re-introduce after TLS upgrade
        server.login(_LOGIN, _SENDER_PASS)
        server.sendmail(_SENDER_EMAIL, to_email, message_string)


class EmailService:
    @staticmethod
    def generate_otp() -> str:
        return "".join(random.choices(string.digits, k=6))

    @staticmethod
    async def send_otp_email(to_email: str, otp: str, name: str = "Operator") -> bool:
        try:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = "DRD Secure Login — Verification Code"
            msg["From"]    = _SENDER_EMAIL
            msg["To"]      = to_email

            text = (
                f"DRD Tracking System — Login Verification\n\n"
                f"{name},\n\n"
                f"Your one-time verification code is:\n\n"
                f"  {otp}\n\n"
                f"This code expires in 10 minutes.\n"
                f"If you did not request this, contact your system administrator immediately.\n\n"
                f"— DRD Security Team"
            )

            html = f"""<!DOCTYPE html>
<html>
<body style="background:#050C1A;font-family:monospace;margin:0;padding:0;">
  <table width="100%" cellpadding="0" cellspacing="0"
         style="max-width:480px;margin:0 auto;padding:40px 20px;">
    <tr><td style="background:#0A1628;border:1px solid #1e3a5f;
                   border-radius:12px;padding:32px;">
      <div style="color:#3B82F6;font-size:11px;letter-spacing:3px;
                  font-weight:700;margin-bottom:8px;">
        DRD TRACKING SYSTEM
      </div>
      <div style="color:#fff;font-size:20px;font-weight:700;margin-bottom:24px;">
        Login Verification
      </div>
      <p style="color:#94a3b8;font-size:13px;margin:0 0 24px;">
        Hello {name},<br><br>
        Your one-time verification code:
      </p>
      <div style="background:#0D2144;border:1px solid #3B82F6;
                  border-radius:8px;padding:24px;text-align:center;
                  margin-bottom:24px;">
        <span style="color:#3B82F6;font-size:36px;font-weight:900;
                     letter-spacing:12px;">{otp}</span>
      </div>
      <p style="color:#64748b;font-size:11px;margin:0;">
        Expires in 10 minutes. Do not share this code.<br>
        If you did not attempt to log in, contact your administrator.
      </p>
    </td></tr>
  </table>
</body>
</html>"""

            msg.attach(MIMEText(text, "plain"))
            msg.attach(MIMEText(html, "html"))

            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, _send_smtp_sync, to_email, msg.as_string())

            return True

        except Exception as exc:
            print(f"[EmailService] Failed to send OTP to {to_email}: {exc}")
            return False
