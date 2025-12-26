import os
import sys
import json
import hashlib
import random
import string
import requests
import time
import uuid
import threading
from collections import defaultdict
import mysql.connector
from flask import Flask, jsonify, request, send_file
from werkzeug.utils import secure_filename
from dotenv import load_dotenv
from functools import wraps

load_dotenv()

app = Flask(__name__)

class RateLimiter:
    def __init__(self):
        self.requests = defaultdict(list)
        self.lock = threading.Lock()

        self.limits = {
            'verification': {'requests': 5, 'window': 300},
            'token_check': {'requests': 30, 'window': 60},
            'devices': {'requests': 20, 'window': 60},
            'default': {'requests': 60, 'window': 60},
        }

    def _clean_old_requests(self, ip, window):
        now = time.time()
        self.requests[ip] = [t for t in self.requests[ip] if now - t < window]

    def is_allowed(self, ip, limit_type='default'):
        limit = self.limits.get(limit_type, self.limits['default'])
        max_requests = limit['requests']
        window = limit['window']

        with self.lock:
            self._clean_old_requests(ip, window)

            if len(self.requests[ip]) >= max_requests:
                return False

            self.requests[ip].append(time.time())
            return True

    def get_retry_after(self, ip, limit_type='default'):
        limit = self.limits.get(limit_type, self.limits['default'])
        window = limit['window']

        with self.lock:
            if not self.requests[ip]:
                return 0
            oldest = min(self.requests[ip])
            return max(0, int(window - (time.time() - oldest)))

rate_limiter = RateLimiter()

def rate_limit(limit_type='default'):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            ip = request.headers.get('X-Forwarded-For', request.remote_addr)
            if ip:
                ip = ip.split(',')[0].strip()

            if not rate_limiter.is_allowed(ip, limit_type):
                retry_after = rate_limiter.get_retry_after(ip, limit_type)
                log(f"Rate limit exceeded for {ip} on {limit_type}")
                response = jsonify({
                    'error': 'Too many requests',
                    'retry_after': retry_after
                })
                response.headers['Retry-After'] = str(retry_after)
                return response, 429

            return f(*args, **kwargs)
        return wrapper
    return decorator

def log(message):
    print(message, flush=True)

@app.before_request
def log_incoming_request():
    log("\n========== INCOMING REQUEST ==========")
    log(f"URL: {request.url}")
    log(f"Method: {request.method}")
    log("Headers:")
    for key, value in request.headers.items():
        log(f"  {key}: {value}")

    if request.is_json:
        log(f"Body: {json.dumps(request.json)}")
    elif request.form:
        log(f"Body (Form): {request.form.to_dict()}")
    elif request.data:
        log(f"Body (Raw): {request.data.decode('utf-8', errors='ignore')}")
    else:
        log("Body: [empty]")
    log("======================================\n")

@app.after_request
def log_outgoing_response(response):
    log("\n========== OUTGOING RESPONSE ==========")
    log(f"Status Code: {response.status_code}")
    if response.is_json:
        log(f"Response Body: {response.get_data(as_text=True)}")
    else:
        log("Response Body: [Not JSON]")
    log("=======================================\n")
    return response

BASE_URL = "https://app.eschool.center/ec-server"
USER_AGENT = "eSchoolMobile"

CURRENT_COOKIES = None
MY_PRS_ID = None

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_USER = os.getenv("DB_USER", "user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DB_NAME = os.getenv("DB_NAME", "reschool")

UPLOAD_FOLDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'uploads', 'custom_homework')
MAX_FILE_SIZE = 50 * 1024 * 1024
MAX_FILES_PER_HOMEWORK = 3
ALLOWED_EXTENSIONS = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'gif', 'txt', 'zip', 'rar'}

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

