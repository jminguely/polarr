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

### Synology NAS Deployment (Container Manager)

If you are deploying on a Synology NAS using Container Manager, you can create a Project using `docker-compose`.

1. Open **Container Manager** > **Project** > **Create**.
2. Give it a name (e.g., `polarr`) and select a path on your NAS where you want to store the data (e.g., `/docker/polarr`).
3. Under **Source**, choose **Create docker-compose.yml**.
4. Paste the following configuration, replacing the environment variables with your actual values (no `.env` file needed, they are bundled in the compose file for simplicity on Synology):

```yaml
services:
  polarr:
    image: ghcr.io/YOUR_GITHUB_USERNAME/polarr:main
    container_name: polarr
    ports:
      - "8080:8080"
    volumes:
      - ./data:/app/data
    environment:
      - ABS_URL=http://your-abs-host:13378
      - ABS_TOKEN=your-abs-api-token
      - ABS_LIBRARY_ID=your-podcast-library-id
      - PODCASTINDEX_API_KEY=
      - PODCASTINDEX_API_SECRET=
      - POLARR_EXTERNAL_URL=http://your-synology-ip:8080
    restart: unless-stopped
```

5. Click **Next** and proceed to build and start the project.

> **Note:** The `image` path assumes you have pushed the Docker image to GitHub Container Registry using the provided GitHub Actions workflow. Replace `YOUR_GITHUB_USERNAME` with your actual username.

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
