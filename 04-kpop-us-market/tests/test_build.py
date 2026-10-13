import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build import build  # noqa: E402


@pytest.fixture(scope="module")
def con():
    return build()


def tag(con, credit):
    row = con.execute("SELECT kpop, segment, western_collab FROM performer_tags WHERE credit = ?",
                      [credit]).fetchone()
    assert row is not None, f"{credit!r} not on either chart"
    return row


@pytest.mark.parametrize("credit, segment", [
    ("BTS", "Korean act"),
    ("TOMORROW X TOGETHER", "Korean act"),       # contains the " X " separator
    ("Coldplay x BTS", "Korean act"),
    ("ROSE & Bruno Mars", "Korean act"),
    ("KATSEYE", "KATSEYE"),
    ("HUNTR/X: EJAE, Audrey Nuna & REI AMI", "KPop Demon Hunters"),
    ("JEONGYEON, JIHYO & CHAEYOUNG Of TWICE", "KPop Demon Hunters"),
])
def test_kpop_credits_are_tagged(con, credit, segment):
    kpop, seg, _ = tag(con, credit)
    assert kpop and seg == segment


@pytest.mark.parametrize("credit", ["Bobby V Featuring Yung Joc", "Bad Bunny, Omar Courtz & Dei V",
                                    "Taylor Swift", "Soundtrack"])
def test_lookalike_names_are_not_tagged(con, credit):
    assert not tag(con, credit)[0]


def test_old_namesakes_are_not_tagged(con):
    # "Jin" and "Wendy" charted decades before the K-pop artists with those names
    n = con.execute("""SELECT count(*) FROM entries e JOIN performer_tags t USING (credit)
                       WHERE t.kpop AND e.chart_week < DATE '2009-01-01'""").fetchone()[0]
    assert n == 0


def test_western_collab_flag(con):
    assert tag(con, "Coldplay x BTS")[2]
    assert not tag(con, "BTS")[2]
    assert not tag(con, "Le Sserafim, ILLIT & KATSEYE")[2]   # all K-pop credits


def test_demon_hunters_soundtrack_album_is_tagged(con):
    seg = con.execute("""SELECT DISTINCT t.segment FROM entries e JOIN performer_tags t USING (credit)
                         WHERE e.chart = 'billboard200' AND e.title = 'KPop Demon Hunters'""").fetchall()
    assert seg == [("KPop Demon Hunters",)]


def test_albums_have_full_first_year_and_valid_positions(con):
    bad = con.execute("""SELECT count(*) FROM albums
                         WHERE weeks_first_year NOT BETWEEN 1 AND 52
                            OR debut_pos NOT BETWEEN 1 AND 50
                            OR week2_pos NOT BETWEEN 1 AND 201
                            OR debut_week > DATE '2025-10-18'""").fetchone()[0]
    assert bad == 0


def test_trajectories_have_13_weeks_per_album(con):
    counts = con.execute("""SELECT DISTINCT count(*) FROM album_trajectories
                            GROUP BY title, performer""").fetchall()
    assert counts == [(13,)]
    first = con.execute("SELECT max(pos) FROM album_trajectories WHERE week_index = 0").fetchone()[0]
    assert first <= 10


def test_yearly_share_is_a_percentage(con):
    lo, hi = con.execute("SELECT min(kpop_share_pct), max(kpop_share_pct) FROM yearly_presence").fetchone()
    assert 0 <= lo <= hi < 100