DEVICES = [
  "Samsung SM-G998B", "Samsung SM-G991B", "Samsung SM-G996B", "Samsung SM-S901B", "Samsung SM-S906B", "Samsung SM-S908B", "Samsung SM-S911B", "Samsung SM-S916B", "Samsung SM-S918B", "Samsung SM-S921B", "Samsung SM-S926B", "Samsung SM-S928B",
  "Samsung SM-G980F", "Samsung SM-G985F", "Samsung SM-G988B", "Samsung SM-G981B", "Samsung SM-G986B", "Samsung SM-G780F", "Samsung SM-G781B", "Samsung SM-G990B",
  "Samsung SM-N980F", "Samsung SM-N981B", "Samsung SM-N985F", "Samsung SM-N986B", "Samsung SM-N970F", "Samsung SM-N975F", "Samsung SM-N976B", "Samsung SM-N770F",
  "Samsung SM-G970F", "Samsung SM-G973F", "Samsung SM-G975F", "Samsung SM-G977B", "Samsung SM-G770F",
  "Samsung SM-F711B", "Samsung SM-F926B", "Samsung SM-F721B", "Samsung SM-F936B", "Samsung SM-F731B", "Samsung SM-F946B", "Samsung SM-F700F", "Samsung SM-F900F", "Samsung SM-F916B",
  "Samsung SM-A525F", "Samsung SM-A526B", "Samsung SM-A528B", "Samsung SM-A536B", "Samsung SM-A546B", "Samsung SM-A556B",
  "Samsung SM-A725F", "Samsung SM-A736B", "Samsung SM-A325F", "Samsung SM-A336B", "Samsung SM-A346B", "Samsung SM-A356B",
  "Samsung SM-M526B", "Samsung SM-M536B", "Samsung SM-M546B", "Samsung SM-E526B",
  "Samsung Galaxy A01", "Samsung Galaxy A02", "Samsung Galaxy A02s", "Samsung Galaxy A03", "Samsung Galaxy A03s", "Samsung Galaxy A04", "Samsung Galaxy A04s", "Samsung Galaxy A04e", "Samsung Galaxy A05", "Samsung Galaxy A05s",
  "Samsung Galaxy A10", "Samsung Galaxy A10s", "Samsung Galaxy A11", "Samsung Galaxy A12", "Samsung Galaxy A12 Nacho", "Samsung Galaxy A13", "Samsung Galaxy A13 5G", "Samsung Galaxy A14", "Samsung Galaxy A14 5G", "Samsung Galaxy A15", "Samsung Galaxy A15 5G",
  "Samsung Galaxy A20", "Samsung Galaxy A20s", "Samsung Galaxy A21", "Samsung Galaxy A21s", "Samsung Galaxy A22", "Samsung Galaxy A22 5G", "Samsung Galaxy A23", "Samsung Galaxy A23 5G", "Samsung Galaxy A24", "Samsung Galaxy A25 5G",
  "Samsung Galaxy A30", "Samsung Galaxy A30s", "Samsung Galaxy A31", "Samsung Galaxy A40", "Samsung Galaxy A41", "Samsung Galaxy A42 5G",
  "Samsung Galaxy A50", "Samsung Galaxy A50s", "Samsung Galaxy A51", "Samsung Galaxy A51 5G", "Samsung Galaxy A60", "Samsung Galaxy A70", "Samsung Galaxy A70s", "Samsung Galaxy A71", "Samsung Galaxy A71 5G", "Samsung Galaxy A80", "Samsung Galaxy A90 5G",
  "Samsung Galaxy M01", "Samsung Galaxy M02", "Samsung Galaxy M04", "Samsung Galaxy M11", "Samsung Galaxy M12", "Samsung Galaxy M13", "Samsung Galaxy M13 5G", "Samsung Galaxy M14 5G",
  "Samsung Galaxy M20", "Samsung Galaxy M21", "Samsung Galaxy M22", "Samsung Galaxy M23 5G", "Samsung Galaxy M30", "Samsung Galaxy M30s", "Samsung Galaxy M31", "Samsung Galaxy M31s", "Samsung Galaxy M32", "Samsung Galaxy M32 5G", "Samsung Galaxy M33 5G", "Samsung Galaxy M34 5G",
  "Samsung Galaxy M40", "Samsung Galaxy M42 5G", "Samsung Galaxy M51", "Samsung Galaxy M52 5G", "Samsung Galaxy M53 5G", "Samsung Galaxy M54 5G", "Samsung Galaxy M55 5G",
  "Samsung Galaxy F04", "Samsung Galaxy F12", "Samsung Galaxy F13", "Samsung Galaxy F14 5G", "Samsung Galaxy F22", "Samsung Galaxy F23 5G", "Samsung Galaxy F34 5G", "Samsung Galaxy F41", "Samsung Galaxy F42 5G", "Samsung Galaxy F54 5G", "Samsung Galaxy F62",
  "Samsung Galaxy XCover 4s", "Samsung Galaxy XCover 5", "Samsung Galaxy XCover 6 Pro", "Samsung Galaxy XCover 7",
  "Samsung Galaxy Quantum 2", "Samsung Galaxy Buddy", "Samsung Galaxy Jump", "Samsung Galaxy Wide5",
  "Google Pixel 4", "Google Pixel 4 XL", "Google Pixel 4a", "Google Pixel 4a (5G)",
  "Google Pixel 5", "Google Pixel 5a", "Google Pixel 6", "Google Pixel 6 Pro", "Google Pixel 6a",
  "Google Pixel 7", "Google Pixel 7 Pro", "Google Pixel 7a", "Google Pixel 8", "Google Pixel 8 Pro", "Google Pixel 8a",
  "Google Pixel Fold", "Google Pixel 3", "Google Pixel 3 XL", "Google Pixel 3a", "Google Pixel 3a XL",
  "Xiaomi Mi 11", "Xiaomi Mi 11 Pro", "Xiaomi Mi 11 Ultra", "Xiaomi Mi 11i", "Xiaomi Mi 11 Lite", "Xiaomi Mi 11 Lite 5G", "Xiaomi Mi 11 Lite 5G NE", "Xiaomi Mi 11X", "Xiaomi Mi 11X Pro",
  "Xiaomi 11T", "Xiaomi 11T Pro", "Xiaomi 12", "Xiaomi 12 Pro", "Xiaomi 12X", "Xiaomi 12S", "Xiaomi 12S Pro", "Xiaomi 12S Ultra", "Xiaomi 12 Lite",
  "Xiaomi 12T", "Xiaomi 12T Pro", "Xiaomi 13", "Xiaomi 13 Pro", "Xiaomi 13 Ultra", "Xiaomi 13 Lite", "Xiaomi 13T", "Xiaomi 13T Pro",
  "Xiaomi 14", "Xiaomi 14 Pro", "Xiaomi 14 Ultra", "Xiaomi Civi", "Xiaomi Civi 1S", "Xiaomi Civi 2", "Xiaomi Civi 3", "Xiaomi Civi 4 Pro",
  "Xiaomi Mi 10", "Xiaomi Mi 10 Pro", "Xiaomi Mi 10 Ultra", "Xiaomi Mi 10 Lite", "Xiaomi Mi 10T", "Xiaomi Mi 10T Pro", "Xiaomi Mi 10T Lite", "Xiaomi Mi 10S",
  "Xiaomi Mi 9", "Xiaomi Mi 9T", "Xiaomi Mi 9T Pro", "Xiaomi Mi 9 SE", "Xiaomi Mi 9 Lite", "Xiaomi Mi 9 Pro", "Xiaomi Mi 9 Pro 5G",
  "Xiaomi Mi Note 10", "Xiaomi Mi Note 10 Pro", "Xiaomi Mi Note 10 Lite", "Xiaomi Mi CC9", "Xiaomi Mi CC9 Pro", "Xiaomi Mi CC9e",
  "Xiaomi Mix 4", "Xiaomi Mix Fold", "Xiaomi Mix Fold 2", "Xiaomi Mix Fold 3",
  "Redmi Note 10", "Redmi Note 10 Pro", "Redmi Note 10S", "Redmi Note 10 5G", "Redmi Note 10 JE", "Redmi Note 10T 5G", "Redmi Note 10 Pro Max", "Redmi Note 10 Lite",
  "Redmi Note 11", "Redmi Note 11 Pro", "Redmi Note 11 Pro 5G", "Redmi Note 11 Pro+", "Redmi Note 11S", "Redmi Note 11S 5G", "Redmi Note 11T 5G", "Redmi Note 11E", "Redmi Note 11E Pro", "Redmi Note 11R", "Redmi Note 11 SE", "Redmi Note 11 4G",
  "Redmi Note 12", "Redmi Note 12 Pro", "Redmi Note 12 Pro+", "Redmi Note 12 4G", "Redmi Note 12S", "Redmi Note 12 Turbo", "Redmi Note 12R", "Redmi Note 12R Pro", "Redmi Note 12 Explorer",
  "Redmi Note 13", "Redmi Note 13 Pro", "Redmi Note 13 Pro+", "Redmi Note 13 4G", "Redmi Note 13R", "Redmi Note 13R Pro", "Redmi Note 13 5G",
  "Redmi Note 9", "Redmi Note 9 Pro", "Redmi Note 9S", "Redmi Note 9 Pro Max", "Redmi Note 9T", "Redmi Note 9 4G", "Redmi Note 9 5G",
  "Redmi Note 8", "Redmi Note 8 Pro", "Redmi Note 8T", "Redmi Note 8 2021", "Redmi Note 7", "Redmi Note 7 Pro", "Redmi Note 7S",
  "Redmi 13C", "Redmi 13C 5G", "Redmi 12", "Redmi 12C", "Redmi 10", "Redmi 10 2022", "Redmi 10C", "Redmi 10A", "Redmi 10 Prime", "Redmi 10 Power",
  "Redmi 9", "Redmi 9A", "Redmi 9C", "Redmi 9T", "Redmi 9i", "Redmi 9 Power", "Redmi 9 Prime", "Redmi 9 Activ", "Redmi 9 Sport",
  "Redmi 8", "Redmi 8A", "Redmi 8A Dual", "Redmi 7", "Redmi 7A",
  "Redmi K70", "Redmi K70 Pro", "Redmi K70E", "Redmi K60", "Redmi K60 Pro", "Redmi K60 Ultra", "Redmi K60E",
  "Redmi K50", "Redmi K50 Pro", "Redmi K50 Ultra", "Redmi K50 Gaming", "Redmi K50i",
  "Redmi K40", "Redmi K40 Pro", "Redmi K40 Pro+", "Redmi K40 Gaming", "Redmi K40S", "Redmi K30", "Redmi K30 Pro", "Redmi K30 Ultra", "Redmi K30S",
  "Redmi A1", "Redmi A1+", "Redmi A2", "Redmi A2+", "Redmi A3",
  "POCO F3", "POCO F4", "POCO F4 GT", "POCO F5", "POCO F5 Pro", "POCO F6", "POCO F6 Pro", "POCO F2 Pro", "POCO F1",
  "POCO X3", "POCO X3 NFC", "POCO X3 Pro", "POCO X3 GT",
  "POCO X4 Pro 5G", "POCO X4 GT", "POCO X5", "POCO X5 Pro", "POCO X6", "POCO X6 Pro", "POCO X2",
  "POCO M3", "POCO M3 Pro", "POCO M4 Pro", "POCO M4 Pro 5G", "POCO M5", "POCO M5s", "POCO M6 Pro", "POCO M6 5G", "POCO M4 5G",
  "POCO C3", "POCO C31", "POCO C40", "POCO C50", "POCO C51", "POCO C55", "POCO C65", "POCO M2", "POCO M2 Pro", "POCO M2 Reloaded",
  "Black Shark 5", "Black Shark 5 Pro", "Black Shark 5 RS", "Black Shark 4", "Black Shark 4 Pro", "Black Shark 4S", "Black Shark 4S Pro", "Black Shark 3", "Black Shark 3 Pro", "Black Shark 3S",
  "OnePlus 8", "OnePlus 8 Pro", "OnePlus 8T",
  "OnePlus 9", "OnePlus 9 Pro", "OnePlus 9R", "OnePlus 9RT",
  "OnePlus 10 Pro", "OnePlus 10T", "OnePlus 10R",
  "OnePlus 11", "OnePlus 11R",
  "OnePlus 12", "OnePlus 12R",
  "OnePlus 7", "OnePlus 7 Pro", "OnePlus 7T", "OnePlus 7T Pro", "OnePlus 6T", "OnePlus 6",
  "OnePlus Nord", "OnePlus Nord 2", "OnePlus Nord 2T", "OnePlus Nord 3",
  "OnePlus Nord CE", "OnePlus Nord CE 2", "OnePlus Nord CE 3", "OnePlus Nord CE 3 Lite", "OnePlus Nord CE 2 Lite",
  "OnePlus Nord N10", "OnePlus Nord N100", "OnePlus Nord N200", "OnePlus Nord N20", "OnePlus Nord N30",
  "OnePlus Open", "OnePlus Ace", "OnePlus Ace 2", "OnePlus Ace 2V", "OnePlus Ace 3", "OnePlus Ace Pro", "OnePlus Ace Racing",
  "Realme GT", "Realme GT 2", "Realme GT 2 Pro", "Realme GT 3", "Realme GT Neo 2", "Realme GT Neo 3", "Realme GT Neo 5", "Realme GT Neo 5 SE", "Realme GT Neo 3T", "Realme GT Master Edition", "Realme GT Explorer Master",
  "Realme 8", "Realme 8 Pro", "Realme 8i", "Realme 8s 5G", "Realme 8 5G",
  "Realme 9", "Realme 9 Pro", "Realme 9 Pro+", "Realme 9i", "Realme 9i 5G", "Realme 9 5G", "Realme 9 5G SE",
  "Realme 10", "Realme 10 Pro", "Realme 10 Pro+", "Realme 10s", "Realme 10 5G",
  "Realme 11", "Realme 11 Pro", "Realme 11 Pro+", "Realme 11x 5G", "Realme 11 5G",
  "Realme 12 Pro", "Realme 12 Pro+", "Realme 12+", "Realme 12x",
  "Realme C11", "Realme C12", "Realme C15", "Realme C20", "Realme C21", "Realme C21Y", "Realme C25", "Realme C25Y", "Realme C25s",
  "Realme C30", "Realme C30s", "Realme C31", "Realme C33", "Realme C35", "Realme C51", "Realme C53", "Realme C55", "Realme C67",
  "Realme Narzo 10", "Realme Narzo 10A", "Realme Narzo 20", "Realme Narzo 20A", "Realme Narzo 20 Pro",
  "Realme Narzo 30", "Realme Narzo 30 5G", "Realme Narzo 30 Pro 5G",
  "Realme Narzo 50", "Realme Narzo 50A", "Realme Narzo 50i", "Realme Narzo 50 Pro 5G", "Realme Narzo 50A Prime",
  "Realme Narzo 60", "Realme Narzo 60 Pro", "Realme Narzo 60x", "Realme Narzo 70 Pro", "Realme Narzo N53", "Realme Narzo N55",
  "Realme X7", "Realme X7 Pro", "Realme X7 Max", "Realme X50", "Realme X50 Pro", "Realme X3", "Realme X3 SuperZoom", "Realme X2", "Realme X2 Pro",
  "Oppo Find X3", "Oppo Find X3 Pro", "Oppo Find X3 Neo", "Oppo Find X3 Lite",
  "Oppo Find X5", "Oppo Find X5 Pro", "Oppo Find X5 Lite",
  "Oppo Find X6", "Oppo Find X6 Pro",
  "Oppo Find X7", "Oppo Find X7 Ultra",
  "Oppo Find N", "Oppo Find N2", "Oppo Find N2 Flip", "Oppo Find N3", "Oppo Find N3 Flip",
  "Oppo Reno 5", "Oppo Reno 5 Pro", "Oppo Reno 5 Pro+", "Oppo Reno 5 Z", "Oppo Reno 5 Lite",
  "Oppo Reno 6", "Oppo Reno 6 Pro", "Oppo Reno 6 Pro+", "Oppo Reno 6 Z",
  "Oppo Reno 7", "Oppo Reno 7 Pro", "Oppo Reno 7 SE", "Oppo Reno 7 Z",
  "Oppo Reno 8", "Oppo Reno 8 Pro", "Oppo Reno 8 Pro+", "Oppo Reno 8 T", "Oppo Reno 8 T 5G",
  "Oppo Reno 9", "Oppo Reno 9 Pro", "Oppo Reno 9 Pro+",
  "Oppo Reno 10", "Oppo Reno 10 Pro", "Oppo Reno 10 Pro+",
  "Oppo Reno 11", "Oppo Reno 11 Pro", "Oppo Reno 11 F",
  "Oppo A15", "Oppo A16", "Oppo A17", "Oppo A18", "Oppo A38", "Oppo A53", "Oppo A54", "Oppo A55", "Oppo A57", "Oppo A58", "Oppo A74", "Oppo A76", "Oppo A77", "Oppo A78", "Oppo A79", "Oppo A94", "Oppo A96", "Oppo A98",
  "Oppo A1 Pro", "Oppo A58 5G", "Oppo A58x", "Oppo A1x", "Oppo A97", "Oppo A57s", "Oppo A57e",
  "Oppo K10", "Oppo K10 5G", "Oppo K10 Pro", "Oppo K10x", "Oppo K11", "Oppo K11x",
  "Vivo X60", "Vivo X60 Pro", "Vivo X60 Pro+",
  "Vivo X70", "Vivo X70 Pro", "Vivo X70 Pro+",
  "Vivo X80", "Vivo X80 Pro",
  "Vivo X90", "Vivo X90 Pro", "Vivo X90 Pro+", "Vivo X90s",
  "Vivo X100", "Vivo X100 Pro",
  "Vivo X Fold", "Vivo X Fold+", "Vivo X Fold 2", "Vivo X Flip", "Vivo X Note",
  "Vivo V20", "Vivo V20 Pro", "Vivo V20 SE", "Vivo V21", "Vivo V21e", "Vivo V23", "Vivo V23 Pro", "Vivo V23e", "Vivo V25", "Vivo V25 Pro", "Vivo V25e", "Vivo V27", "Vivo V27 Pro", "Vivo V27e", "Vivo V29", "Vivo V29 Pro", "Vivo V29e", "Vivo V30", "Vivo V30 Pro",
  "Vivo Y11", "Vivo Y12", "Vivo Y20", "Vivo Y21", "Vivo Y22", "Vivo Y33s", "Vivo Y35", "Vivo Y36", "Vivo Y51", "Vivo Y72 5G", "Vivo Y76 5G", "Vivo Y100", "Vivo Y200", "Vivo Y56", "Vivo Y16", "Vivo Y02", "Vivo Y02s", "Vivo Y17s", "Vivo Y27", "Vivo Y27s",
  "Vivo T1", "Vivo T1 Pro", "Vivo T1 5G", "Vivo T1x", "Vivo T2", "Vivo T2 Pro", "Vivo T2x", "Vivo T3",
  "Vivo S1", "Vivo S1 Pro", "Vivo S10", "Vivo S10 Pro", "Vivo S12", "Vivo S12 Pro", "Vivo S15", "Vivo S15 Pro", "Vivo S16", "Vivo S16 Pro", "Vivo S17", "Vivo S17 Pro", "Vivo S18", "Vivo S18 Pro",
  "iQOO 7", "iQOO 7 Legend", "iQOO 8", "iQOO 8 Pro", "iQOO 9", "iQOO 9 Pro", "iQOO 9 SE", "iQOO 9T", "iQOO 10", "iQOO 10 Pro", "iQOO 11", "iQOO 11 Pro", "iQOO 11S", "iQOO 12", "iQOO 12 Pro",
  "iQOO Neo 6", "iQOO Neo 6 SE", "iQOO Neo 7", "iQOO Neo 7 Pro", "iQOO Neo 7 SE", "iQOO Neo 8", "iQOO Neo 8 Pro", "iQOO Neo 9", "iQOO Neo 9 Pro",
  "iQOO Z3", "iQOO Z5", "iQOO Z6", "iQOO Z6 Pro", "iQOO Z6 Lite", "iQOO Z7", "iQOO Z7 Pro", "iQOO Z7s", "iQOO Z8", "iQOO Z9",
  "Sony Xperia 1 II", "Sony Xperia 5 II", "Sony Xperia 10 II",
  "Sony Xperia 1 III", "Sony Xperia 5 III", "Sony Xperia 10 III",
  "Sony Xperia 1 IV", "Sony Xperia 5 IV", "Sony Xperia 10 IV", "Sony Xperia Ace III",
  "Sony Xperia 1 V", "Sony Xperia 5 V", "Sony Xperia 10 V",
  "Sony Xperia Pro-I", "Sony Xperia Pro", "Sony Xperia 1", "Sony Xperia 5", "Sony Xperia 10", "Sony Xperia L4", "Sony Xperia L3", "Sony Xperia 8", "Sony Xperia Ace II",
  "Asus Zenfone 8", "Asus Zenfone 8 Flip", "Asus Zenfone 9", "Asus Zenfone 10",
  "Asus ROG Phone 5", "Asus ROG Phone 5s", "Asus ROG Phone 5s Pro", "Asus ROG Phone 5 Ultimate",
  "Asus ROG Phone 6", "Asus ROG Phone 6D", "Asus ROG Phone 6 Pro", "Asus ROG Phone 6D Ultimate", "Asus ROG Phone 6 Batman Edition",
  "Asus ROG Phone 7", "Asus ROG Phone 7 Ultimate", "Asus ROG Phone 8", "Asus ROG Phone 8 Pro",
  "Asus Zenfone 7", "Asus Zenfone 7 Pro", "Asus ROG Phone 3", "Asus ROG Phone II",
  "Motorola Edge 20", "Motorola Edge 20 Pro", "Motorola Edge 20 Lite", "Motorola Edge 20 Fusion",
  "Motorola Edge 30", "Motorola Edge 30 Pro", "Motorola Edge 30 Ultra", "Motorola Edge 30 Fusion", "Motorola Edge 30 Neo",
  "Motorola Edge 40", "Motorola Edge 40 Pro", "Motorola Edge 40 Neo",
  "Motorola Edge 50 Pro", "Motorola Edge", "Motorola Edge+", "Motorola Edge S",
  "Motorola Moto G100", "Motorola Moto G200",
  "Motorola Moto G30", "Motorola Moto G50", "Motorola Moto G60", "Motorola Moto G60s", "Motorola Moto G10", "Motorola Moto G20",
  "Motorola Moto G31", "Motorola Moto G41", "Motorola Moto G51", "Motorola Moto G71",
  "Motorola Moto G32", "Motorola Moto G42", "Motorola Moto G52", "Motorola Moto G62", "Motorola Moto G72", "Motorola Moto G82",
  "Motorola Moto G53", "Motorola Moto G73", "Motorola Moto G54", "Motorola Moto G84", "Motorola Moto G13", "Motorola Moto G14", "Motorola Moto G23", "Motorola Moto G24", "Motorola Moto G24 Power", "Motorola Moto G34",
  "Motorola Moto G Stylus", "Motorola Moto G Stylus 5G", "Motorola Moto G Power", "Motorola Moto G Pure", "Motorola Moto G Play",
  "Motorola Moto E7", "Motorola Moto E7 Power", "Motorola Moto E13", "Motorola Moto E20", "Motorola Moto E22", "Motorola Moto E32", "Motorola Moto E40", "Motorola Moto E32s", "Motorola Moto E22i",
  "Motorola Razr 2022", "Motorola Razr 40", "Motorola Razr 40 Ultra", "Motorola Razr 5G", "Motorola Razr 2019",
  "Motorola One Fusion", "Motorola One Fusion+", "Motorola One Hyper", "Motorola One Vision", "Motorola One Action", "Motorola One Macro", "Motorola One Zoom", "Motorola One 5G", "Motorola One 5G Ace",
  "Nothing Phone (1)", "Nothing Phone (2)", "Nothing Phone (2a)",
  "Honor 50", "Honor 50 Lite", "Honor 50 Pro", "Honor 50 SE",
  "Honor 60", "Honor 60 Pro", "Honor 60 SE",
  "Honor 70", "Honor 70 Pro", "Honor 70 Pro+", "Honor 70 Lite",
  "Honor 80", "Honor 80 Pro", "Honor 80 SE", "Honor 80 GT",
  "Honor 90", "Honor 90 Lite", "Honor 90 Pro", "Honor 90 GT",
  "Honor Magic 3", "Honor Magic 3 Pro", "Honor Magic 3 Pro+",
  "Honor Magic 4", "Honor Magic 4 Pro", "Honor Magic 4 Ultimate", "Honor Magic 4 Lite",
  "Honor Magic 5", "Honor Magic 5 Pro", "Honor Magic 5 Ultimate", "Honor Magic 5 Lite",
  "Honor Magic 6", "Honor Magic 6 Pro", "Honor Magic 6 Ultimate", "Honor Magic 6 RSR",
  "Honor Magic V", "Honor Magic Vs", "Honor Magic V2", "Honor Magic V2 RSR",
  "Honor X7", "Honor X7a", "Honor X7b", "Honor X8", "Honor X8a", "Honor X8b", "Honor X9", "Honor X9a", "Honor X9b", "Honor X6", "Honor X6a", "Honor X5",
  "Honor Play 40", "Honor Play 50", "Honor Play 8T",
  "Huawei P40", "Huawei P40 Pro", "Huawei P40 Pro+", "Huawei P40 Lite", "Huawei P40 Lite 5G", "Huawei P40 Lite E",
  "Huawei P50", "Huawei P50 Pro", "Huawei P50E", "Huawei P50 Pocket",
  "Huawei P60", "Huawei P60 Pro", "Huawei P60 Art",
  "Huawei Mate 40", "Huawei Mate 40 Pro", "Huawei Mate 40 Pro+", "Huawei Mate 40 RS Porsche Design", "Huawei Mate 40E",
  "Huawei Mate 50", "Huawei Mate 50 Pro", "Huawei Mate 50 RS Porsche Design", "Huawei Mate 50E",
  "Huawei Mate 60", "Huawei Mate 60 Pro", "Huawei Mate 60 Pro+", "Huawei Mate 60 RS Ultimate",
  "Huawei Mate X2", "Huawei Mate Xs 2", "Huawei Mate X3", "Huawei Mate X5",
  "Huawei Nova 8", "Huawei Nova 8 Pro", "Huawei Nova 8i", "Huawei Nova 9", "Huawei Nova 9 Pro", "Huawei Nova 9 SE",
  "Huawei Nova 10", "Huawei Nova 10 Pro", "Huawei Nova 10 SE", "Huawei Nova 10z",
  "Huawei Nova 11", "Huawei Nova 11 Pro", "Huawei Nova 11 Ultra", "Huawei Nova 11i",
  "Huawei Nova 12", "Huawei Nova 12 Pro", "Huawei Nova 12 Ultra", "Huawei Nova 12 Lite",
  "Huawei Nova Y70", "Huawei Nova Y90", "Huawei Nova Y61", "Huawei Nova Y71", "Huawei Nova Y91",
  "Tecno Spark 7", "Tecno Spark 7 Pro", "Tecno Spark 7T", "Tecno Spark 8", "Tecno Spark 8P", "Tecno Spark 8C", "Tecno Spark 8T",
  "Tecno Spark 9", "Tecno Spark 9 Pro", "Tecno Spark 9T", "Tecno Spark 10", "Tecno Spark 10 Pro", "Tecno Spark 10C", "Tecno Spark 10 5G",
  "Tecno Spark 20", "Tecno Spark 20 Pro", "Tecno Spark 20 Pro+", "Tecno Spark 20C", "Tecno Spark Go 2024",
  "Tecno Camon 17", "Tecno Camon 17 Pro", "Tecno Camon 18", "Tecno Camon 18 Premier", "Tecno Camon 18P", "Tecno Camon 18i",
  "Tecno Camon 19", "Tecno Camon 19 Pro", "Tecno Camon 19 Neo", "Tecno Camon 20", "Tecno Camon 20 Pro", "Tecno Camon 20 Pro 5G", "Tecno Camon 20 Premier",
  "Tecno Camon 30", "Tecno Camon 30 Pro", "Tecno Camon 30 Premier",
  "Tecno Pova 2", "Tecno Pova 3", "Tecno Pova 4", "Tecno Pova 4 Pro", "Tecno Pova 5", "Tecno Pova 5 Pro", "Tecno Pova 6", "Tecno Pova 6 Pro",
  "Tecno Phantom X", "Tecno Phantom X2", "Tecno Phantom X2 Pro", "Tecno Phantom V Fold", "Tecno Phantom V Flip",
  "Infinix Hot 10", "Infinix Hot 10 Play", "Infinix Hot 10S", "Infinix Hot 11", "Infinix Hot 11S", "Infinix Hot 12", "Infinix Hot 12 Play", "Infinix Hot 12i",
  "Infinix Hot 20", "Infinix Hot 20 5G", "Infinix Hot 20S", "Infinix Hot 30", "Infinix Hot 30i", "Infinix Hot 30 Play", "Infinix Hot 40", "Infinix Hot 40 Pro", "Infinix Hot 40i",
  "Infinix Note 10", "Infinix Note 10 Pro", "Infinix Note 11", "Infinix Note 11 Pro", "Infinix Note 11S",
  "Infinix Note 12", "Infinix Note 12 G96", "Infinix Note 12 VIP", "Infinix Note 12 Pro", "Infinix Note 12 Pro 5G",
  "Infinix Note 30", "Infinix Note 30 Pro", "Infinix Note 30 VIP", "Infinix Note 30 5G", "Infinix Note 40", "Infinix Note 40 Pro", "Infinix Note 40 Pro+",
  "Infinix Zero X", "Infinix Zero X Pro", "Infinix Zero X Neo", "Infinix Zero Ultra", "Infinix Zero 5G", "Infinix Zero 20", "Infinix Zero 30", "Infinix Zero 30 5G",
  "Infinix GT 10 Pro", "Infinix Smart 7", "Infinix Smart 8", "Infinix Smart 8 Plus",
  "ZTE Axon 30", "ZTE Axon 30 Ultra", "ZTE Axon 30 Pro", "ZTE Axon 40", "ZTE Axon 40 Ultra", "ZTE Axon 40 Pro", "ZTE Axon 50 Ultra",
  "ZTE Nubia Z40 Pro", "ZTE Nubia Z50", "ZTE Nubia Z50 Ultra", "ZTE Nubia Z50S Pro", "ZTE Nubia Z60 Ultra",
  "ZTE RedMagic 6", "ZTE RedMagic 6 Pro", "ZTE RedMagic 6R", "ZTE RedMagic 6S Pro",
  "ZTE RedMagic 7", "ZTE RedMagic 7 Pro", "ZTE RedMagic 7S Pro",
  "ZTE RedMagic 8 Pro", "ZTE RedMagic 8 Pro+", "ZTE RedMagic 8S Pro", "ZTE RedMagic 9 Pro", "ZTE RedMagic 9 Pro+",
  "ZTE Blade V30", "ZTE Blade V40", "ZTE Blade V41", "ZTE Blade A72", "ZTE Blade A52",
  "LG Velvet", "LG Velvet 5G", "LG Wing", "LG V60 ThinQ", "LG G8 ThinQ", "LG G8X ThinQ", "LG G8S ThinQ", "LG V50 ThinQ", "LG K92 5G", "LG K61", "LG K51S", "LG K41S",
  "Nokia X30", "Nokia X20", "Nokia X10", "Nokia XR20", "Nokia XR21", "Nokia G60", "Nokia G50", "Nokia G22", "Nokia G21", "Nokia G11", "Nokia G11 Plus", "Nokia G42",
  "Nokia C32", "Nokia C22", "Nokia C12", "Nokia C31", "Nokia C21 Plus", "Nokia C30", "Nokia C20",
  "Nokia 8.3 5G", "Nokia 5.4", "Nokia 3.4", "Nokia 2.4", "Nokia 9 PureView",
  "HTC U20 5G", "HTC Desire 22 Pro", "HTC U23 Pro", "HTC Desire 21 Pro 5G", "HTC Desire 20 Pro",
  "Sharp Aquos R8", "Sharp Aquos R8 Pro", "Sharp Aquos R7", "Sharp Aquos R6", "Sharp Aquos Sense 8", "Sharp Aquos Sense 7", "Sharp Aquos Zero 6",
  "Fairphone 5", "Fairphone 4", "Fairphone 3+", "Fairphone 3",
  "Microsoft Surface Duo", "Microsoft Surface Duo 2",
  "Lenovo Legion Phone Duel", "Lenovo Legion Phone Duel 2", "Lenovo Legion Y70", "Lenovo Legion Y90", "Lenovo K14 Plus",
  "Meizu 21", "Meizu 21 Pro", "Meizu 20", "Meizu 20 Pro", "Meizu 20 Infinity", "Meizu 18", "Meizu 18 Pro", "Meizu 18s", "Meizu 18s Pro",
  "Ulefone Power Armor 18T", "Ulefone Power Armor 19", "Ulefone Armor 21", "Ulefone Armor 24", "Ulefone Note 16 Pro",
  "Blackview BV9300", "Blackview BV9200", "Blackview BV8900", "Blackview BL9000", "Blackview Shark 8", "Blackview A200 Pro",
  "Doogee V Max", "Doogee V30", "Doogee S100", "Doogee S100 Pro", "Doogee S99", "Doogee S98",
  "Cubot KingKong 9", "Cubot KingKong Star", "Cubot P80", "Cubot X70",
  "TCL 40 SE", "TCL 40 NxtPaper", "TCL 40R 5G", "TCL 30 5G", "TCL 30+", "TCL 30 SE", "TCL 20 Pro 5G", "TCL 20 SE", "TCL 10 Pro", "TCL 10L",
  "Cat S75", "Cat S62 Pro", "Cat S53", "Cat S42 H+"
]

