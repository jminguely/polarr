# Polarr — Agent Guidelines

## Project Overview

Polarr is a self-hosted podcast subscription manager that acts as a companion to **Audiobookshelf (ABS)**. It tracks listening history, auto-deletes listened episodes, and provides filtered proxy RSS feeds.

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Python 3.11, FastAPI, Uvicorn |
| Database | SQLite via SQLAlchemy (ORM) |
| Templates | Jinja2 + TailwindCSS (CDN via `cdn.tailwindcss.com`) |
| RSS parsing | `feedparser` (reading) + `lxml` (XML manipulation for proxy feeds) |
| External APIs | Audiobookshelf REST API, PodcastIndex API |
| Deployment | Docker / docker-compose |

## Project Structure

```
polarr/
├── app/
│   ├── core/            # Config, auth session/API keys, logger with auto-pruning
│   ├── database.py      # DB engine, session factory, get_db dependency, migrations
│   ├── models.py        # SQLAlchemy models: Podcast (with artwork), PlayHistory, SyncLog, SystemLog
│   ├── routes/          # Modular API & HTML routes: auth, podcasts, webhooks, feeds, discover, history, settings, system_logs
│   ├── services/        # Business logic: abs_client, podcastindex, feed_parser, sync_service
│   ├── static/          # Compiled Tailwind CSS (tailwind.min.css, input.css)
│   ├── templates/       # Jinja2 HTML templates (*arr dark theme with Lucide SVGs)
│   └── main.py          # App factory, lifespan background tasks, router mounting
├── data/                # SQLite database (polarr.db), gitignored
├── scripts/             # One-off migration/debug scripts (not part of the app)
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── run.sh               # Local dev launcher (venv + .env + uvicorn --reload)
└── .env                 # Environment variables (never commit secrets)
```

## Key Architecture Decisions

### Audiobookshelf is the audio player, Polarr is the history tracker
- ABS manages podcast files and playback
- Polarr manages subscriptions, history, and cleanup
- Polarr talks to ABS via its REST API (auth via Bearer token)

### Two mechanisms catch finished episodes
1. **Webhook** (`POST /webhook/abs`) — ABS pushes `item_finished` / `progress_update` events
2. **Background polling** (`sync_abs_progress()`) — Every 5 minutes, polls `GET /api/me` for episodes with >95% progress

### Proxy feed filters out listened episodes
- `GET /feed/{podcast_id}` fetches the upstream RSS XML, parses with lxml, removes `<item>` elements whose GUID matches a played episode, returns the cleaned XML

### Subscribe/Unsubscribe syncs with ABS
- **Subscribe**: Creates the podcast in ABS via `POST /api/podcasts`, marks historical episodes as finished, triggers episode scan
- **Unsubscribe**: Hard-deletes the podcast from ABS via `DELETE /api/items/{id}?hard=1`

## Integration Contracts & Gotchas

### ABS API endpoints used
| Endpoint | Purpose |
|---|---|
| `GET /api/me` | Fetch user's media progress for background sync |
| `GET /api/libraries/{id}` | Get library folder info for podcast creation |
| `POST /api/podcasts/feed` | Parse an RSS feed URL to get podcast metadata |
| `POST /api/podcasts` | Create a new podcast in ABS |
| `GET /api/podcasts/{id}/checknew` | Trigger ABS to check for new episodes |
| `PATCH /api/me/progress/{id}` | Mark an episode as finished in ABS |
| `PATCH /api/items/{id}/media` | Reset episode check timestamp |
| `DELETE /api/items/{id}?hard=1` | Hard-delete a podcast and all its files |
| `DELETE /api/podcasts/{id}/episode/{epId}?hard=1` | Delete a specific episode file |

### PodcastIndex API
- Auth uses HMAC-SHA1: `sha1(api_key + api_secret + unix_timestamp)`
- Headers: `X-Auth-Key`, `X-Auth-Date`, `Authorization` (the SHA1 hash)
- Used for podcast title resolution and episode title matching

### Known dependency issue
- `lxml` is used in the codebase (proxy feed XML parsing) but is **missing from `requirements.txt`** — it must be added

## Coding Conventions

### UI Language
- The UI is being transitioned to **English**. New UI strings should be written in English. Existing French strings should be migrated to English when touched.

### Code style
- Python code uses standard PEP 8
- Templates use TailwindCSS utility classes (loaded via CDN)
- Error feedback currently uses `alert()` via inline `<script>` tags — this should be replaced with proper toast notifications (see Roadmap)

### Recommended refactoring direction
The current `main.py` is a monolith (~370 lines). If adding significant features, split into:
```
app/
├── routes/
│   ├── podcasts.py     # CRUD, detail, toggle
│   ├── webhooks.py     # ABS webhook handler
│   ├── feeds.py        # Proxy RSS feed
│   └── history.py      # History page
├── services/
│   ├── abs_client.py   # All ABS API interactions
│   ├── podcastindex.py # PodcastIndex API client
│   └── sync.py         # Background sync task
├── models.py
├── database.py
└── main.py             # App factory, startup events, router includes
```

## Roadmap / Future Ideas

These are features the owner is interested in. Use this context when making design decisions:

1. **Search** — Search podcasts by title or feed URL within Polarr
2. **Better error handling** — Replace `alert()` JS popups with proper toast/notification UI (e.g. using a lightweight JS library or custom CSS notifications)
3. **Tests** — Add pytest unit and integration tests (mock the ABS API)
4. **Statistics & insights** — Listening stats dashboard: episodes per week, total listened, per-podcast breakdowns
5. **Podcast discovery** — Browse/search PodcastIndex directly from Polarr to add new podcasts without needing to know the RSS URL
