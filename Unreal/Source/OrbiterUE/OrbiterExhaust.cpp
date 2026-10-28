#include "OrbiterExhaust.h"
#include "OrbiterFrame.h"
THIRD_PARTY_INCLUDES_START
#include "Exhaust.h"
#include "Aerodynamics.h"
THIRD_PARTY_INCLUDES_END
#include "ProceduralMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "Components/PointLightComponent.h"

static constexpr int32 MaxParticles=1536,MaxNozzles=32;
static constexpr int32 FlameRings=12,FlameSides=12,FlameLayers=2;
static constexpr int32 FlameStride=(FlameRings+1)*(FlameSides+1)*FlameLayers;
static FVector U(const Vector &V){return OrbiterFrame::Point(V);}
static float FlameLength(native::ExhaustKind Kind){
    switch(Kind){
        case native::ExhaustKind::Main:return 12;
        case native::ExhaustKind::Hover:return 5;
        case native::ExhaustKind::Retro:return 3;
        default:return .85f;
    }
}
static void CrossSection(const FVector &Direction,FVector &Side,FVector &Other){
    Side=FVector::CrossProduct(Direction,FVector(0,0,1)).GetSafeNormal();
    if(Side.IsNearlyZero())Side=FVector(1,0,0);
    Other=FVector::CrossProduct(Direction,Side).GetSafeNormal();
}
AOrbiterExhaust::AOrbiterExhaust(){
    Mesh=CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("SoftExhaustParticles"));RootComponent=Mesh;
    Flame=CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("NozzleFlameCores"));Flame->SetupAttachment(Mesh);
    Glow=CreateDefaultSubobject<UPointLightComponent>(TEXT("EngineGlow"));Glow->SetupAttachment(Mesh);
    Glow->SetLightColor(FLinearColor(.25,.5,1));Glow->SetAttenuationRadius(1000);Glow->SetCastShadows(false);
    for(auto *Component:{Mesh.Get(),Flame.Get()}){
        Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Component->SetCastShadow(false);Component->SetCanEverAffectNavigation(false);
    }
}
void AOrbiterExhaust::BeginPlay(){
    Super::BeginPlay();
    Vertices.SetNumZeroed(MaxParticles*4);Normals.Init(FVector(0,0,1),Vertices.Num());Colors.Init(FLinearColor::Transparent,Vertices.Num());
    TArray<int32> Indices;TArray<FProcMeshTangent> Tangents;
    for(int32 I=0;I<MaxParticles;++I){int32 V=I*4;Indices.Append({V,V+1,V+2,V,V+2,V+3});UV.Append({FVector2D(0,0),FVector2D(1,0),FVector2D(1,1),FVector2D(0,1)});}
    Mesh->CreateMeshSection_LinearColor(0,Vertices,Indices,Normals,UV,Colors,Tangents,false);
    if(auto *M=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/Materials/M_Exhaust.M_Exhaust")))Mesh->SetMaterial(0,M);

    FlameVertices.SetNumZeroed(MaxNozzles*FlameStride);FlameNormals.Init(FVector(0,0,1),FlameVertices.Num());
    FlameColors.Init(FLinearColor::Transparent,FlameVertices.Num());Indices.Reset();
    for(int32 E=0;E<MaxNozzles;++E)for(int32 Layer=0;Layer<FlameLayers;++Layer)
        for(int32 Ring=0;Ring<=FlameRings;++Ring)for(int32 Side=0;Side<=FlameSides;++Side){
            FlameUV.Add(FVector2D(float(Ring)/FlameRings,float(Side)/FlameSides));
            if(Ring<FlameRings&&Side<FlameSides){
                int32 A=E*FlameStride+Layer*(FlameRings+1)*(FlameSides+1)+Ring*(FlameSides+1)+Side;
                int32 B=A+FlameSides+1;Indices.Append({A,B,A+1,A+1,B,B+1});
            }
        }
    Flame->CreateMeshSection_LinearColor(0,FlameVertices,Indices,FlameNormals,FlameUV,FlameColors,Tangents,false);
    if(auto *M=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/Materials/M_Flame.M_Flame")))Flame->SetMaterial(0,M);
}
void AOrbiterExhaust::Update(const native::Flight &F,const FVector &Camera,const FTransform &VesselTransform){
    double DT=PreviousTime<0?0:F.elapsed-PreviousTime;PreviousTime=F.elapsed;
    if(DT<0||DT>.5){Particles.Reset();FMemory::Memzero(Credit);DT=0;}
    FVector Origin=U(F.position),Velocity=U(F.velocity);
    // Use the exact transform used by the rendered ship, including its coordinate conversion.
    auto Position=[&](const Vector &V){return VesselTransform.TransformPosition(U(V)*100);};
    auto Direction=[&](const Vector &V){return VesselTransform.TransformVectorNoScale(U(V)).GetSafeNormal();};
    auto Emitters=native::gliderExhaust(F);
    Glow->SetIntensity(F.glider.mainLevel*12000);Glow->SetWorldLocation(Position(Vector(0,0,-8.5)));
    for(int32 I=Particles.Num()-1;I>=0;--I){
        auto &P=Particles[I];P.Age+=DT;
        if(P.Age>P.Life){Particles.RemoveAtSwap(I,1,EAllowShrinking::No);continue;}
        P.Position+=P.Velocity*DT;
    }
    for(int32 I=0;I<int32(Emitters.size())&&I<MaxNozzles;++I){
        const auto &E=Emitters[I];auto Shape=native::plumeShape(F.altitude(),E.kind);const bool Rcs=E.kind==native::ExhaustKind::Rcs;
        const float Length=FlameLength(E.kind)*FMath::Sqrt(E.level);
        double Count=(Rcs?900:1200)*E.level*DT+Credit[I];int32 Spawn=FMath::FloorToInt(Count);Credit[I]=Count-Spawn;
        FVector D=Direction(E.direction),Side,Other;CrossSection(D,Side,Other);
        for(int32 J=0;J<Spawn&&Particles.Num()<MaxParticles;++J){
            FOrbiterParticle P;P.Rcs=Rcs;P.Life=Shape.lifetime*Random.FRandRange(.8f,1.15f);P.Radius=E.radius*.45;P.Spread=Shape.spread*.6;
            P.Age=Random.FRand()*FMath::Min(DT,double(P.Life));P.Direction=D;
            FVector Turbulence=(Side*Random.FRandRange(-1,1)+Other*Random.FRandRange(-1,1))*Shape.speed*P.Spread*.2;
            P.Velocity=Velocity+D*Shape.speed+Turbulence;
            P.Position=Origin+Position(E.position)/100+D*Length*.55+(Side*Random.FRandRange(-1,1)+Other*Random.FRandRange(-1,1))*E.radius*.1+(P.Velocity-Velocity)*P.Age;
            // Thin blue exhaust blends out of the flame; it is not an opaque smoke cone in vacuum.
            P.Opacity=(Rcs?.08f:.035f)*E.level;Particles.Add(P);
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
        FLinearColor Color(.06f,.24f,.9f,FMath::Exp(-Age*4)*(1-Age)*P.Opacity);
        for(int32 K=0;K<4;++K)Colors[V+K]=Color;
    }
    // Continuous three-dimensional cores stay attached to nozzle mouths at every frame rate.
    for(int32 I=0;I<MaxNozzles;++I){
        if(I>=int32(Emitters.size())){
            for(int32 V=I*FlameStride;V<(I+1)*FlameStride;++V){FlameVertices[V]=FVector::ZeroVector;FlameColors[V]=FLinearColor::Transparent;}
            continue;
        }
        const auto &E=Emitters[I];FVector D=Direction(E.direction),Side,Other;CrossSection(D,Side,Other);
        const FVector Mouth=Position(E.position)+D*1.;
        const float Level=FMath::Sqrt(E.level),Length=FlameLength(E.kind)*Level*100;
        for(int32 Layer=0;Layer<FlameLayers;++Layer)for(int32 Ring=0;Ring<=FlameRings;++Ring){
            const float T=float(Ring)/FlameRings;
            const float Ripple=.92f+.08f*FMath::Cos(T*37.7f-F.elapsed*12);
            const float Radius=E.radius*100*(Layer==0?.64f:.98f)*FMath::Pow(1-T,.65f)*Ripple*(.5f+.5f*Level);
            const FVector Center=Mouth+D*Length*T;
            FLinearColor Color=Layer==0?FLinearColor::LerpUsingHSV(FLinearColor(.6,.82,1),FLinearColor(.06,.25,1),T):FLinearColor(.025,.12,1);
            Color.A=(Layer==0?.65f:.12f)*Level*FMath::Pow(1-T,.8f);
            for(int32 S=0;S<=FlameSides;++S){
                const float Angle=S*(2*UE_PI/FlameSides);
                const int32 V=I*FlameStride+Layer*(FlameRings+1)*(FlameSides+1)+Ring*(FlameSides+1)+S;
                FlameVertices[V]=Center+(Side*FMath::Cos(Angle)+Other*FMath::Sin(Angle))*Radius;FlameColors[V]=Color;
            }
        }
    }
    TArray<FProcMeshTangent> Tangents;
    Mesh->UpdateMeshSection_LinearColor(0,Vertices,Normals,UV,Colors,Tangents,false);
    Flame->UpdateMeshSection_LinearColor(0,FlameVertices,FlameNormals,FlameUV,FlameColors,Tangents,false);
}