def generate_random_string(length):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def get_random_device_model():
    return random.choice(DEVICES)

def sha256_hash(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()

def get_db_connection():
    try:
        return mysql.connector.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME
        )
    except Exception as e:
        log(f"DB Connection failed: {e}")
        return None

def save_session(cookies):
    conn = get_db_connection()
    if not conn:
        log("Cannot save session: DB not available")
        return

    try:
        cursor = conn.cursor()
        cookie_data = json.dumps(requests.utils.dict_from_cookiejar(cookies))

        cursor.execute(, (cookie_data, cookie_data))
        conn.commit()
        cursor.close()
        conn.close()
        log("Session saved to DB.")
    except Exception as e:
        log(f"Error saving session to DB: {e}")

def load_session():
    conn = get_db_connection()
    if not conn:
        return None

    try:
        cursor = conn.cursor()
        cursor.execute("SELECT cookies FROM server_sessions WHERE id = 1")
        row = cursor.fetchone()
        cursor.close()
        conn.close()

        if row:
            cookie_dict = json.loads(row[0])
            return requests.utils.cookiejar_from_dict(cookie_dict)
    except Exception as e:
        log(f"Error loading session from DB: {e}")

    return None

def log_request(method, url, headers, body=None):
    log("\n========== API REQUEST ==========")
    log(f"URL: {url}")
    log(f"Method: {method}")
    log("Headers:")
    if headers:
        for key, value in headers.items():
            if key.lower() == "cookie":
                log(f"  {key}: [COOKIES HIDDEN]")
            else:
                log(f"  {key}: {value}")

    if body:
        log(f"Body: {body}")
    else:
        log("Body: [empty]")
    log("==================================\n")

