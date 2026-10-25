import json
import os

from src.connectors.world_bank import WorldBankConnector

SAMPLE = os.path.join(os.path.dirname(__file__), "samples", "world_bank_egy_inflation.json")


def load():
    with open(SAMPLE, encoding="utf-8") as f:
        return json.load(f)


def test_parse_shape_and_values():
    rows = WorldBankConnector().parse(load())
    assert rows, "parse returned nothing"
    for r in rows:
        assert set(r) == {"source", "indicator_code", "country", "period", "value"}
        assert r["source"] == "world_bank"
        assert r["indicator_code"] == "FP.CPI.TOTL.ZG"
        assert r["country"] == "EGY"


def test_validate_keeps_null_values_as_gaps():
    c = WorldBankConnector()
    valid, rejected = c.validate(c.parse(load()))
    assert valid and not rejected
    assert any(r["value"] is None for r in valid)  # the 2020 gap is kept


def test_validate_rejects_bad_rows():
    c = WorldBankConnector()
    good = {"source": "world_bank", "indicator_code": "X", "country": "EGY",
            "period": "2022", "value": 1.0}
    bad_period = dict(good, period="22")
    bad_value = dict(good, value="abc")
    no_field = {"source": "world_bank"}
    valid, rejected = c.validate([good, bad_period, bad_value, no_field])
    assert valid == [good]
    assert len(rejected) == 3
    assert all(r["reason"] for r in rejected)


def test_check_shape_errors():
    for bad in (None, [], [{"message": [{"id": "120"}]}], [{"pages": 1}], [{"pages": 1}, None]):
        try:
            WorldBankConnector._check_shape(bad)
        except ValueError:
            continue
        raise AssertionError(f"no error for {bad!r}")


class FakeResp:
    status_code = 200

    def __init__(self, data):
        self._data = data

    def raise_for_status(self):
        pass

    def json(self):
        return self._data


class FakeSession:
    def get(self, url, **kwargs):
        assert kwargs.get("timeout") == 15
        return FakeResp(load())


def test_fetch_uses_timeout_and_records_endpoint():
    c = WorldBankConnector(session=FakeSession())
    data = c.fetch()
    assert data == load()
    assert c.last_status == 200 and "FP.CPI.TOTL.ZG" in c.last_endpoint
