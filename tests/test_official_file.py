import csv
import os
import tempfile

from src.connectors.official_file import OfficialFileConnector, normalize_header


def test_normalize_header_arabic():
    assert normalize_header("  إجمالي   الشهر ") == "اجمالي الشهر"
    assert normalize_header("أحمد") == "احمد"


def test_parse_csv_with_fixed_columns():
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "cpi.csv")
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["الشهر", "معدل التضخم", "ملاحظات"])
            w.writerow(["2026-08", 14.5, "x"])
            w.writerow(["2026-09", "", "y"])      # missing value -> None
        c = OfficialFileConnector(url="http://example.test/cpi.csv", save_dir=tmp)
        c.COLUMN_MAP = {"الشهر": "period", "معدل التضخم": "value"}
        rows = c.parse({"file_path": path})
        valid, rejected = c.validate(rows)
        assert len(valid) == 2 and not rejected
        assert valid[0]["value"] == 14.5 and valid[1]["value"] is None
        assert valid[0]["source"] == "official_file"


def test_parse_fails_loudly_when_columns_change():
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "cpi.csv")
        with open(path, "w", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow(["other", "columns"])
        c = OfficialFileConnector(url="http://x", save_dir=tmp)
        c.COLUMN_MAP = {"الشهر": "period", "معدل التضخم": "value"}
        try:
            c.parse({"file_path": path})
        except ValueError:
            return
        raise AssertionError("expected ValueError")