def log_response(response):
    log("\n========== API RESPONSE ==========")
    log(f"URL: {response.url}")
    log(f"Status Code: {response.status_code}")
    log("Headers:")
    for key, value in response.headers.items():
        log(f"  {key}: {value}")

    if response.text:
        if len(response.text) > 2000:
            log(f"Response Body: {response.text[:2000]}... [Truncated]")
        else:
            log(f"Response Body: {response.text}")
    else:
        log("Response Body: [empty]")
    log("==================================\n")

def login(username, password):
    if not username or not password:
        return None

    password_hash = sha256_hash(password)
    device_id = generate_random_string(16).lower()
    push_token = generate_random_string(152)
    device_model = get_random_device_model()

    device_payload = {
        "cliType": "mobile",
        "cliVer": "7.4.0",
        "pushToken": push_token,
        "deviceId": device_id,
        "deviceName": "-",
        "deviceModel": device_model,
        "cliOs": "android",
        "cliOsVer": "9"
    }

    body = {
        "username": username,
        "password": password_hash,
        "device": json.dumps(device_payload)
    }

    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Accept-Language": "ru-RU,en,*",
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/",
        "Content-Type": "application/x-www-form-urlencoded"
    }

    try:
        url = f"{BASE_URL}/login"
        log_request("POST", url, headers, body)
        response = requests.post(url, data=body, headers=headers)
        log_response(response)

        if response.status_code == 200:
            if 'JSESSIONID' in response.cookies or len(response.text) > 5:
                save_session(response.cookies)
                return response.cookies
        return None
    except Exception as e:
        log(f"Login error: {e}")
        return None

