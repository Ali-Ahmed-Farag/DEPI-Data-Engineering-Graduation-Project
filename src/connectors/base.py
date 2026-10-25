"""BaseConnector: the shape every source connector follows (team contract, section 9).

Each source is one connector file in src/connectors/ that inherits this class.
Adding a source = adding one file; nothing else in the project changes.

Record shapes that parse() must return (checklist 9.2):
  price     : source, product_id, product_name, category, unit, price, currency, observed_at
  fx / gold : source, code, kind ('currency'|'gold'), karat, rate, observed_at
  indicator : source, indicator_code, country, period, value

validate() returns (valid_rows, rejected_rows). Each rejected row is a dict:
  {"reason": "<why>", "record": <the row as it was>}
which maps straight onto ops.records_rejected (stage = 'validate').
"""


class BaseConnector:
    name: str = ""  # same value as dwh.dim_source.source_name, e.g. 'fx_gold'

    # Filled by fetch() so the raw layer can store where the data came from.
    last_endpoint = None
    last_status = None

    def fetch(self):
        """Download raw data (JSON / HTML / file bytes) and return it untouched."""
        raise NotImplementedError

    def parse(self, raw):
        """Turn raw data into a list of dict records (see shapes above)."""
        raise NotImplementedError

    def validate(self, rows):
        """Structural check only. Return (valid_rows, rejected_rows)."""
        raise NotImplementedError

    # ---- optional helpers (not part of the contract) -------------------
    def store_raw(self, raw):
        """Save the untouched response in raw.*. Override for non-JSON sources."""
        from src.common import raw_store

        return raw_store.store_api_response(
            self.name, self.last_endpoint, self.last_status, raw
        )

    def run(self, store=True):
        """fetch -> (save raw) -> parse -> validate. Returns (valid, rejected)."""
        raw = self.fetch()
        if store:
            self.store_raw(raw)
        rows = self.parse(raw)
        return self.validate(rows)


def reject(record, reason):
    """Build one rejected-row dict."""
    return {"reason": reason, "record": record}


def is_number(x):
    """True for real finite numbers (bool and NaN/inf are not numbers here)."""
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return False
    return x == x and x not in (float("inf"), float("-inf"))
