import aiosmtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from app.config import settings


async def send_email(to: str, subject: str, html_body: str) -> bool:
    try:
        message = MIMEMultipart("alternative")
        message["From"] = f"DRD Operations <{settings.EMAIL_SENDER_EMAIL}>"
        message["To"] = to
        message["Subject"] = subject
        message.attach(MIMEText(html_body, "html"))
        await aiosmtplib.send(
            message,
            hostname=settings.EMAIL_SMTP_SERVER,
            port=settings.EMAIL_SMTP_PORT,
            username=settings.EMAIL_LOGIN,
            password=settings.EMAIL_SENDER_PASSWORD,
            start_tls=True,
        )
        return True
    except Exception as e:
        print(f"[EMAIL ERROR] {e}")
        return False


def _base_template(content: str) -> str:
    logo_url = f"{settings.FRONTEND_URL}/logo1.png"
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1.0"/>
<title>DRD Operations</title>
</head>
<body style="margin:0;padding:0;background:#0a0a0a;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#0a0a0a;padding:40px 20px;">
  <tr><td align="center">
    <table width="100%" style="max-width:560px;background:#111;border:1px solid #1a2e1a;border-radius:2px;">

      <!-- Header -->
      <tr>
        <td style="background:#0d1a0d;padding:28px 36px;border-bottom:2px solid #16a34a;">
          <table width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td>
                <img src="{logo_url}" alt="DRD" height="42"
                     style="height:42px;width:auto;display:block;"
                     onerror="this.style.display='none'"/>
              </td>
              <td align="right">
                <span style="color:#16a34a;font-size:10px;letter-spacing:3px;font-family:'Courier New',monospace;">
                  SECURE CHANNEL
                </span>
              </td>
            </tr>
          </table>
        </td>
      </tr>

      <!-- Body -->
      <tr>
        <td style="padding:36px 36px 28px;">
          {content}
        </td>
      </tr>

      <!-- Footer -->
      <tr>
        <td style="padding:20px 36px 28px;border-top:1px solid #1a2e1a;">
          <p style="color:#374151;font-size:11px;margin:0;line-height:1.6;">
            This message is intended only for authorized DRD personnel.<br/>
            If you did not initiate this request, contact your system administrator immediately.
          </p>
          <p style="color:#1f2d1f;font-size:10px;margin:12px 0 0;letter-spacing:1px;font-family:'Courier New',monospace;">
            DRD FIELD COORDINATION SYSTEM &nbsp;|&nbsp; CLASSIFICATION: RESTRICTED
          </p>
        </td>
      </tr>

    </table>
  </td></tr>
