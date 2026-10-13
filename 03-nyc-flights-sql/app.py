"""Interactive dashboard:  streamlit run app.py"""

import duckdb
import plotly.express as px
import streamlit as st

from build_db import DB_PATH, build

st.set_page_config(page_title="NYC Flight Delays 2013", layout="wide")


@st.cache_resource
def connect():
    if not DB_PATH.exists():
        build()
    return duckdb.connect(str(DB_PATH), read_only=True)


con = connect()

# ---- Filters -------------------------------------------------------------------
st.sidebar.header("Filters")
airports = st.sidebar.multiselect("Departure airport", ["EWR", "JFK", "LGA"], default=["EWR", "JFK", "LGA"])
airline_options = con.execute(
    "SELECT DISTINCT airline FROM flights_enriched ORDER BY airline").df()["airline"].tolist()
airlines = st.sidebar.multiselect("Airline", airline_options, default=airline_options)
months = st.sidebar.slider("Months", 1, 12, (1, 12))

if not airports or not airlines:
    st.warning("Select at least one airport and one airline.")
    st.stop()

WHERE = "origin IN (SELECT unnest($airports)) AND airline IN (SELECT unnest($airlines)) AND month BETWEEN $m1 AND $m2"
params = {"airports": airports, "airlines": airlines, "m1": months[0], "m2": months[1]}


def q(sql: str):
    return con.execute(sql.replace("{where}", WHERE), params).df()


# ---- KPIs ----------------------------------------------------------------------
st.title("NYC departures, 2013: where and why flights run late")
k = q("""SELECT count(*) AS flights, avg(on_time::INT) AS on_time, avg(cancelled::INT) AS cancelled,
                avg(dep_delay) AS dep_delay
         FROM flights_enriched WHERE {where}""").iloc[0]
c1, c2, c3, c4 = st.columns(4)
c1.metric("Scheduled flights", f"{int(k.flights):,}")
c2.metric("On time (≤ 15 min late)", f"{k.on_time:.1%}")
c3.metric("Cancelled", f"{k.cancelled:.1%}")
c4.metric("Avg departure delay", f"{k.dep_delay:.1f} min")

# ---- Charts --------------------------------------------------------------------
left, right = st.columns(2)

by_hour = q("""SELECT hour, avg(dep_delay) AS avg_dep_delay, count(*) AS flights
               FROM flights_enriched WHERE {where} AND hour BETWEEN 5 AND 23
               GROUP BY hour ORDER BY hour""")
left.plotly_chart(px.bar(by_hour, x="hour", y="avg_dep_delay",
                         labels={"hour": "Scheduled hour", "avg_dep_delay": "Avg departure delay (min)"},
                         title="Delays build up through the day"), use_container_width=True)

by_month = q("""SELECT month, avg(on_time::INT) AS on_time FROM flights_enriched
                WHERE {where} GROUP BY month ORDER BY month""")
right.plotly_chart(px.line(by_month, x="month", y="on_time", markers=True,
                           labels={"month": "Month", "on_time": "On-time rate"},
                           title="On-time rate by month").update_yaxes(tickformat=".0%"),
                   use_container_width=True)

by_airline = q("""SELECT airline, count(*) AS flights, avg(on_time::INT) AS on_time
                  FROM flights_enriched WHERE {where}
                  GROUP BY airline HAVING count(*) >= 100 ORDER BY on_time""")
left.plotly_chart(px.bar(by_airline, x="on_time", y="airline", orientation="h", hover_data=["flights"],
                         labels={"on_time": "On-time rate", "airline": ""},
                         title="Airlines (100+ flights)").update_xaxes(tickformat=".0%"),
                  use_container_width=True)

routes = q("""SELECT origin || '-' || dest AS route, any_value(dest_name) AS destination,
                     count(*) AS flights, round(100 * avg(on_time::INT), 1) AS on_time_pct,
                     round(avg(arr_delay), 1) AS avg_arr_delay_min
              FROM flights_enriched WHERE {where}
              GROUP BY origin, dest HAVING count(*) >= 100
              ORDER BY on_time_pct LIMIT 15""")
right.subheader("Least punctual routes (100+ flights)")
right.dataframe(routes, hide_index=True, use_container_width=True)

st.caption("Data: nycflights13 (US Bureau of Transportation Statistics and Iowa Environmental Mesonet), "
           "all 336,776 scheduled departures from EWR, JFK and LGA in 2013.")
