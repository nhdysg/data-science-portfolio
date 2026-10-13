import sys
from pathlib import Path

import duckdb
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import run_queries  # noqa: E402
from build_db import build  # noqa: E402


@pytest.fixture(scope="module")
def con(tmp_path_factory):
    path = build(tmp_path_factory.mktemp("db") / "test.duckdb")
    return duckdb.connect(str(path), read_only=True)


@pytest.fixture(scope="module")
def results(con, tmp_path_factory):
    mp = pytest.MonkeyPatch()
    mp.setattr(run_queries, "TAB", tmp_path_factory.mktemp("tables"))
    yield run_queries.run_all(con)
    mp.undo()


def test_row_counts_match_source(con):
    counts = {t: con.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
              for t in ["flights", "weather", "planes", "airports", "airlines"]}
    assert counts == {"flights": 336_776, "weather": 26_115, "planes": 3_322,
                      "airports": 1_458, "airlines": 16}


def test_enriched_view_does_not_duplicate_flights(con):
    assert con.execute("SELECT count(*) FROM flights_enriched").fetchone()[0] == 336_776


def test_airport_kpis_cover_every_flight(results):
    assert results["01_airport_kpis"]["scheduled_flights"].sum() == 336_776


def test_carrier_shares_sum_to_100(results):
    assert results["02_carrier_scorecard"]["share_of_flights_pct"].sum() == pytest.approx(100, abs=0.5)


def test_every_query_returns_rows(results):
    assert len(results) == len(list((ROOT / "sql").glob("*.sql")))
    for name, df in results.items():
        assert len(df) > 0, name


def test_weather_buckets_have_no_unclassified_flights(results):
    assert results["06_weather_impact"]["level"].notna().all()


def test_delay_propagation_is_monotonic(results):
    pct = results["07_delay_propagation"]["pct_departing_15_plus_late"].tolist()
    assert pct == sorted(pct)


def test_mix_adjustment_expected_rates_average_to_overall(results):
    r = results["10_airport_vs_carrier_mix"]
    # Flight-weighted expected and observed rates must agree overall.
    w = r["flights"]
    assert (r["observed_on_time_pct"] * w).sum() / w.sum() == pytest.approx(
        (r["expected_from_airline_mix_pct"] * w).sum() / w.sum(), abs=0.2)
