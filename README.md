# 🐻‍❄️ Polarr

A self-hosted podcast subscription manager that works as a companion to [Audiobookshelf](https://www.audiobookshelf.org/) (ABS). Polarr tracks your listening history, auto-cleans listened episodes from ABS to save disk space, and provides filtered proxy RSS feeds.

## What It Does

- **Subscription management** — Subscribe/unsubscribe from podcasts, synced with Audiobookshelf
- **Listening history** — Automatically tracks finished episodes via ABS webhooks and background polling
- **Auto-cleanup** — Deletes listened episode files from ABS to free disk space
- **Proxy RSS feeds** — Serves filtered RSS feeds with already-listened episodes removed (useful for podcast apps that don't support ABS)
- **Metadata enrichment** — Resolves podcast/episode titles via PodcastIndex API or direct RSS parsing

## Architecture

```
┌──────────────┐   webhook    ┌──────────┐   API calls   ┌──────────────────┐
│ Audiobookshelf├────────────►│  Polarr  ├──────────────►│  Audiobookshelf  │
│   (player)   │              │ (FastAPI) │               │   (API server)   │
└──────────────┘              └────┬─────┘               └──────────────────┘
                                   │
                              ┌────┴─────┐
                              │ SQLite   │
                              │ (history)│
                              └──────────┘
```

### Key Flows

1. **Webhook flow** — ABS sends a webhook when an episode finishes → Polarr logs it to history → queues the episode file for deletion from ABS
2. **Background sync** — Every 5 minutes, Polarr polls `GET /api/me` on ABS to catch any finished episodes (>95% progress) that the webhook might have missed
3. **Proxy feed** — `GET /feed/{podcast_id}` fetches the original RSS, parses the XML, removes `<item>` entries whose GUID matches a played episode, and returns the cleaned feed
4. **Subscribe/Unsubscribe** — Toggling a subscription creates or hard-deletes the podcast in ABS via its API, then marks historical episodes as finished

## Setup

### Environment Variables

| Variable | Description | Required |
|---|---|---|
| `ABS_URL` | Audiobookshelf base URL (e.g. `http://myserver:13378/audiobookshelf`) | ✅ |
| `ABS_TOKEN` | ABS API token (get from ABS user settings) | ✅ |
| `ABS_LIBRARY_ID` | ABS podcast library UUID | ✅ |
| `PODCASTINDEX_API_KEY` | PodcastIndex API key (for metadata enrichment) | Optional |
| `PODCASTINDEX_API_SECRET` | PodcastIndex API secret | Optional |
| `POLARR_EXTERNAL_URL` | External URL where Polarr is reachable (for proxy feed URLs) | Optional |
| `DATABASE_URL` | SQLAlchemy DB URL (defaults to `sqlite:///data/polarr.db`) | Optional |

### Docker (Recommended)

```bash
# Clone and configure
cp .env.example .env  # Edit with your values

# Run
docker compose up -d
```

Polarr will be available at `http://localhost:8080`.

### Local Development

```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env  # Edit with your values

# Run with hot-reload
./run.sh
```

### ABS Webhook Configuration

In Audiobookshelf, go to **Settings → Notifications** and add a webhook:
- **URL**: `http://<polarr-host>:8080/webhook/abs`
- **Events**: `item_finished`, `progress_update`

## Tech Stack

- **Backend**: Python 3.11, FastAPI, Uvicorn
- **Database**: SQLite via SQLAlchemy
- **Templates**: Jinja2 with TailwindCSS (CDN)
- **RSS parsing**: feedparser + lxml
- **APIs**: Audiobookshelf REST API, PodcastIndex API
