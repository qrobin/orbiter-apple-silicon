#include "OrbiterExhaust.h"
#include "OrbiterCore.h"
THIRD_PARTY_INCLUDES_START
#include "Exhaust.h"
#include "Aerodynamics.h"
THIRD_PARTY_INCLUDES_END
#include "ProceduralMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "Components/PointLightComponent.h"
static constexpr int32 MaxParticles=1536;
static FVector U(const Vector &V){return FVector(V.z,V.x,V.y);}
AOrbiterExhaust::AOrbiterExhaust(){
    Mesh=CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("SoftExhaustParticles"));RootComponent=Mesh;
    Glow=CreateDefaultSubobject<UPointLightComponent>(TEXT("EngineGlow"));Glow->SetupAttachment(Mesh);Glow->SetLightColor(FLinearColor(.25,.5,1));Glow->SetAttenuationRadius(1000);Glow->SetCastShadows(false);
    Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);Mesh->SetCastShadow(false);Mesh->SetCanEverAffectNavigation(false);
}
void AOrbiterExhaust::BeginPlay(){
    Super::BeginPlay();Vertices.SetNumZeroed(MaxParticles*4);Normals.Init(FVector(0,0,1),Vertices.Num());Colors.Init(FLinearColor::Transparent,Vertices.Num());
    TArray<int32> Indices;TArray<FProcMeshTangent> Tangents;
    for(int32 I=0;I<MaxParticles;++I){int32 V=I*4;Indices.Append({V,V+1,V+2,V,V+2,V+3});UV.Append({FVector2D(0,0),FVector2D(1,0),FVector2D(1,1),FVector2D(0,1)});}
    Mesh->CreateMeshSection_LinearColor(0,Vertices,Indices,Normals,UV,Colors,Tangents,false);
    if(auto *M=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/Materials/M_Exhaust.M_Exhaust")))Mesh->SetMaterial(0,M);
}
void AOrbiterExhaust::Update(const native::Flight &F,const FVector &Camera){
    double DT=PreviousTime<0?0:F.elapsed-PreviousTime;PreviousTime=F.elapsed;
    if(DT<0||DT>.5){Particles.Reset();FMemory::Memzero(Credit);DT=0;}
    FVector Origin=U(F.position),Velocity=U(F.velocity);
    auto World=[&](const Vector &V){return U(F.right*V.x+F.up*V.y+F.forward*V.z);};
    auto Emitters=native::gliderExhaust(F);
    Glow->SetIntensity(F.glider.mainLevel*12000);Glow->SetWorldLocation(World(Vector(0,0,-9))*100);
    for(int32 I=Particles.Num()-1;I>=0;--I){auto &P=Particles[I];P.Age+=DT;if(P.Age>P.Life){Particles.RemoveAtSwap(I,1,EAllowShrinking::No);continue;}P.Position+=P.Velocity*DT;}
    for(int32 I=0;I<int32(Emitters.size())&&I<32;++I){
        const auto &E=Emitters[I];auto Shape=native::plumeShape(F.altitude(),E.kind);const bool Rcs=E.kind==native::ExhaustKind::Rcs;
        double Count=(Rcs?1600:1800)*E.level*DT+Credit[I];int32 Spawn=FMath::FloorToInt(Count);Credit[I]=Count-Spawn;
        FVector Direction=World(E.direction),Side=FVector::CrossProduct(Direction,FVector(0,0,1)).GetSafeNormal();if(Side.IsNearlyZero())Side=FVector(1,0,0);
        FVector Other=FVector::CrossProduct(Direction,Side).GetSafeNormal();
        for(int32 J=0;J<Spawn&&Particles.Num()<MaxParticles;++J){
            FOrbiterParticle P;P.Rcs=Rcs;P.Life=Shape.lifetime*Random.FRandRange(.8f,1.15f);P.Radius=E.radius;P.Spread=Shape.spread;
            P.Age=Random.FRand()*FMath::Min(DT,double(P.Life));P.Direction=Direction;
            FVector Turbulence=(Side*Random.FRandRange(-1,1)+Other*Random.FRandRange(-1,1))*Shape.speed*Shape.spread*.35;
            P.Velocity=Velocity+Direction*Shape.speed+Turbulence;
            P.Position=Origin+World(E.position)+(Side*Random.FRandRange(-1,1)+Other*Random.FRandRange(-1,1))*E.radius*.2+(P.Velocity-Velocity)*P.Age;
            P.Opacity=(Rcs?.35f:.15f)*E.level;Particles.Add(P);
        }
    }
    for(int32 I=0;I<MaxParticles;++I){int32 V=I*4;
        if(I>=Particles.Num()){for(int32 K=0;K<4;++K){Vertices[V+K]=FVector::ZeroVector;Colors[V+K]=FLinearColor::Transparent;}continue;}
        const auto &P=Particles[I];FVector Center=(P.Position-Origin)*100,Normal=(Camera-Center).GetSafeNormal();
        FVector Along=(P.Direction-Normal*FVector::DotProduct(P.Direction,Normal)).GetSafeNormal();if(Along.IsNearlyZero())Along=FVector(0,0,1);
        FVector Across=FVector::CrossProduct(Along,Normal).GetSafeNormal();
        float Age=P.Age/P.Life,Radius=P.Radius+P.Age*(P.Rcs?55:400)*P.Spread;
        FVector X=Across*Radius*100,Y=Along*Radius*160;
        Vertices[V]=Center-X-Y;Vertices[V+1]=Center+X-Y;Vertices[V+2]=Center+X+Y;Vertices[V+3]=Center-X+Y;
        float Fade=FMath::Exp(-Age*5)*(1-Age)*P.Opacity;
        FLinearColor Color(P.Rcs?.65f:.22f+(.8f*(1-Age)),P.Rcs?.8f:.45f+.5f*(1-Age),1,Fade);
        for(int32 K=0;K<4;++K)Colors[V+K]=Color;
    }
    TArray<FProcMeshTangent> Tangents;Mesh->UpdateMeshSection_LinearColor(0,Vertices,Normals,UV,Colors,Tangents,false);
}