def get_state(cookies):
    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/"
    }
    try:
        url = f"{BASE_URL}/state"
        log_request("GET", url, headers)
        response = requests.get(url, headers=headers, cookies=cookies)
        log_response(response)

        if response.status_code == 200:
            return response.json()
        return None
    except Exception:
        return None

def get_messages(cookies):
    global CURRENT_COOKIES
    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/"
    }
    try:
        url = f"{BASE_URL}/chat/threads?newOnly=false&row=0&rowsCount=50"
        log_request("GET", url, headers)
        response = requests.get(url, headers=headers, cookies=cookies)
        log_response(response)

        if response.status_code == 401:
            log("Received 401, attempting re-login...")
            username = os.getenv("ESCHOOL_USERNAME")
            password = os.getenv("ESCHOOL_PASSWORD")
            new_cookies = login(username, password)
            if new_cookies:
                CURRENT_COOKIES = new_cookies
                log("Re-login successful, retrying request...")
                response = requests.get(url, headers=headers, cookies=new_cookies)
                log_response(response)
            else:
                log("Re-login failed.")
                return []

        if response.status_code == 200:
            threads = response.json()
            messages = []
            for thread in threads:
                messages.append({
                    "threadId": thread.get('threadId'),
                    "preview": thread.get('msgPreview', ''),
                    "sender": thread.get('senderFio', ''),
                    "imgObjId": thread.get('imgObjId'),
                    "date": thread.get('sendDate', 0)
                })
            return messages
        return []
    except Exception as e:
        log(f"Error fetching messages: {e}")
        return []

