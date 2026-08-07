"""UI Service: shows the page and calls Backend only after form submission."""

import math
import os
from datetime import timedelta

import requests
from dotenv import load_dotenv
from flask import Flask, redirect, render_template, request, session, url_for
from flask_session import Session
from redis import Redis
from redis.exceptions import RedisError


load_dotenv()

API_URL = os.getenv("API_SERVICE_URL", "http://127.0.0.1:8000")
SERVICE_HOST = os.getenv("SERVICE_HOST", "127.0.0.1")
SERVICE_PORT = int(os.getenv("SERVICE_PORT", "5000"))
REDIS_URL = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")
SESSION_LIFETIME_DAYS = int(os.getenv("SESSION_LIFETIME_DAYS", "30"))
redis_client = Redis.from_url(REDIS_URL)

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.getenv(
        "FLASK_SECRET_KEY",
        "local-development-secret-key",
    ),
    SESSION_TYPE="redis",
    SESSION_REDIS=redis_client,
    SESSION_PERMANENT=True,
    SESSION_USE_SIGNER=True,
    SESSION_KEY_PREFIX="wildlife:session:",
    PERMANENT_SESSION_LIFETIME=timedelta(days=SESSION_LIFETIME_DAYS),
    SESSION_COOKIE_SECURE=True,
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
)
Session(app)

CHART_COLORS = [
    "#1f654f",
    "#c58b37",
    "#5377a5",
    "#a95d68",
    "#7b6aa8",
    "#5f8e62",
    "#d0663f",
    "#3b8f91",
]


@app.before_request
def keep_session_alive() -> None:
    """Renew the Redis session lifetime whenever this browser returns."""

    session.permanent = True


def sector_clip_path(start_percentage: float, end_percentage: float) -> str:
    """Return a polygon that follows one clockwise pie-chart sector."""

    start_angle = start_percentage * 3.6 - 90
    end_angle = end_percentage * 3.6 - 90
    angle_span = max(end_angle - start_angle, 0)
    steps = max(1, math.ceil(angle_span / 6))
    angles = [
        start_angle + angle_span * step / steps
        for step in range(steps + 1)
    ]
    points = ["50% 50%"]
    for angle in angles:
        radians = math.radians(angle)
        x = 50 + 50 * math.cos(radians)
        y = 50 + 50 * math.sin(radians)
        points.append(f"{x:.2f}% {y:.2f}%")

    return f"polygon({', '.join(points)})"


def prepare_changes(changes: list[dict]) -> list[dict]:
    """Prepare timestamps and signed values for the HTML template."""

    for item in changes:
        timestamp = str(item.get("changed_at", ""))
        item["display_time"] = timestamp[:16].replace("T", " ")

        amount = int(item.get("change_amount", 0))
        formatted = f"{abs(amount):,}".replace(",", " ")
        item["display_change"] = f"+{formatted}" if amount > 0 else f"-{formatted}"
        item["change_class"] = "increase" if amount > 0 else "decrease"

    return changes


def prepare_chart(items: list[dict]) -> dict:
    """Calculate percentages and a CSS conic-gradient for a pie chart."""

    total = sum(int(item.get("observation_count", 0)) for item in items)
    chart_items = []
    segments = []
    position = 0.0

    for index, source_item in enumerate(items):
        item = dict(source_item)
        count = int(item.get("observation_count", 0))
        percentage = (count / total * 100) if total else 0
        color = CHART_COLORS[index % len(CHART_COLORS)]
        end_position = position + percentage

        item["percentage"] = round(percentage, 1)
        item["color"] = color
        item["clip_path"] = sector_clip_path(position, end_position)
        chart_items.append(item)
        segments.append(
            f"{color} {position:.2f}% {end_position:.2f}%"
        )
        position = end_position

    gradient = ", ".join(segments) if total else "#d7ded8 0% 100%"
    return {
        "entries": chart_items,
        "total": total,
        "gradient": gradient,
    }


