import uuid
from datetime import datetime
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user, require_role
from app.models.user import User, UserRole
from app.models.post import Post, FacilityType, FacilityStatus, FacilityVisibility

router = APIRouter(prefix="/posts", tags=["Posts & Facilities"])

COORDINATOR = UserRole.operations_coordinator
PLANNING = UserRole.planning_officer
TEAM_LEADER = UserRole.team_leader
FIELD = UserRole.field_user


# ── Schemas ────────────────────────────────────────────────────────────────

class PostCreate(BaseModel):
    name: str
    facility_type: FacilityType
    description: Optional[str] = None
    mission: Optional[str] = None
    latitude: float
    longitude: float
    address: Optional[str] = None
    region: Optional[str] = None
    status: FacilityStatus = FacilityStatus.active
    visibility: FacilityVisibility = FacilityVisibility.all_personnel
    capacity: Optional[int] = None
    commander_name: Optional[str] = None
    contact_info: Optional[str] = None
    classification: str = "restricted"
    allowed_team_ids: Optional[List[str]] = None


class PostUpdate(BaseModel):
    name: Optional[str] = None
    facility_type: Optional[FacilityType] = None
    description: Optional[str] = None
    mission: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    address: Optional[str] = None
    region: Optional[str] = None
    status: Optional[FacilityStatus] = None
    visibility: Optional[FacilityVisibility] = None
    capacity: Optional[int] = None
    commander_name: Optional[str] = None
    contact_info: Optional[str] = None
    classification: Optional[str] = None
    allowed_team_ids: Optional[List[str]] = None


class GrantAccessRequest(BaseModel):
    user_id: str


def _can_edit(post: Post, user: User) -> bool:
    if user.role == COORDINATOR:
        return True
    if user.role == PLANNING:
        editor_ids = post.editor_ids or []
        return str(user.id) in editor_ids
    return False


def _can_view(post: Post, user: User) -> bool:
    if user.role in (COORDINATOR, PLANNING):
        return True
    if not post.is_published:
        return False
    if post.visibility == FacilityVisibility.planning_only:
        return False
    if post.visibility == FacilityVisibility.all_personnel:
        return True
    # assigned_teams — check via team membership (simplified: pass team_ids list)
    return True


def _serialize(post: Post, user: User) -> dict:
    return {
        "id": str(post.id),
        "name": post.name,
        "facility_type": post.facility_type.value,
        "description": post.description,
        "mission": post.mission,
        "latitude": post.latitude,
        "longitude": post.longitude,
        "address": post.address,
        "region": post.region,
        "status": post.status.value,
        "is_published": post.is_published,
        "visibility": post.visibility.value,
        "capacity": post.capacity,
        "commander_name": post.commander_name,
        "contact_info": post.contact_info,
        "classification": post.classification,
        "allowed_team_ids": post.allowed_team_ids or [],
        "editor_ids": post.editor_ids or [] if user.role == COORDINATOR else None,
        "can_edit": _can_edit(post, user),
        "created_by": str(post.created_by) if post.created_by else None,
        "created_at": post.created_at.isoformat() if post.created_at else None,
        "updated_at": post.updated_at.isoformat() if post.updated_at else None,
    }


# ── Endpoints ──────────────────────────────────────────────────────────────

@router.get("")
async def list_posts(
    facility_type: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    published_only: bool = Query(False),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = select(Post)

    # Field users and team leaders only see published posts they have access to
    if user.role in (TEAM_LEADER, FIELD):
        q = q.where(Post.is_published == True).where(
            Post.visibility != FacilityVisibility.planning_only
        )
    elif published_only:
        q = q.where(Post.is_published == True)

    if facility_type:
        q = q.where(Post.facility_type == facility_type)
    if status:
        q = q.where(Post.status == status)

    result = await db.execute(q.order_by(Post.created_at.desc()))
    posts = result.scalars().all()
    return [_serialize(p, user) for p in posts if _can_view(p, user)]


@router.post("", status_code=201)
async def create_post(
    data: PostCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role not in (COORDINATOR, PLANNING):
        raise HTTPException(403, "Insufficient permissions")
    if user.role == PLANNING:
        # Planning officers can only create if they have a global editor grant
        # (granted by coordinator via /posts/grant-global-access — simplified: check flag)
        # For now, planning officers can create — coordinator controls publish
        pass

    post = Post(
        name=data.name,
        facility_type=data.facility_type,
        description=data.description,
        mission=data.mission,
        latitude=data.latitude,
        longitude=data.longitude,
        address=data.address,
        region=data.region,
        status=data.status,
        visibility=data.visibility,
        capacity=data.capacity,
        commander_name=data.commander_name,
        contact_info=data.contact_info,
        classification=data.classification,
        allowed_team_ids=data.allowed_team_ids,
        created_by=user.id,
    )
    db.add(post)
    await db.commit()
    await db.refresh(post)
    return _serialize(post, user)


@router.get("/{post_id}")
async def get_post(
    post_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(404, "Post not found")
    if not _can_view(post, user):
        raise HTTPException(403, "Access denied")
    return _serialize(post, user)


@router.put("/{post_id}")
async def update_post(
    post_id: uuid.UUID,
    data: PostUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(404, "Post not found")
    if not _can_edit(post, user):
        raise HTTPException(403, "You don't have edit access to this post")

    for field, value in data.model_dump(exclude_none=True).items():
        setattr(post, field, value)
    post.updated_by = user.id
    post.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(post)
    return _serialize(post, user)


@router.delete("/{post_id}", status_code=204)
async def delete_post(
    post_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role(COORDINATOR)),
):
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(404, "Post not found")
    await db.delete(post)
    await db.commit()


@router.post("/{post_id}/publish")
async def toggle_publish(
    post_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role(COORDINATOR)),
):
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(404, "Post not found")
    post.is_published = not post.is_published
    post.updated_at = datetime.utcnow()
    await db.commit()
    return {"is_published": post.is_published}


@router.post("/{post_id}/grant-access")
async def grant_edit_access(
    post_id: uuid.UUID,
    body: GrantAccessRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role(COORDINATOR)),
):
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(404, "Post not found")

    editors = list(post.editor_ids or [])
    if body.user_id not in editors:
        editors.append(body.user_id)
    post.editor_ids = editors
    await db.commit()
    return {"editor_ids": post.editor_ids}


@router.delete("/{post_id}/grant-access/{user_id}")
async def revoke_edit_access(
    post_id: uuid.UUID,
    user_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role(COORDINATOR)),
):
    result = await db.execute(select(Post).where(Post.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(404, "Post not found")

    post.editor_ids = [e for e in (post.editor_ids or []) if e != user_id]
    await db.commit()
    return {"editor_ids": post.editor_ids}


@router.get("/map/published")
async def map_posts(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Lightweight endpoint for map display — returns only location + type."""
    if user.role in (TEAM_LEADER, FIELD):
        q = select(Post).where(Post.is_published == True).where(
            Post.visibility != FacilityVisibility.planning_only
        )
    else:
        q = select(Post)

    result = await db.execute(q)
    posts = result.scalars().all()
    return [
        {
            "id": str(p.id),
            "name": p.name,
            "facility_type": p.facility_type.value,
            "status": p.status.value,
            "latitude": p.latitude,
            "longitude": p.longitude,
            "is_published": p.is_published,
            "classification": p.classification,
            "description": p.description,
            "mission": p.mission,
        }
        for p in posts if _can_view(p, user)
    ]
