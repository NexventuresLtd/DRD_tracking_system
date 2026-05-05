# app/seed.py
import asyncio
from app.database import async_session, init_db
from app.models.user import User, UserRole
from app.models.team import Team, TeamMember
from app.utils.security import hash_password

async def seed_data():
    """Seed initial data"""
    await init_db()
    
    async with async_session() as db:
        try:
            # Check if admin exists
            from sqlalchemy import select
            result = await db.execute(
                select(User).where(User.username == "admin")
            )
            if result.scalar_one_or_none():
                print("Admin user already exists, skipping seed")
                return
            
            # Create admin user
            admin = User(
                email="admin@drd-system.com",
                username="admin",
                hashed_password=hash_password("Admin123!"),
                full_name="System Administrator",
                role=UserRole.SUPER_ADMIN,
                is_active=True,
                is_verified=True,
            )
            db.add(admin)
            
            # Create commander
            commander = User(
                email="commander@drd-system.com",
                username="commander",
                hashed_password=hash_password("Commander123!"),
                full_name="Field Commander",
                role=UserRole.COMMANDER,
                is_active=True,
                is_verified=True,
            )
            db.add(commander)
            
            # Create operator
            operator = User(
                email="operator@drd-system.com",
                username="operator",
                hashed_password=hash_password("Operator123!"),
                full_name="Field Operator",
                role=UserRole.OPERATOR,
                is_active=True,
                is_verified=True,
            )
            db.add(operator)
            
            # Create viewer
            viewer = User(
                email="viewer@drd-system.com",
                username="viewer",
                hashed_password=hash_password("Viewer123!"),
                full_name="Viewer User",
                role=UserRole.VIEWER,
                is_active=True,
                is_verified=True,
            )
            db.add(viewer)
            
            await db.flush()
            
            # Create teams
            teams_data = [
                {"name": "Team Alpha", "code": "ALPHA", "color": "#22c55e", "description": "Primary assault team", "lead_id": commander.id},
                {"name": "Team Bravo", "code": "BRAVO", "color": "#f59e0b", "description": "Support and recon team", "lead_id": operator.id},
                {"name": "Team Charlie", "code": "CHRLIE", "color": "#ef4444", "description": "Medical and extraction", "lead_id": operator.id},
                {"name": "Team Delta", "code": "DELTA", "color": "#8b5cf6", "description": "Logistics and supply", "lead_id": commander.id},
                {"name": "Team Echo", "code": "ECHO", "color": "#06b6d4", "description": "Communications and tech", "lead_id": operator.id},
            ]
            
            for team_data in teams_data:
                team = Team(**team_data)
                db.add(team)
                await db.flush()
                
                # Add admin to first team
                if team_data["name"] == "Team Alpha":
                    member = TeamMember(
                        team_id=team.id,
                        user_id=admin.id,
                        role="lead",
                    )
                    db.add(member)
            
            # Create field units
            field_unit_data = [
                {"username": "field_alpha1", "full_name": "Alpha Operator 1", "team": "Team Alpha", "role": "lead"},
                {"username": "field_alpha2", "full_name": "Alpha Medic", "team": "Team Alpha", "role": "medic"},
                {"username": "field_bravo1", "full_name": "Bravo Scout", "team": "Team Bravo", "role": "scout"},
                {"username": "field_charlie1", "full_name": "Charlie Lead", "team": "Team Charlie", "role": "lead"},
                {"username": "field_delta1", "full_name": "Delta Support", "team": "Team Delta", "role": "support"},
                {"username": "field_echo1", "full_name": "Echo Tech", "team": "Team Echo", "role": "sniper"},
            ]
            
            for unit_data in field_unit_data:
                # Find team
                team_result = await db.execute(
                    select(Team).where(Team.name == unit_data["team"])
                )
                team = team_result.scalar_one_or_none()
                
                if team:
                    user = User(
                        email=f"{unit_data['username']}@field.drd-system.com",
                        username=unit_data["username"],
                        hashed_password=hash_password("Field123!"),
                        full_name=unit_data["full_name"],
                        role=UserRole.FIELD_UNIT,
                        is_active=True,
                        is_verified=True,
                    )
                    db.add(user)
                    await db.flush()
                    
                    member = TeamMember(
                        team_id=team.id,
                        user_id=user.id,
                        role=unit_data["role"],
                    )
                    db.add(member)
            
            await db.commit()
            print("Seed data created successfully!")
            print("\nTest Accounts:")
            print("Admin: admin / Admin123!")
            print("Commander: commander / Commander123!")
            print("Operator: operator / Operator123!")
            print("Viewer: viewer / Viewer123!")
            print("Field Units: field_alpha1 ... / Field123!")
            
        except Exception as e:
            await db.rollback()
            print(f"Error seeding data: {e}")
            raise

if __name__ == "__main__":
    asyncio.run(seed_data())