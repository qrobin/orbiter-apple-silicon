#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "OrbiterExhaust.generated.h"
namespace native {class Flight;}
class UProceduralMeshComponent;
class UPointLightComponent;
struct FOrbiterParticle {
    FVector Position,Velocity,Direction;
    float Age=0,Life=.1f,Radius=.5f,Spread=.1f,Opacity=1;
    bool Rcs=false;
};
UCLASS()
class AOrbiterExhaust : public AActor {
    GENERATED_BODY()
public:
    AOrbiterExhaust();
    virtual void BeginPlay() override;
    void Update(const native::Flight &Flight,const FVector &Camera);
    int32 ParticleCount() const {return Particles.Num();}
private:
    UPROPERTY() TObjectPtr<UProceduralMeshComponent> Mesh;
    UPROPERTY() TObjectPtr<UPointLightComponent> Glow;
    TArray<FOrbiterParticle> Particles;
    TArray<FVector> Vertices,Normals;
    TArray<FVector2D> UV;
    TArray<FLinearColor> Colors;
    FRandomStream Random{7349};
    double PreviousTime=-1;
    double Credit[32]={};
};