def get_thread_messages(cookies, thread_id):
    global CURRENT_COOKIES
    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/",
        "Content-Type": "application/json"
    }
    try:
        url = f"{BASE_URL}/chat/messages?getNew=false&isSearch=false&rowStart=0&rowsCount=50&threadId={thread_id}"
        body = json.dumps({"msgNums": None, "searchText": None})

        log_request("PUT", url, headers, body)
        response = requests.put(url, headers=headers, cookies=cookies, data=body)
        log_response(response)

        if response.status_code == 401:
            log("Received 401, attempting re-login...")
            username = os.getenv("ESCHOOL_USERNAME")
            password = os.getenv("ESCHOOL_PASSWORD")
            new_cookies = login(username, password)
            if new_cookies:
                CURRENT_COOKIES = new_cookies
                log("Re-login successful, retrying request...")
                response = requests.put(url, headers=headers, cookies=new_cookies, data=body)
                log_response(response)
            else:
                log("Re-login failed.")
                return []

        if response.status_code == 200:
            return response.json()
        return []
    except Exception as e:
        log(f"Error fetching thread messages: {e}")
        return []

def init_db():
    conn = get_db_connection()
    if not conn:
        log("Skipping DB initialization (no connection)")
        return

    try:
        cursor = conn.cursor()

        cursor.execute(, (DB_NAME,))
        old_schema = cursor.fetchone()[0] > 0

        if old_schema:
            log("Migrating verified_users table to new schema (multi-device support)...")
            cursor.execute("DROP TABLE IF EXISTS verified_users")
            log("Old table dropped, creating new schema...")

        cursor.execute()
        cursor.execute()
        cursor.execute()
        cursor.execute()
        conn.commit()
        log("Database initialized.")
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"Error initializing DB: {e}")

def initialize_server():
    global CURRENT_COOKIES, MY_PRS_ID

    log("Initializing server...")

    init_db()

    cookies = load_session()

    state = None
    if cookies:
        state = get_state(cookies)
        if not state:
            log("Session expired.")
            cookies = None

    if not cookies:
        username = os.getenv("ESCHOOL_USERNAME")
        password = os.getenv("ESCHOOL_PASSWORD")
        if username and password:
            cookies = login(username, password)
            if cookies:
                state = get_state(cookies)

    if state and cookies:
        CURRENT_COOKIES = cookies
        MY_PRS_ID = state.get('user', {}).get('prsId')
        name = state.get('profile', {}).get('firstName')
        log(f"Server authenticated as {name} (PRS ID: {MY_PRS_ID})")
    else:
        log("Failed to authenticate server. Please check .env")

@app.route('/request-verification', methods=['POST'])
@rate_limit('verification')
def request_verification():
    if not MY_PRS_ID:
        return jsonify({"error": "Server not authenticated"}), 503

    code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=16))
    return jsonify({
        "code": code,
        "targetPrsId": MY_PRS_ID
    })

@app.route('/check-verification', methods=['POST'])
@rate_limit('verification')
def check_verification():
    if not CURRENT_COOKIES:
        return jsonify({"error": "Server not authenticated"}), 503

    data = request.json
    expected_code = data.get('code')
    client_thread_id = data.get('threadId')

    if not expected_code:
        return jsonify({"error": "No code provided"}), 400

    log(f"Checking for message with code: {expected_code} (Client Thread: {client_thread_id})")

    verified_prs_id = None

    if client_thread_id:
        log(f"Strategy 1: Checking specific thread {client_thread_id}...")
        messages = get_thread_messages(CURRENT_COOKIES, client_thread_id)
        if messages:
            log(f"  Got {len(messages)} messages from thread {client_thread_id}")
        else:
            log(f"  Failed to get messages from thread {client_thread_id} or empty")

        for msg in messages:
            if expected_code in msg.get('msg', ''):
                verified_prs_id = msg.get('senderId')
                log(f"Found code in thread {client_thread_id}! Sender: {verified_prs_id}")
                break

    threads = []
    if not verified_prs_id:
        log("Strategy 2: Checking thread previews...")
        threads = get_messages(CURRENT_COOKIES)
        log(f"  Got {len(threads)} threads")
        for thread in threads:
            if expected_code in thread.get('preview', ''):
                verified_prs_id = thread.get('imgObjId')
                log(f"Found code in preview of thread with {thread.get('sender')}!")
                break

    if not verified_prs_id:
        if threads:
            log("Strategy 3: Deep scanning top 5 threads...")
            for i, thread in enumerate(threads[:5]):
                t_id = thread.get('threadId')
                if not t_id:
                    continue

                log(f"  Scanning thread {t_id} ({i+1}/5)...")
                msgs = get_thread_messages(CURRENT_COOKIES, t_id)
                for msg in msgs:
                    if expected_code in msg.get('msg', ''):
                        verified_prs_id = msg.get('senderId')
                        log(f"  Found code in thread {t_id}!")
                        break
                if verified_prs_id:
                    break
        else:
            log("Strategy 3 Skipped: No threads found in thread list.")

    if verified_prs_id:
        token = str(uuid.uuid4())
        device_name = data.get('deviceName', 'Unknown device')
        full_name = data.get('fullName')
        grade_class = data.get('gradeClass')

        conn = get_db_connection()
        if conn:
            try:
                cursor = conn.cursor()
                cursor.execute(, (token, verified_prs_id, device_name, full_name, grade_class))
                conn.commit()
                cursor.close()
                conn.close()
                log(f"Verified user: {full_name} ({grade_class}) - prs_id: {verified_prs_id}")
            except Exception as e:
                log(f"DB Error: {e}")
                return jsonify({"error": "Database error"}), 500

        return jsonify({
            "verified": True,
            "token": token
        })

    log("Verification failed: Code not found.")
    return jsonify({"verified": False})

