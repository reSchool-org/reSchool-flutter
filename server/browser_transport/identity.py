import base64
import hashlib
import json
import os
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature


def encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def decode(value):
    return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))


def server_id(public):
    return hashlib.sha256(decode(public)).hexdigest()


def load_identity(directory):
    path = Path(directory) / 'browser-identity.pem'
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open('xb') as output:
            os.chmod(path, 0o600)
            key = ec.generate_private_key(ec.SECP256R1())
            output.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    except FileExistsError:
        pass
    return serialization.load_pem_private_key(path.read_bytes(), password=None)


def public_key(key):
    return encode(key.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint))


def sign(key, text):
    r, s = decode_dss_signature(key.sign(text.encode(), ec.ECDSA(hashes.SHA256())))
    return encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))


def verify(public, text, signature):
    try:
        key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), decode(public))
        raw = decode(signature)
        if len(raw) != 64:
            return False
        sig = encode_dss_signature(int.from_bytes(raw[:32], 'big'), int.from_bytes(raw[32:], 'big'))
        key.verify(sig, text.encode(), ec.ECDSA(hashes.SHA256()))
        return True
    except Exception:
        return False


def connection_code(key, signal, server):
    public = public_key(key)
    return 'rsc1.' + encode(json.dumps({'v': 1, 'id': server_id(public), 'key': public, 'signal': signal, 'server': server}, separators=(',', ':')).encode())
