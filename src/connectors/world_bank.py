"""World Bank connector: annual indicators for Egypt (default: CPI inflation).

API docs: https://datahelpdesk.worldbank.org/knowledgebase/articles/889392
Response shape: [ {page info}, [ {indicator, country, date, value, ...}, ... ] ]
`value` is null for years without data; we keep those rows (staging decides).
"""
import requests

from .base import BaseConnector, reject, is_number

REQUIRED = ("source", "indicator_code", "country", "period", "value")


class WorldBankConnector(BaseConnector):
    name = "world_bank"
    BASE = "https://api.worldbank.org/v2/country/{country}/indicator/{indicator}"
    HEADERS = {"User-Agent": "EcoPlatformBot/1.0 (student project)"}

    def __init__(self, country="EGY", indicator="FP.CPI.TOTL.ZG", session=None):
        self.country = country
        self.indicator = indicator
        self.session = session or requests

    def fetch(self):
        url = self.BASE.format(country=self.country, indicator=self.indicator)
        resp = self.session.get(
            url,
            params={"format": "json", "per_page": 500},
            headers=self.HEADERS,
            timeout=15,
        )
        self.last_endpoint = url
        self.last_status = resp.status_code
        resp.raise_for_status()
        data = resp.json()
        self._check_shape(data)
        return data

    @staticmethod
    def _check_shape(data):
        if not (isinstance(data, list) and data and isinstance(data[0], dict)):
            raise ValueError("World Bank: unexpected JSON shape")
        if "message" in data[0]:
            raise ValueError(f"World Bank API error: {data[0]['message']}")
        if len(data) < 2 or not isinstance(data[1], list):
            raise ValueError("World Bank: response has no data list")
        if data[0].get("pages", 1) > 1:
            raise ValueError("World Bank: more than one page, raise per_page")

    def parse(self, raw):
        self._check_shape(raw)
        rows = []
        for item in raw[1]:
            indicator = item.get("indicator") or {}
            country = item.get("countryiso3code") or (item.get("country") or {}).get("id")
            rows.append(
                {
                    "source": self.name,
                    "indicator_code": indicator.get("id"),
                    "country": country,
                    "period": item.get("date"),
                    "value": item.get("value"),
                }
            )
        return rows

    def validate(self, rows):
        valid, rejected = [], []
        for row in rows:
            missing = [k for k in REQUIRED if k not in row]
            if missing:
                rejected.append(reject(row, f"missing field(s): {', '.join(missing)}"))
            elif not row["indicator_code"] or not row["country"]:
                rejected.append(reject(row, "empty indicator_code or country"))
            elif not (isinstance(row["period"], str) and row["period"].isdigit()
                      and len(row["period"]) == 4):
                rejected.append(reject(row, f"period is not a year: {row['period']!r}"))
            elif row["value"] is not None and not is_number(row["value"]):
                rejected.append(reject(row, f"value is not a number: {row['value']!r}"))
            else:
                valid.append(row)  # value None = known data gap, kept on purpose
        return valid, rejected