@app.route('/revoke-token', methods=['POST'])
@rate_limit('devices')
def revoke_token():
    data = request.json
    token = data.get('token')

    if not token:
        return jsonify({"error": "No token provided"}), 400

    log(f"Revoking token: {token}")

    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM verified_users WHERE token = %s", (token,))
            rows_affected = cursor.rowcount
            conn.commit()
            cursor.close()
            conn.close()

            if rows_affected > 0:
                return jsonify({"success": True, "message": "Token revoked"})
            else:
                return jsonify({"success": False, "message": "Token not found"}), 404
        except Exception as e:
            log(f"DB Error: {e}")
            return jsonify({"error": "Database error"}), 500

    return jsonify({"error": "Database connection failed"}), 500

@app.route('/list-devices', methods=['POST'])
@rate_limit('devices')
def list_devices():
    data = request.json
    token = data.get('token')

    if not token:
        return jsonify({"error": "No token provided"}), 401

    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()

            cursor.execute("SELECT prs_id FROM verified_users WHERE token = %s", (token,))
            row = cursor.fetchone()

            if not row:
                cursor.close()
                conn.close()
                return jsonify({"error": "Invalid token"}), 401

            prs_id = row[0]

            cursor.execute(, (prs_id,))
            results = cursor.fetchall()

            devices = []
            for row in results:
                devices.append({
                    "token": row[0],
                    "deviceName": row[1] or "Unknown device",
                    "createdAt": row[2].isoformat() if row[2] else None,
                    "isCurrent": row[0] == token
                })

            cursor.close()
            conn.close()

            return jsonify({"devices": devices})

        except Exception as e:
            log(f"DB Error: {e}")
            return jsonify({"error": "Database error"}), 500

    return jsonify({"error": "Database connection failed"}), 500

@app.route('/check-verified-users', methods=['POST'])
@rate_limit('token_check')
def check_verified_users():
    data = request.json
    token = data.get('token')
    ids_to_check = data.get('ids')

    if not token:
        return jsonify({"error": "No token provided"}), 401

    if not ids_to_check or not isinstance(ids_to_check, list):
        return jsonify({"verifiedIds": []})

    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()

            cursor.execute("SELECT prs_id FROM verified_users WHERE token = %s", (token,))
            requester = cursor.fetchone()

            if not requester:
                cursor.close()
                conn.close()
                return jsonify({"error": "Invalid token"}), 401

            format_strings = ','.join(['%s'] * len(ids_to_check))
            query = f"SELECT DISTINCT prs_id FROM verified_users WHERE prs_id IN ({format_strings})"

            cursor.execute(query, tuple(ids_to_check))
            results = cursor.fetchall()

            verified_ids = [row[0] for row in results]

            cursor.close()
            conn.close()

            return jsonify({"verifiedIds": verified_ids})

        except Exception as e:
            log(f"DB Error: {e}")
            return jsonify({"error": "Database error"}), 500

    return jsonify({"error": "Database connection failed"}), 500

def get_user_by_token(token):
    conn = get_db_connection()
    if not conn:
        return None, None
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT prs_id, grade_class FROM verified_users WHERE token = %s", (token,))
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row:
            return row[0], row[1]
        return None, None
    except Exception as e:
        log(f"Error getting user by token: {e}")
        return None, None

def get_homework_files(cursor, homework_id):
    cursor.execute(, (homework_id,))
    files = []
    for row in cursor.fetchall():
        files.append({
            "id": row[0],
            "fileName": row[1],
            "fileSize": row[2],
            "mimeType": row[3]
        })
    return files

