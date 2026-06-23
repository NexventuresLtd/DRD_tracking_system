import aiosmtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from app.config import settings


async def send_email(to: str, subject: str, html_body: str) -> bool:
    try:
        message = MIMEMultipart("alternative")
        message["From"] = settings.EMAIL_SENDER_EMAIL
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
        print(f"Email send error: {e}")
        return False


async def send_password_reset_email(to: str, reset_token: str, full_name: str) -> bool:
    reset_url = f"https://{settings.DOMAIN}/reset-password?token={reset_token}"
    html = f"""
    <html><body>
    <h2>DRD Field Coordination System</h2>
    <p>Hello {full_name},</p>
    <p>You requested a password reset. Click the link below to reset your password:</p>
    <p><a href="{reset_url}" style="background:#3b82f6;color:white;padding:10px 20px;text-decoration:none;border-radius:5px;">Reset Password</a></p>
    <p>This link expires in 2 hours.</p>
    <p>If you did not request this, ignore this email.</p>
    <p>— DRD Security Team</p>
    </body></html>
    """
    return await send_email(to, "DRD Password Reset", html)


async def send_welcome_email(to: str, full_name: str, role: str) -> bool:
    html = f"""
    <html><body>
    <h2>Welcome to DRD Field Coordination System</h2>
    <p>Hello {full_name},</p>
    <p>Your account has been created with role: <strong>{role}</strong></p>
    <p>You can now log in to the DRD platform.</p>
    <p>— DRD Team</p>
    </body></html>
    """
    return await send_email(to, "Welcome to DRD", html)
