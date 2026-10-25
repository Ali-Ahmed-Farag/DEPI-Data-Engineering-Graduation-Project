"""FX / gold connector.

Source: fawazahmed0 free currency API (no key, no rate limit stated, daily data,
200+ currencies including metals). One file per day with USD as the base:
  {"date": "2026-10-25", "usd": {"egp": 48.5, "xau": 0.00023, "eur": 0.86, ...}}
Each number is "units of that code per 1 USD"; xau is troy ounces per 1 USD.

What we output (all in EGP):
  currencies : EGP per 1 unit of the currency          (kind='currency', karat=None)
  gold       : EGP per GRAM for karat 24/21/18         (kind='gold', code='XAU')
Gold is derived from the international spot price. It is NOT the price at an
Egyptian jeweller (no making charges, taxes or local premium).
"""
from datetime import datetime, timedelta, timezone

import requests

from .base import BaseConnector, reject, is_number

GRAMS_PER_TROY_OUNCE = 31.1035
KARATS = (24, 21, 18)
REQUIRED = ("source", "code", "kind", "karat", "rate", "observed_at")

try:
    from zoneinfo import ZoneInfo

    _CAIRO = ZoneInfo("Africa/Cairo")
except Exception:  # tzdata missing (some Windows installs): pip install tzdata
    _CAIRO = timezone(timedelta(hours=2))


class FxGoldConnector(BaseConnector):
    name = "fx_gold"
    URLS = (  # main CDN first, Cloudflare fallback second
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{date}/v1/currencies/usd.json",
        "https://{date}.currency-api.pages.dev/v1/currencies/usd.json",
    )
    HEADERS = {"User-Agent": "EcoPlatformBot/1.0 (student project)"}
    CURRENCIES = ("usd", "eur", "gbp", "sar")  # shown as EGP per 1 unit

    def __init__(self, date="latest", session=None):
        self.date = date
        self.session = session or requests

    def fetch(self):
        last_error = None
        for template in self.URLS:
            url = template.format(date=self.date)
            try:
                resp = self.session.get(url, headers=self.HEADERS, timeout=15)
                self.last_endpoint = url
                self.last_status = resp.status_code
                resp.raise_for_status()
                data = resp.json()
                self._check_shape(data)
                return data
            except (requests.RequestException, ValueError) as exc:
                last_error = exc  # try the fallback URL
        raise RuntimeError(f"FX/Gold: all endpoints failed: {last_error}")

    @staticmethod
    def _check_shape(data):
        if not isinstance(data, dict) or not isinstance(data.get("usd"), dict):
            raise ValueError("FX/Gold: unexpected JSON shape (no 'usd' object)")
        if not isinstance(data.get("date"), str):
            raise ValueError("FX/Gold: no 'date' field")
        if "egp" not in data["usd"]:
            raise ValueError("FX/Gold: EGP not in response (task 1.12 failed)")

    @staticmethod
    def _observed_at(date_str):
        day = datetime.strptime(date_str, "%Y-%m-%d")
        return day.replace(tzinfo=_CAIRO).isoformat()

    def parse(self, raw):
        self._check_shape(raw)
        rates = raw["usd"]
        observed_at = self._observed_at(raw["date"])
        egp_per_usd = rates.get("egp")
        rows = []

        def row(code, kind, karat, rate):
            return {"source": self.name, "code": code, "kind": kind,
                    "karat": karat, "rate": rate, "observed_at": observed_at}

        for cur in self.CURRENCIES:
            per_usd = 1.0 if cur == "usd" else rates.get(cur)
            if is_number(egp_per_usd) and is_number(per_usd) and per_usd > 0:
                rate = egp_per_usd / per_usd
            else:
                rate = None  # validate() will reject it with a clear reason
            rows.append(row(cur.upper(), "currency", None, rate))

        xau = rates.get("xau")  # troy ounces per 1 USD
        for karat in KARATS:
            if is_number(egp_per_usd) and is_number(xau) and xau > 0:
                egp_per_gram_24k = egp_per_usd / xau / GRAMS_PER_TROY_OUNCE
                rate = egp_per_gram_24k * karat / 24
            else:
                rate = None
            rows.append(row("XAU", "gold", karat, rate))
        return rows

    def validate(self, rows):
        valid, rejected = [], []
        for r in rows:
            missing = [k for k in REQUIRED if k not in r]
            if missing:
                rejected.append(reject(r, f"missing field(s): {', '.join(missing)}"))
            elif r["kind"] not in ("currency", "gold"):
                rejected.append(reject(r, f"unknown kind: {r['kind']!r}"))
            elif r["kind"] == "gold" and r["karat"] not in KARATS:
                rejected.append(reject(r, f"gold needs karat 24/21/18, got {r['karat']!r}"))
            elif r["kind"] == "currency" and r["karat"] is not None:
                rejected.append(reject(r, "currency must have karat=None"))
            elif not is_number(r["rate"]):
                rejected.append(reject(r, f"rate missing or not a number: {r['rate']!r}"))
            elif r["rate"] <= 0:
                rejected.append(reject(r, f"rate must be > 0, got {r['rate']}"))
            else:
                valid.append(r)
        return valid, rejected