</table>
</body>
</html>"""


async def send_otp_email(to: str, full_name: str, otp_code: str) -> bool:
    digits = "".join(
        f'<td style="width:44px;height:52px;text-align:center;vertical-align:middle;background:#0d1a0d;border:1px solid #16a34a;border-radius:2px;margin:0 4px;">'
        f'<span style="color:#22c55e;font-size:26px;font-weight:700;font-family:\'Courier New\',monospace;">{d}</span></td>'
        for d in otp_code
    )

    content = f"""
      <h2 style="color:#d1fae5;font-size:20px;font-weight:700;margin:0 0 6px;letter-spacing:1px;">
        AUTHENTICATION CODE
      </h2>
      <p style="color:#374151;font-size:13px;margin:0 0 28px;">
        Hello <strong style="color:#d1fae5;">{full_name}</strong>,<br/>
        Use the verification code below to complete your login.
      </p>

      <!-- OTP Code -->
      <div style="text-align:center;margin:0 0 28px;">
        <p style="color:#374151;font-size:10px;letter-spacing:3px;margin:0 0 14px;font-family:'Courier New',monospace;">
          VERIFICATION CODE
        </p>
        <table cellpadding="0" cellspacing="6" style="margin:0 auto;">
          <tr>{digits}</tr>
        </table>
        <p style="color:#374151;font-size:11px;margin:16px 0 0;">
          Expires in <strong style="color:#f59e0b;">{settings.OTP_EXPIRE_MINUTES} minutes</strong>
        </p>
      </div>

      <!-- Warning box -->
      <div style="background:#1a0d0d;border:1px solid #450a0a;border-left:3px solid #ef4444;padding:14px 16px;margin:0 0 20px;">
        <p style="color:#fca5a5;font-size:12px;margin:0;line-height:1.6;">
          <strong>⚠ Security Notice:</strong> Never share this code with anyone.
          DRD Operations will never ask for your verification code.
        </p>
      </div>

      <p style="color:#4b5563;font-size:12px;margin:0;line-height:1.6;">
        If you did not attempt to sign in, your account may be compromised.
        Change your password immediately and contact your administrator.
      </p>
    """
    return await send_email(to, "DRD Operations — Login Verification Code", _base_template(content))


async def send_welcome_email(to: str, full_name: str, role: str) -> bool:
    role_display = role.replace("_", " ").title()
    content = f"""
      <h2 style="color:#d1fae5;font-size:20px;font-weight:700;margin:0 0 6px;letter-spacing:1px;">
        ACCOUNT ACTIVATED
      </h2>
      <p style="color:#374151;font-size:13px;margin:0 0 24px;">
        Welcome to the DRD Field Coordination System, <strong style="color:#d1fae5;">{full_name}</strong>.
        Your account has been provisioned and is ready for use.
      </p>
      <div style="background:#0d1a0d;border:1px solid #16a34a;padding:16px 20px;margin:0 0 24px;">
        <table width="100%" cellpadding="0" cellspacing="0">
          <tr>
            <td style="color:#374151;font-size:11px;letter-spacing:2px;font-family:'Courier New',monospace;padding-bottom:6px;">
              ASSIGNED ROLE
            </td>
          </tr>
          <tr>
            <td style="color:#22c55e;font-size:16px;font-weight:700;font-family:'Courier New',monospace;letter-spacing:1px;">
              {role_display.upper()}
            </td>
          </tr>
        </table>
      </div>
      <p style="color:#4b5563;font-size:12px;margin:0;line-height:1.8;">
        • Log in at <a href="{settings.FRONTEND_URL}" style="color:#16a34a;">{settings.FRONTEND_URL}</a><br/>
        • Mobile enrollment requires a QR code from your coordinator<br/>
        • Keep your credentials confidential at all times
      </p>
    """
    return await send_email(to, "DRD Operations — Account Activated", _base_template(content))


async def send_password_reset_email(to: str, reset_token: str, full_name: str) -> bool:
    reset_url = f"{settings.FRONTEND_URL}/reset-password?token={reset_token}"
    content = f"""
      <h2 style="color:#d1fae5;font-size:20px;font-weight:700;margin:0 0 6px;letter-spacing:1px;">
        PASSWORD RESET REQUEST
      </h2>
      <p style="color:#374151;font-size:13px;margin:0 0 24px;">
        Hello <strong style="color:#d1fae5;">{full_name}</strong>,<br/>
        A password reset was requested for your account. Click the button below to set a new password.
      </p>
      <div style="text-align:center;margin:0 0 24px;">
        <a href="{reset_url}"
           style="display:inline-block;background:#16a34a;color:#000;padding:14px 32px;
                  font-weight:700;font-size:13px;letter-spacing:2px;text-decoration:none;
                  font-family:'Courier New',monospace;">
          RESET PASSWORD
        </a>
      </div>
      <p style="color:#374151;font-size:12px;margin:0 0 12px;">
        This link expires in <strong style="color:#f59e0b;">2 hours</strong>.
        If you did not request a password reset, ignore this email — your password will remain unchanged.
      </p>
    """
    return await send_email(to, "DRD Operations — Password Reset", _base_template(content))
