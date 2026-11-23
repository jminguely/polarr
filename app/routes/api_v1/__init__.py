from fastapi import APIRouter, Depends
from ...core.auth import require_api_auth

from .podcasts import router as podcasts_router
from .inbox import router as inbox_router
from .journal import router as journal_router
from .queue import router as queue_router
from .search import router as search_router
from .sync import router as sync_router
from .stats import router as stats_router
from .playlists import router as playlists_router

router = APIRouter(prefix="/api/v1", dependencies=[Depends(require_api_auth)])

router.include_router(podcasts_router)
router.include_router(inbox_router)
router.include_router(journal_router)
router.include_router(queue_router)
router.include_router(search_router)
router.include_router(sync_router)
router.include_router(stats_router)
router.include_router(playlists_router)