@app.route("/", methods=["GET", "POST"])
def index():
    """Search on POST, then redirect so browser refresh repeats only GET."""

    if request.method == "POST":
        search_name = request.form.get("animal_name", "").strip()
        page = {
            "result": None,
            "error": None,
            "suggestions": [],
            "search_name": search_name,
        }

        if len(search_name) < 2:
            page["error"] = "Введіть назву тварини щонайменше з двох символів."
        else:
            try:
                response = requests.get(
                    f"{API_URL}/animals/search",
                    params={"name": search_name},
                    timeout=25,
                )

                if response.status_code in (404, 422):
                    detail = response.json().get("detail", "Тварину не знайдено.")
                    if isinstance(detail, dict):
                        page["error"] = detail.get(
                            "message",
                            "Тварину не знайдено.",
                        )
                        page["suggestions"] = detail.get("suggestions", [])
                    else:
                        page["error"] = detail
                else:
                    response.raise_for_status()
                    page["result"] = response.json()
            except requests.Timeout:
                page["error"] = "Сервер відповідає надто довго. Спробуйте ще раз."
            except (requests.RequestException, ValueError):
                page["error"] = "Не вдалося отримати дані. Спробуйте пізніше."

        # Flask stores this result in Redis and only a session ID in the cookie.
        # The 303 redirect changes POST into GET, so F5 cannot repeat the search.
        session.pop("chart_page", None)
        session["search_page"] = page
        session["active_view"] = "search"
        return redirect(url_for("index", view="search"), code=303)

    requested_view = request.args.get("view", "")
    view = (
        requested_view
        if requested_view in {"search", "compare"}
        else session.get("active_view", "")
    )
    page = session.get("search_page", {}) if view == "search" else {}
    chart_page = session.get("chart_page", {}) if view == "compare" else {}

    result = page.get("result")
    changes = prepare_changes(result.get("changes", [])) if result else []
    comparison = chart_page.get("comparison")
    chart = (
        prepare_chart(comparison.get("items", []))
        if comparison
        else None
    )

    return render_template(
        "index.html",
        result=result,
        error=page.get("error"),
        suggestions=page.get("suggestions", []),
        changes=changes,
        search_name=page.get("search_name", ""),
        has_searched=bool(page),
        chart=chart,
        chart_meaning=(
            comparison.get("meaning") if comparison else None
        ),
        chart_names=chart_page.get("chart_names", ""),
        chart_error=chart_page.get("error"),
        chart_suggestions=chart_page.get("suggestions", []),
        theme=session.get("theme", "light"),
    )


@app.post("/compare")
def compare_animals():
    """Request one GBIF comparison only after the user submits species."""

    raw_names = request.form.get("animal_names", "").strip()
    names = [
        name.strip()
        for name in raw_names.replace("\n", ",").split(",")
        if name.strip()
    ]
    page = {
        "comparison": None,
        "error": None,
        "suggestions": [],
        "chart_names": raw_names,
    }

    if not 2 <= len(names) <= 8:
        page["error"] = "Введіть від двох до восьми видів через кому."
    else:
        try:
            response = requests.post(
                f"{API_URL}/animals/compare",
                json={"names": names},
                timeout=90,
            )
            if response.status_code in (404, 422):
                detail = response.json().get(
                    "detail",
                    "Не вдалося порівняти вибрані види.",
                )
                if isinstance(detail, dict):
                    page["error"] = detail.get(
                        "message",
                        "Не вдалося порівняти вибрані види.",
                    )
                    page["suggestions"] = detail.get("suggestions", [])
                else:
                    page["error"] = detail
            else:
                response.raise_for_status()
                page["comparison"] = response.json()
        except requests.Timeout:
            page["error"] = "Порівняння триває надто довго."
        except (requests.RequestException, ValueError):
            page["error"] = "Не вдалося отримати дані для діаграми."

    session.pop("search_page", None)
    session["chart_page"] = page
    session["active_view"] = "compare"
    return redirect(url_for("index", view="compare"), code=303)


@app.post("/theme")
def change_theme():
    """Save this browser's light or dark preference in Redis."""

    selected_theme = request.form.get("theme", "light")
    session["theme"] = (
        selected_theme if selected_theme in {"light", "dark"} else "light"
    )
    next_view = session.get("active_view", "")
    return redirect(
        url_for("index", view=next_view) if next_view else url_for("index"),
        code=303,
    )


@app.get("/health")
def health() -> dict:
    """Report whether UI can use its Redis session dependency."""

    try:
        redis_client.ping()
    except RedisError as error:
        return {"status": "error", "redis": str(error)}, 503
    return {"status": "ok", "redis": "ok"}


if __name__ == "__main__":
    app.run(host=SERVICE_HOST, port=SERVICE_PORT, debug=False)