@app.route('/custom-homework/create', methods=['POST'])
@rate_limit('default')
def create_custom_homework():
    token = request.form.get('token')
    subject = request.form.get('subject')
    lesson_date = request.form.get('lesson_date')
    text = request.form.get('text')

    if not token:
        return jsonify({"error": "No token provided"}), 401
    if not subject or not lesson_date or not text:
        return jsonify({"error": "Missing required fields"}), 400

    prs_id, grade_class = get_user_by_token(token)
    if not prs_id:
        return jsonify({"error": "Invalid token"}), 401
    if not grade_class:
        return jsonify({"error": "User has no grade_class"}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()
        cursor.execute("SELECT full_name FROM verified_users WHERE token = %s", (token,))
        row = cursor.fetchone()
        author_full_name = row[0] if row else "Unknown"

        cursor.execute(, (prs_id, author_full_name, grade_class, subject, lesson_date, text))
        homework_id = cursor.lastrowid
        conn.commit()

        files = request.files.getlist('files')
        saved_files = []

        if len(files) > MAX_FILES_PER_HOMEWORK:
            cursor.execute("DELETE FROM custom_homework WHERE id = %s", (homework_id,))
            conn.commit()
            cursor.close()
            conn.close()
            return jsonify({"error": f"Maximum {MAX_FILES_PER_HOMEWORK} files allowed"}), 400

        homework_folder = os.path.join(UPLOAD_FOLDER, grade_class, str(homework_id))
        os.makedirs(homework_folder, exist_ok=True)

        for file in files:
            if file and file.filename:
                if not allowed_file(file.filename):
                    continue

                file.seek(0, 2)
                file_size = file.tell()
                file.seek(0)

                if file_size > MAX_FILE_SIZE:
                    continue

                original_name = secure_filename(file.filename)
                unique_name = f"{uuid.uuid4().hex[:8]}_{original_name}"
                file_path = os.path.join(homework_folder, unique_name)
                file.save(file_path)

                mime_type = file.content_type or 'application/octet-stream'

                cursor.execute(, (homework_id, original_name, file_size, mime_type, file_path))

                saved_files.append({
                    "id": cursor.lastrowid,
                    "fileName": original_name,
                    "fileSize": file_size,
                    "mimeType": mime_type
                })

        conn.commit()

        cursor.execute(, (homework_id,))
        hw = cursor.fetchone()

        cursor.close()
        conn.close()

        log(f"Custom homework created: {homework_id} by {author_full_name} for {grade_class}")

        return jsonify({
            "success": True,
            "homework": {
                "id": hw[0],
                "subject": hw[1],
                "lessonDate": hw[2].isoformat() if hw[2] else None,
                "text": hw[3],
                "authorFullName": hw[4],
                "authorPrsId": prs_id,
                "isMine": True,
                "files": saved_files,
                "createdAt": hw[5].isoformat() if hw[5] else None
            }
        })

    except Exception as e:
        log(f"Error creating homework: {e}")
        return jsonify({"error": "Database error"}), 500

@app.route('/custom-homework/list', methods=['POST'])
@rate_limit('default')
def list_custom_homework():
    data = request.json
    token = data.get('token')
    date_from = data.get('date_from')
    date_to = data.get('date_to')

    if not token:
        return jsonify({"error": "No token provided"}), 401

    prs_id, grade_class = get_user_by_token(token)
    if not prs_id:
        return jsonify({"error": "Invalid token"}), 401
    if not grade_class:
        return jsonify({"error": "User has no grade_class"}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        query =
        params = [grade_class]

        if date_from:
            query += " AND lesson_date >= %s"
            params.append(date_from)
        if date_to:
            query += " AND lesson_date <= %s"
            params.append(date_to)

        query += " ORDER BY lesson_date DESC, created_at DESC"

        cursor.execute(query, tuple(params))
        rows = cursor.fetchall()

        homework_list = []
        for row in rows:
            hw_id = row[0]
            files = get_homework_files(cursor, hw_id)

            homework_list.append({
                "id": hw_id,
                "authorPrsId": row[1],
                "authorFullName": row[2],
                "subject": row[3],
                "lessonDate": row[4].isoformat() if row[4] else None,
                "text": row[5],
                "isMine": row[1] == prs_id,
                "files": files,
                "createdAt": row[6].isoformat() if row[6] else None,
                "updatedAt": row[7].isoformat() if row[7] else None
            })

        cursor.close()
        conn.close()

        return jsonify({"homework": homework_list})

    except Exception as e:
        log(f"Error listing homework: {e}")
        return jsonify({"error": "Database error"}), 500

@app.route('/custom-homework/update', methods=['POST'])
@rate_limit('default')
def update_custom_homework():
    token = request.form.get('token')
    homework_id = request.form.get('homework_id')
    text = request.form.get('text')
    delete_file_ids = request.form.get('delete_file_ids')

    if not token:
        return jsonify({"error": "No token provided"}), 401
    if not homework_id:
        return jsonify({"error": "No homework_id provided"}), 400

    prs_id, grade_class = get_user_by_token(token)
    if not prs_id:
        return jsonify({"error": "Invalid token"}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        cursor.execute("SELECT author_prs_id, grade_class FROM custom_homework WHERE id = %s", (homework_id,))
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            return jsonify({"error": "Homework not found"}), 404
        if row[0] != prs_id:
            cursor.close()
            conn.close()
            return jsonify({"error": "Not authorized to edit this homework"}), 403

        hw_grade_class = row[1]

        if text:
            cursor.execute("UPDATE custom_homework SET text = %s WHERE id = %s", (text, homework_id))

        if delete_file_ids:
            try:
                ids_to_delete = json.loads(delete_file_ids)
                for file_id in ids_to_delete:
                    cursor.execute("SELECT storage_path FROM custom_homework_files WHERE id = %s AND homework_id = %s", (file_id, homework_id))
                    file_row = cursor.fetchone()
                    if file_row:
                        if os.path.exists(file_row[0]):
                            os.remove(file_row[0])

                        cursor.execute("DELETE FROM custom_homework_files WHERE id = %s", (file_id,))
            except json.JSONDecodeError:
                pass

        files = request.files.getlist('files')

        cursor.execute("SELECT COUNT(*) FROM custom_homework_files WHERE homework_id = %s", (homework_id,))
        existing_count = cursor.fetchone()[0]

        homework_folder = os.path.join(UPLOAD_FOLDER, hw_grade_class, str(homework_id))
        os.makedirs(homework_folder, exist_ok=True)

        saved_files = []
        for file in files:
            if existing_count + len(saved_files) >= MAX_FILES_PER_HOMEWORK:
                break

            if file and file.filename:
                if not allowed_file(file.filename):
                    continue

                file.seek(0, 2)
                file_size = file.tell()
                file.seek(0)

                if file_size > MAX_FILE_SIZE:
                    continue

                original_name = secure_filename(file.filename)
                unique_name = f"{uuid.uuid4().hex[:8]}_{original_name}"
                file_path = os.path.join(homework_folder, unique_name)
                file.save(file_path)

                mime_type = file.content_type or 'application/octet-stream'

                cursor.execute(, (homework_id, original_name, file_size, mime_type, file_path))

                saved_files.append({
                    "id": cursor.lastrowid,
                    "fileName": original_name,
                    "fileSize": file_size,
                    "mimeType": mime_type
                })

        conn.commit()

        cursor.execute(, (homework_id,))
        hw = cursor.fetchone()
        all_files = get_homework_files(cursor, homework_id)

        cursor.close()
        conn.close()

        log(f"Custom homework updated: {homework_id}")

        return jsonify({
            "success": True,
            "homework": {
                "id": hw[0],
                "subject": hw[1],
                "lessonDate": hw[2].isoformat() if hw[2] else None,
                "text": hw[3],
                "authorFullName": hw[4],
                "authorPrsId": hw[5],
                "isMine": True,
                "files": all_files,
                "createdAt": hw[6].isoformat() if hw[6] else None,
                "updatedAt": hw[7].isoformat() if hw[7] else None
            }
        })

    except Exception as e:
        log(f"Error updating homework: {e}")
        return jsonify({"error": "Database error"}), 500

@app.route('/custom-homework/delete', methods=['POST'])
@rate_limit('default')
def delete_custom_homework():
    data = request.json
    token = data.get('token')
    homework_id = data.get('homework_id')

    if not token:
        return jsonify({"error": "No token provided"}), 401
    if not homework_id:
        return jsonify({"error": "No homework_id provided"}), 400

    prs_id, _ = get_user_by_token(token)
    if not prs_id:
        return jsonify({"error": "Invalid token"}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        cursor.execute("SELECT author_prs_id, grade_class FROM custom_homework WHERE id = %s", (homework_id,))
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            return jsonify({"error": "Homework not found"}), 404
        if row[0] != prs_id:
            cursor.close()
            conn.close()
            return jsonify({"error": "Not authorized to delete this homework"}), 403

        grade_class = row[1]

        cursor.execute("SELECT storage_path FROM custom_homework_files WHERE homework_id = %s", (homework_id,))
        files = cursor.fetchall()

        for file_row in files:
            if file_row[0] and os.path.exists(file_row[0]):
                os.remove(file_row[0])

        homework_folder = os.path.join(UPLOAD_FOLDER, grade_class, str(homework_id))
        if os.path.exists(homework_folder) and not os.listdir(homework_folder):
            os.rmdir(homework_folder)

        cursor.execute("DELETE FROM custom_homework WHERE id = %s", (homework_id,))
        conn.commit()

        cursor.close()
        conn.close()

        log(f"Custom homework deleted: {homework_id}")

        return jsonify({"success": True})

    except Exception as e:
        log(f"Error deleting homework: {e}")
        return jsonify({"error": "Database error"}), 500

@app.route('/custom-homework/file/<int:file_id>', methods=['GET'])
@rate_limit('default')
def download_custom_homework_file(file_id):
    token = request.args.get('token')

    if not token:
        return jsonify({"error": "No token provided"}), 401

    prs_id, grade_class = get_user_by_token(token)
    if not prs_id:
        return jsonify({"error": "Invalid token"}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        cursor.execute(, (file_id,))
        row = cursor.fetchone()

        cursor.close()
        conn.close()

        if not row:
            return jsonify({"error": "File not found"}), 404

        file_path, file_name, mime_type, hw_grade_class = row

        if hw_grade_class != grade_class:
            return jsonify({"error": "Not authorized to download this file"}), 403

        if not os.path.exists(file_path):
            return jsonify({"error": "File not found on server"}), 404

        return send_file(
            file_path,
            mimetype=mime_type or 'application/octet-stream',
            as_attachment=True,
            download_name=file_name
        )

    except Exception as e:
        log(f"Error downloading file: {e}")
        return jsonify({"error": "Server error"}), 500

if __name__ == '__main__':
    initialize_server()
    app.run(host='0.0.0.0', port=20001)