import os
import json
import base64
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

_KEY_FILE = Path(__file__).parent.parent.parent / ".vapid_keys.json"

_PRIVATE_KEY: str | None = None
_PUBLIC_KEY: str | None = None


def _generate_vapid_keys() -> tuple[str, str]:
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.backends import default_backend
    from cryptography.hazmat.primitives.serialization import (
        Encoding, PublicFormat, PrivateFormat, NoEncryption
    )

    private_key = ec.generate_private_key(ec.SECP256R1(), default_backend())
    public_key = private_key.public_key()

    # DER-encoded uncompressed public key for web push (65 bytes)
    pub_der = public_key.public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
    pub_b64 = base64.urlsafe_b64encode(pub_der).rstrip(b"=").decode()

    # PEM for pywebpush private key
    priv_pem = private_key.private_bytes(Encoding.PEM, PrivateFormat.TraditionalOpenSSL, NoEncryption())
    priv_b64 = base64.urlsafe_b64encode(priv_pem).rstrip(b"=").decode()

    return priv_b64, pub_b64


def load_vapid_keys() -> tuple[str | None, str | None]:
    global _PRIVATE_KEY, _PUBLIC_KEY

    # 1. Environment variables take priority
    env_priv = os.getenv("VAPID_PRIVATE_KEY")
    env_pub = os.getenv("VAPID_PUBLIC_KEY")
    if env_priv and env_pub:
        _PRIVATE_KEY, _PUBLIC_KEY = env_priv, env_pub
        return _PRIVATE_KEY, _PUBLIC_KEY

    # 2. Cached key file
    if _KEY_FILE.exists():
        try:
            keys = json.loads(_KEY_FILE.read_text())
            _PRIVATE_KEY, _PUBLIC_KEY = keys["private_key"], keys["public_key"]
            return _PRIVATE_KEY, _PUBLIC_KEY
        except Exception:
            pass

    # 3. Generate and persist
    try:
        priv, pub = _generate_vapid_keys()
        _KEY_FILE.write_text(json.dumps({"private_key": priv, "public_key": pub}, indent=2))
        _PRIVATE_KEY, _PUBLIC_KEY = priv, pub
        logger.info("Generated new VAPID keys — persisted to %s", _KEY_FILE)
        return _PRIVATE_KEY, _PUBLIC_KEY
    except Exception as e:
        logger.warning("VAPID key generation failed: %s — web push disabled", e)
        return None, None


def get_public_key() -> str | None:
    if _PUBLIC_KEY is None:
        load_vapid_keys()
    return _PUBLIC_KEY


async def send_web_push(subscription: dict, payload: dict) -> None:
    priv, _ = load_vapid_keys() if _PRIVATE_KEY is None else (_PRIVATE_KEY, _PUBLIC_KEY)
    if not priv:
        return
    try:
        from pywebpush import webpush, WebPushException
        webpush(
            subscription_info=subscription,
            data=json.dumps(payload),
            vapid_private_key=base64.urlsafe_b64decode(priv + "=="),
            vapid_claims={
                "sub": os.getenv("VAPID_SUBJECT", "mailto:admin@drd-ops.local"),
            },
            content_encoding="aes128gcm",
        )
    except Exception as e:
        logger.debug("Web push failed: %s", e)
